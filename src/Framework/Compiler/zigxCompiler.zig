const std = @import("std");
const lexer = @import("lexer.zig");

pub const ZigxDocument = struct {
    allocator: std.mem.Allocator,
    file_name: []const u8,
    route: []const u8, // Route path (from @route or defaults to /file_name)
    html_content: []const u8,
    server_code: []const u8,
    client_code: []const u8,
    expressions: []const []const u8,

    pub fn deinit(self: *ZigxDocument) void {
        self.allocator.free(self.file_name);
        self.allocator.free(self.route);
        self.allocator.free(self.html_content);
        self.allocator.free(self.server_code);
        self.allocator.free(self.client_code);
        for (self.expressions) |expr| {
            self.allocator.free(expr);
        }
        self.allocator.free(self.expressions);
    }
};

pub fn parse(allocator: std.mem.Allocator, reader: *std.Io.Reader, file_name: []const u8) !ZigxDocument {
    var html_buf = std.ArrayList(u8){};
    errdefer html_buf.deinit(allocator);

    var server_buf = std.ArrayList(u8){};
    errdefer server_buf.deinit(allocator);

    var client_buf = std.ArrayList(u8){};
    errdefer client_buf.deinit(allocator);

    var expressions = std.ArrayList([]const u8){};
    errdefer {
        for (expressions.items) |expr| {
            allocator.free(expr);
        }
        expressions.deinit(allocator);
    }

    var zigx_lexer = lexer.Lexer.init(allocator, reader);
    defer zigx_lexer.deinit();

    var custom_route: ?[]const u8 = null;
    errdefer if (custom_route) |r| allocator.free(r);

    while (true) {
        const token = try zigx_lexer.next();

        switch (token.kind) {
            .Eof => break,
            .RouteDirective => {
                // @route("/path") - store the custom route
                if (token.lexeme.len > 0) {
                    custom_route = try allocator.dupe(u8, token.lexeme);
                }
            },
            .HtmlText => {
                try html_buf.appendSlice(allocator, token.lexeme);
            },
            .ServerBlock => {
                try server_buf.appendSlice(allocator, token.lexeme);
            },
            .ClientBlock => {
                try client_buf.appendSlice(allocator, token.lexeme);
            },
            .Expression, .ExpressionBlock => {
                const expr_copy = try allocator.dupe(u8, token.lexeme);
                errdefer allocator.free(expr_copy);

                // Adds unique placeholder: __ZIGX_EXPR_N__ (I will cry if this SOMEHOW conflicts with anyone's HTML)
                var placeholder_buf: [32]u8 = undefined;
                const placeholder = std.fmt.bufPrint(&placeholder_buf, "__ZIGX_EXPR_{d}__", .{expressions.items.len}) catch unreachable;
                try html_buf.appendSlice(allocator, placeholder);

                try expressions.append(allocator, expr_copy);
            },
        }
    }

    const owned_file_name = try allocator.dupe(u8, file_name);
    errdefer allocator.free(owned_file_name);

    // Use custom route if provided, otherwise default to /file_name
    const route = if (custom_route) |r| r else try std.fmt.allocPrint(allocator, "/{s}", .{file_name});
    errdefer if (custom_route == null) allocator.free(route);

    return ZigxDocument{
        .allocator = allocator,
        .file_name = owned_file_name,
        .route = route,
        .html_content = try html_buf.toOwnedSlice(allocator),
        .server_code = try server_buf.toOwnedSlice(allocator),
        .client_code = try client_buf.toOwnedSlice(allocator),
        .expressions = try expressions.toOwnedSlice(allocator),
    };
}
