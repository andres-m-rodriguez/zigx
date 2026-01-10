const std = @import("std");
const ZigLexer = @import("lexer.zig").ZigLexer;

/// Parsed Zig file info
pub const ZigFile = struct {
    imports: std.ArrayList([]const u8),

    pub fn deinit(self: *ZigFile, allocator: std.mem.Allocator) void {
        self.imports.deinit(allocator);
    }

    /// Check if this file imports a specific module
    pub fn hasImport(self: *const ZigFile, import_name: []const u8) bool {
        for (self.imports.items) |imp| {
            if (std.mem.eql(u8, imp, import_name)) {
                return true;
            }
        }
        return false;
    }
};

pub const ZigParser = struct {
    source: []const u8,

    pub fn init(source: []const u8) ZigParser {
        return .{
            .source = source,
        };
    }

    /// Parse the source and extract all imports
    pub fn parse(self: *ZigParser, allocator: std.mem.Allocator) !ZigFile {
        var lexer = ZigLexer.init(self.source);
        const imports = try lexer.findImports(allocator);

        return ZigFile{
            .imports = imports,
        };
    }
};
