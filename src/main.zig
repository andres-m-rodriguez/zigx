const std = @import("std");

const httpServer = @import("Http/Server/server.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var http_server = try httpServer.create(42069);
    try http_server.run(allocator);
    defer http_server.deinit();
}
