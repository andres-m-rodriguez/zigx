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
    ForBlock, // @for(collection) |capture| { body }
    IfBlock, // @if(condition) { body } optionally with else
    WhileBlock, // @while(condition) |capture| { body }
    EventHandler, // @onclick=handler_name
    Eof,
};

/// Data for control flow tokens (@for, @if, @while)
pub const ControlFlowData = struct {
    param: []const u8, // collection for @for, condition for @if/@while
    capture: ?[]const u8, // |var| capture for @for/@while, null for @if
    body: []const u8, // content inside { }
    else_body: ?[]const u8, // else branch for @if, null otherwise
};

/// Data for event handler tokens (@onclick=handler)
pub const EventHandlerData = struct {
    event: []const u8, // "onclick", "onchange", etc.
    handler: []const u8, // function name to call
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    control_flow: ?ControlFlowData = null,
    event_handler: ?EventHandlerData = null,
};

pub const Lexer = struct {
    reader: *std.Io.Reader,
    token_buf: std.ArrayList(u8),
    // Pending identifier from failed @else check (e.g., saw @client instead of @else)
    pending_at_identifier: ?[]const u8 = null,

    pub fn init(reader: *std.Io.Reader) Lexer {
        return .{
            .reader = reader,
            .token_buf = std.ArrayList(u8){},
            .pending_at_identifier = null,
        };
    }

    pub fn deinit(self: *Lexer, allocator: std.mem.Allocator) void {
        self.token_buf.deinit(allocator);
        if (self.pending_at_identifier) |ident| {
            allocator.free(ident);
        }
    }

    pub fn next(self: *Lexer, allocator: std.mem.Allocator) !Token {
        self.token_buf.clearRetainingCapacity();

        // If we have a pending @identifier from a failed @else check, process it
        if (self.pending_at_identifier) |ident| {
            self.pending_at_identifier = null;
            // Copy to token_buf and process as if we just read @identifier
            try self.token_buf.appendSlice(allocator, ident);
            allocator.free(ident);
            return try self.processAtIdentifier(allocator);
        }

        const first_byte = self.reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => return Token{ .kind = .Eof, .lexeme = "" },
            else => return err,
        };

        if (first_byte == '@') {
            return try self.lexAtSign(allocator);
        }

        try self.token_buf.append(allocator, first_byte);
        return try self.lexHtmlText(allocator);
    }

    fn lexAtSign(self: *Lexer, allocator: std.mem.Allocator) !Token {
        // Peek at next character to determine what kind of @ token
        const next_byte = self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => {
                // Just a lone @ at end of file, which should be just html??? maybe???
                try self.token_buf.append(allocator, '@');
                return Token{ .kind = .HtmlText, .lexeme = self.token_buf.items };
            },
            else => return err,
        };

        if (next_byte == '{') {
            // @{...} expression block
            _ = try self.reader.takeByte(); // consume '{'
            return try self.lexBraceBlock(allocator, .ExpressionBlock);
        }

        if (isIdentifierStart(next_byte)) {
            // Could be @server{, @client{, or @identifier
            return try self.lexAtIdentifier(allocator);
        }

        // Not a valid @ sequence, treat '@' as HTML text
        try self.token_buf.append(allocator, '@');
        return try self.lexHtmlText(allocator);
    }

    fn lexAtIdentifier(self: *Lexer, allocator: std.mem.Allocator) !Token {
        // Read identifier chars (a-z, A-Z, 0-9, _) until we hit a non-identifier char
        // This builds up the identifier name after '@' (e.g., "server", "client", "myVar")
        while (true) {
            const byte = self.reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (isIdentifierChar(byte)) {
                try self.token_buf.append(allocator, byte);
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
                return try self.lexBraceBlock(allocator, .ServerBlock);
            } else if (std.mem.eql(u8, identifier, "client")) {
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(allocator, .ClientBlock);
            } else {
                // Unknown @identifier{ - treat the content as expression block
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(allocator, .ExpressionBlock);
            }
        }

        // Check for @route("...")
        if (std.mem.eql(u8, identifier, "route") and next_byte == '(') {
            _ = try self.reader.takeByte(); // consume '('
            return try self.lexRouteDirective(allocator);
        }

        // Check for control flow: @for(...), @if(...), @while(...)
        if (next_byte == '(') {
            if (std.mem.eql(u8, identifier, "for")) {
                return try self.lexForBlock(allocator);
            } else if (std.mem.eql(u8, identifier, "if")) {
                return try self.lexIfBlock(allocator);
            } else if (std.mem.eql(u8, identifier, "while")) {
                return try self.lexWhileBlock(allocator);
            }
        }

        // Check for event handler: @onclick=handler_name
        if (next_byte == '=') {
            _ = try self.reader.takeByte(); // consume '='
            return try self.lexEventHandler(allocator, identifier);
        }

        // Just an expression like @myVariable
        return Token{ .kind = .Expression, .lexeme = identifier };
    }

    /// Processes an @identifier that was already read (used for pending_at_identifier from @else check)
    fn processAtIdentifier(self: *Lexer, allocator: std.mem.Allocator) !Token {
        const identifier = self.token_buf.items;

        // Check if followed by '{'
        const next_byte = self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => {
                return Token{ .kind = .Expression, .lexeme = identifier };
            },
            else => return err,
        };

        if (next_byte == '{') {
            _ = try self.reader.takeByte(); // consume '{'

            if (std.mem.eql(u8, identifier, "server")) {
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(allocator, .ServerBlock);
            } else if (std.mem.eql(u8, identifier, "client")) {
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(allocator, .ClientBlock);
            } else {
                self.token_buf.clearRetainingCapacity();
                return try self.lexBraceBlock(allocator, .ExpressionBlock);
            }
        }

        // Check for @route("...")
        if (std.mem.eql(u8, identifier, "route") and next_byte == '(') {
            _ = try self.reader.takeByte(); // consume '('
            return try self.lexRouteDirective(allocator);
        }

        // Check for control flow: @for(...), @if(...), @while(...)
        if (next_byte == '(') {
            if (std.mem.eql(u8, identifier, "for")) {
                return try self.lexForBlock(allocator);
            } else if (std.mem.eql(u8, identifier, "if")) {
                return try self.lexIfBlock(allocator);
            } else if (std.mem.eql(u8, identifier, "while")) {
                return try self.lexWhileBlock(allocator);
            }
        }

        // Check for event handler: @onclick=handler_name
        if (next_byte == '=') {
            _ = try self.reader.takeByte(); // consume '='
            return try self.lexEventHandler(allocator, identifier);
        }

        // Just an expression like @myVariable
        return Token{ .kind = .Expression, .lexeme = identifier };
    }

    fn lexRouteDirective(self: *Lexer, allocator: std.mem.Allocator) !Token {
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
            try self.token_buf.append(allocator, byte);
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

    /// Lexes @eventname=handler (e.g., @onclick=increment)
    fn lexEventHandler(self: *Lexer, allocator: std.mem.Allocator, event_name: []const u8) !Token {
        // Save event name (already in token_buf from lexAtIdentifier)
        const event = try allocator.dupe(u8, event_name);
        errdefer allocator.free(event);

        // Read handler name until whitespace or '>'
        var handler_buf = std.ArrayList(u8){};
        errdefer handler_buf.deinit(allocator);

        while (true) {
            const byte = self.reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            // Stop at whitespace, '>', or other delimiters
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == '>') {
                break;
            }

            try handler_buf.append(allocator, byte);
            _ = try self.reader.takeByte();
        }

        const handler = try handler_buf.toOwnedSlice(allocator);

        return Token{
            .kind = .EventHandler,
            .lexeme = event,
            .event_handler = .{
                .event = event,
                .handler = handler,
            },
        };
    }

    fn lexBraceBlock(self: *Lexer, allocator: std.mem.Allocator, kind: TokenKind) !Token {
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
                try self.token_buf.append(allocator, byte);
            } else if (byte == '}') {
                brace_depth -= 1;
                if (brace_depth > 0) {
                    try self.token_buf.append(allocator, byte);
                }
                // Don't append the final closing brace
            } else {
                try self.token_buf.append(allocator, byte);
            }
        }

        return Token{ .kind = kind, .lexeme = self.token_buf.items };
    }

    fn lexHtmlText(self: *Lexer, allocator: std.mem.Allocator) !Token {
        while (true) {
            const byte = self.reader.peekByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            if (byte == '@') {
                // Stop before '@', next call will handle it
                break;
            }

            try self.token_buf.append(allocator, byte);
            _ = try self.reader.takeByte();
        }

        return Token{ .kind = .HtmlText, .lexeme = self.token_buf.items };
    }

    /// Lexes @for(collection) |capture| { body }
    fn lexForBlock(self: *Lexer, allocator: std.mem.Allocator) !Token {
        // We've already read "@for", now expect (collection) |capture| { body }
        _ = try self.reader.takeByte();

        // Read collection expression until ')'
        const param = try self.readParenContent(allocator);

        // Skip whitespace
        try self.skipWhitespace();

        // Expect |capture|
        const capture = try self.readPipeCapture(allocator);

        // Skip whitespace
        try self.skipWhitespace();

        // Expect { body }
        const byte = self.reader.peekByte() catch return error.UnexpectedEof;
        if (byte != '{') return error.ExpectedOpenBrace;
        _ = try self.reader.takeByte(); // consume '{'

        const body = try self.readBraceContent(allocator);

        return Token{
            .kind = .ForBlock,
            .lexeme = "",
            .control_flow = .{
                .param = param,
                .capture = capture,
                .body = body,
                .else_body = null,
            },
        };
    }

    /// Lexes @if(condition) { body } with optional @else { else_body }
    fn lexIfBlock(self: *Lexer, allocator: std.mem.Allocator) !Token {
        _ = try self.reader.takeByte(); // consume '('

        // Read condition until ')'
        const condition = try self.readParenContent(allocator);

        // Skip whitespace
        try self.skipWhitespace();

        // Expect { body }
        const byte = self.reader.peekByte() catch return error.UnexpectedEof;
        if (byte != '{') return error.ExpectedOpenBrace;
        _ = try self.reader.takeByte(); // consume '{'

        const body = try self.readBraceContent(allocator);

        // Check for @else
        try self.skipWhitespace();
        const else_body = try self.tryReadElseBlock(allocator);

        return Token{
            .kind = .IfBlock,
            .lexeme = "",
            .control_flow = .{
                .param = condition,
                .capture = null,
                .body = body,
                .else_body = else_body,
            },
        };
    }

    /// Lexes @while(condition) |capture| { body } - capture is optional
    fn lexWhileBlock(self: *Lexer, allocator: std.mem.Allocator) !Token {
        _ = try self.reader.takeByte(); // consume '('

        // Read condition until ')'
        const condition = try self.readParenContent(allocator);

        // Skip whitespace
        try self.skipWhitespace();

        // Check for optional |capture|
        var capture: ?[]const u8 = null;
        const peek = self.reader.peekByte() catch null;
        if (peek == '|') {
            capture = try self.readPipeCapture(allocator);
            try self.skipWhitespace();
        }

        // Expect { body }
        const byte = self.reader.peekByte() catch return error.UnexpectedEof;
        if (byte != '{') return error.ExpectedOpenBrace;
        _ = try self.reader.takeByte(); // consume '{'

        const body = try self.readBraceContent(allocator);

        return Token{
            .kind = .WhileBlock,
            .lexeme = "",
            .control_flow = .{
                .param = condition,
                .capture = capture,
                .body = body,
                .else_body = null,
            },
        };
    }

    // ============================================
    // Helper functions for control flow lexing
    // ============================================

    fn skipWhitespace(self: *Lexer) !void {
        while (true) {
            const byte = self.reader.peekByte() catch return;
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') {
                _ = try self.reader.takeByte();
            } else {
                break;
            }
        }
    }

    /// Reads content inside () with proper nesting, allocates and returns owned slice
    fn readParenContent(self: *Lexer, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);

        var depth: usize = 1;
        while (depth > 0) {
            const byte = self.reader.takeByte() catch return error.UnexpectedEof;
            if (byte == '(') {
                depth += 1;
                try buf.append(allocator, byte);
            } else if (byte == ')') {
                depth -= 1;
                if (depth > 0) {
                    try buf.append(allocator, byte);
                }
            } else {
                try buf.append(allocator, byte);
            }
        }
        return try buf.toOwnedSlice(allocator);
    }

    /// Reads |capture| and returns the capture name (allocates)
    fn readPipeCapture(self: *Lexer, allocator: std.mem.Allocator) ![]const u8 {
        const first = self.reader.peekByte() catch return error.UnexpectedEof;
        if (first != '|') return error.ExpectedPipe;
        _ = try self.reader.takeByte(); // consume '|'

        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);

        while (true) {
            const byte = self.reader.takeByte() catch return error.UnexpectedEof;
            if (byte == '|') break;
            try buf.append(allocator, byte);
        }
        return try buf.toOwnedSlice(allocator);
    }

    /// Reads content inside {} with proper nesting, allocates and returns owned slice
    fn readBraceContent(self: *Lexer, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);

        var depth: usize = 1;
        while (depth > 0) {
            const byte = self.reader.takeByte() catch return error.UnexpectedEof;
            if (byte == '{') {
                depth += 1;
                try buf.append(allocator, byte);
            } else if (byte == '}') {
                depth -= 1;
                if (depth > 0) {
                    try buf.append(allocator, byte);
                }
            } else {
                try buf.append(allocator, byte);
            }
        }
        return try buf.toOwnedSlice(allocator);
    }

    /// Tries to read @else { body }, returns null if not present
    fn tryReadElseBlock(self: *Lexer, allocator: std.mem.Allocator) !?[]const u8 {
        // Check if next is '@else' using lookahead (don't consume until sure)
        const first = self.reader.peekByte() catch return null;
        if (first != '@') return null;

        // Peek ahead to check if it's "@else" - read into buffer without consuming
        var peek_buf: [5]u8 = undefined; // "@else" is 5 chars
        var peek_len: usize = 0;

        // We already know first byte is '@', so peek the next 4 bytes for "else"
        _ = self.reader.takeByte() catch return null; // consume '@'
        peek_buf[0] = '@';
        peek_len = 1;

        // Read up to 4 more chars to check for "else"
        var ident_buf = std.ArrayList(u8){};
        defer ident_buf.deinit(allocator);

        while (ident_buf.items.len < 10) { // reasonable limit
            const byte = self.reader.peekByte() catch break;
            if (isIdentifierChar(byte)) {
                try ident_buf.append(allocator, byte);
                _ = try self.reader.takeByte();
            } else {
                break;
            }
        }

        if (!std.mem.eql(u8, ident_buf.items, "else")) {
            // Not @else - store the consumed identifier so it can be processed as a new token
            // The next call to next() will pick this up via pending_at_identifier
            self.pending_at_identifier = try allocator.dupe(u8, ident_buf.items);
            return null;
        }

        // Skip whitespace after @else
        try self.skipWhitespace();

        // Expect {
        const brace = self.reader.peekByte() catch return error.UnexpectedEof;
        if (brace != '{') return error.ExpectedOpenBrace;
        _ = try self.reader.takeByte();

        return try self.readBraceContent(allocator);
    }

    fn isIdentifierStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isIdentifierChar(c: u8) bool {
        return isIdentifierStart(c) or (c >= '0' and c <= '9');
    }
};
