const std = @import("std");
const header = @import("../Headers/headers.zig");
pub const Response = struct {};

pub const StatusCode = enum(u16) {
    StatusOk = 200,
    StatusBadRequest = 400,
    StatusInternalServerError = 500,
};

pub fn writeStatusLine(writer: *std.Io.Writer, statusCode: StatusCode) !void {
    const status_line = switch (statusCode) {
        .StatusOk => "HTTP/1.1 200 OK\r\n",
        .StatusBadRequest => "HTTP/1.1 400 Bad Request\r\n",
        .StatusInternalServerError => "HTTP/1.1 500 Internal Server Error\r\n",
    };
    try writer.writeAll(status_line);
}
pub fn getDefaultHeaders(allocator: std.mem.Allocator, content_length: usize) !header.Headers {
    var h = header.Headers{};
    errdefer h.deinit(allocator);

    // Convert usize to string
    const content_len_str = try std.fmt.allocPrint(allocator, "{d}", .{content_length});

    try h.set("Content-Length", content_len_str, allocator);
    try h.set("Connection", "close", allocator);
    try h.set("Content-Type", "text/plain", allocator);

    return h;
}

pub fn writeHeaders(writer: *std.Io.Writer, headers: header.Headers) !void {
    var headers_iterator = headers.iterator();
    while (headers_iterator.next()) |header_entry| {
        try writer.print("{s}:{s}\r\n", .{ header_entry.key_ptr.*, header_entry.value_ptr.* });
    }

    try writer.print("\r\n", .{});
}
