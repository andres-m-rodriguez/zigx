const std = @import("std");

pub const ZigLexer = struct {
    source: []const u8,
    pos: usize = 0,

    pub fn init(source: []const u8) ZigLexer {
        return .{ .source = source };
    }

    pub fn findImports(self: *ZigLexer, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var imports = std.ArrayList([]const u8){};

        while (self.pos < self.source.len) {
            if (self.matchImport()) {
                self.skipWhitespace();
                if (self.pos < self.source.len and self.source[self.pos] == '(') {
                    self.pos += 1;
                    self.skipWhitespace();
                    if (self.pos < self.source.len and self.source[self.pos] == '"') {
                        if (self.readString()) |str| {
                            try imports.append(allocator, str);
                        }
                    }
                }
            } else {
                self.pos += 1;
            }
        }

        return imports;
    }

    fn matchImport(self: *ZigLexer) bool {
        const pattern = "@import";
        if (self.pos + pattern.len > self.source.len) return false;

        if (std.mem.eql(u8, self.source[self.pos .. self.pos + pattern.len], pattern)) {
            self.pos += pattern.len;
            return true;
        }
        return false;
    }

    fn skipWhitespace(self: *ZigLexer) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }

    fn readString(self: *ZigLexer) ?[]const u8 {
        if (self.source[self.pos] != '"') return null;
        self.pos += 1; // skip opening quote

        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') {
                self.pos += 2; // skip escape sequence
            } else {
                self.pos += 1;
            }
        }

        if (self.pos >= self.source.len) return null;

        const str = self.source[start..self.pos];
        self.pos += 1; // skip closing quote
        return str;
    }
};

test "find imports" {
    const source =
        \\const std = @import("std");
        \\const fs = @import("std").fs;
        \\const MyModule = @import("./path/to/module.zig");
    ;

    var lexer = ZigLexer.init(source);
    var imports = try lexer.findImports(std.testing.allocator);
    defer imports.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), imports.items.len);
    try std.testing.expectEqualStrings("std", imports.items[0]);
    try std.testing.expectEqualStrings("std", imports.items[1]);
    try std.testing.expectEqualStrings("./path/to/module.zig", imports.items[2]);
}
