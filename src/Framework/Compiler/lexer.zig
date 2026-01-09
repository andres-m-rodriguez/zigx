//PSA: There will be more comments here due to me...sucking...at lexers...BADLY
//I always genuinely forget the token kinds
const std = @import("std");

pub const TokenKind = enum {
    HtmlText,
    ServerBlock, // @server{...}
    ClientBlock, // @client{...}
    Expression, // @identifier
    ExpressionBlock, // @{...}
    RouteDirective, // @route("...")
    Eof,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
};

pub const Lexer = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    token_buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, reader: *std.Io.Reader) Lexer {
        return .{
            .reader = reader,
            .allocator = allocator,
            .token_buf = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.token_buf.deinit(self.allocator);
    }

    pub fn next(self: *Lexer) !Token {
        self.token_buf.clearRetainingCapacity();

        const first_byte = self.reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => return Token{ .kind = .Eof, .lexeme = "" },
            else => return err,
        };

        if (first_byte == '@') {
            return try self.lexAtSign();
        }

        try self.token_buf.append(self.allocator, first_byte);
        return try self.lexHtmlText();
    }

    fn lexAtSign(self: *Lexer) !Token {
        // Peek at next character to determine what kind of @ token
        const next_byte = self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => {
                // Just a lone @ at end of file, which should be just html??? maybe???
                try self.token_buf.append(self.allocator, '@');
                return Token{ .kind = .HtmlText, .lexeme = self.token_buf.items };
            },
            else => return err,
        };

        if (next_byte == '{') {
            // @{...} expression block
            _ = try self.reader.takeByte(); // consume '{'
            return try self.lexBraceBlock(.ExpressionBlock);
        }

        if (isIdentifierStart(next_byte)) {
            // Could be @server{, @client{, or @identifier
            return try self.lexAtIdentifier();
        }

        // Not a valid @ sequence, treat '@' as HTML text
        try self.token_buf.append(self.allocator, '@');
        return try self.lexHtmlText();
    }

    fn lexAtIdentifier(self: *Lexer) !Token {
        // Read identifier chars (a-z, A-Z, 0-9, _) until we hit a non-identifier char
        // This builds up the identifier name after '@' (e.g., "server", "client", "myVar")
        while (true) {
            const byte = self.reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (isIdentifierChar(byte)) {
                try self.token_buf.append(self.allocator, byte);
                _ = try self.reader.takeByte();
            } else {
                break;
            }
        }

        const identifier = self.token_buf.items;

        // Check if followed by '{'
        const next_byte = self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => {
                // Just an identifier expression
                return Token{ .kind = .Expression, .lexeme = identifier };
            },
            else => return err,
        };

        if (next_byte == '{') {
            _ = try self.reader.takeByte(); // consume '{'

            if (std.mem.eql(u8, identifier, "server")) {
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(.ServerBlock);
            } else if (std.mem.eql(u8, identifier, "client")) {
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(.ClientBlock);
            } else {
                // Unknown @identifier{ - treat the content as expression block
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(.ExpressionBlock);
            }
        }

        // Check for @route("...")
        if (std.mem.eql(u8, identifier, "route") and next_byte == '(') {
            _ = try self.reader.takeByte(); // consume '('
            return try self.lexRouteDirective();
        }

        // Just an expression like @myVariable
        return Token{ .kind = .Expression, .lexeme = identifier };
    }

    fn lexRouteDirective(self: *Lexer) !Token {
        self.token_buf.clearRetainingCapacity();

        // Skip whitespace and find opening quote
        while (true) {
            const byte = self.reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => return Token{ .kind = .RouteDirective, .lexeme = "" },
                else => return err,
            };
            if (byte == '"') break;
            // Skip whitespace before quote
            if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') {
                // Invalid format, return empty
                return Token{ .kind = .RouteDirective, .lexeme = "" };
            }
        }

        // Read until closing quote
        while (true) {
            const byte = self.reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            if (byte == '"') break;
            try self.token_buf.append(self.allocator, byte);
        }

        // Skip to closing paren
        while (true) {
            const byte = self.reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            if (byte == ')') break;
        }

        return Token{ .kind = .RouteDirective, .lexeme = self.token_buf.items };
    }

    fn lexBraceBlock(self: *Lexer, kind: TokenKind) !Token {
        var brace_depth: usize = 1;

        while (brace_depth > 0) { // Praying that I don't get this wrong...I always get brace depth wrong...
            const byte = self.reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => {
                    // Unclosed brace - return what we have
                    return Token{ .kind = kind, .lexeme = self.token_buf.items };
                },
                else => return err,
            };

            if (byte == '{') {
                brace_depth += 1;
                try self.token_buf.append(self.allocator, byte);
            } else if (byte == '}') {
                brace_depth -= 1;
                if (brace_depth > 0) {
                    try self.token_buf.append(self.allocator, byte);
                }
                // Don't append the final closing brace
            } else {
                try self.token_buf.append(self.allocator, byte);
            }
        }

        return Token{ .kind = kind, .lexeme = self.token_buf.items };
    }

    fn lexHtmlText(self: *Lexer) !Token {
        while (true) {
            const byte = self.reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (byte == '@') {
                // Stop before '@', next call will handle it
                break;
            }

            try self.token_buf.append(self.allocator, byte);
            _ = try self.reader.takeByte();
        }

        return Token{ .kind = .HtmlText, .lexeme = self.token_buf.items };
    }

    fn isIdentifierStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isIdentifierChar(c: u8) bool {
        return isIdentifierStart(c) or (c >= '0' and c <= '9');
    }
};
