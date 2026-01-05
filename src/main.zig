const std = @import("std");
const httpServer = @import("Http/Server/server.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var http_server = try httpServer.create(42069, handleError);
    try http_server.run(allocator);
    defer http_server.deinit();
}

fn handleError(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    r: *httpServer.Request.Request,
) !httpServer.HandlerResult {
    const request_line = r.request_line orelse return httpServer.Request.Error.MalformedRequestLine;

    if (std.mem.eql(u8, request_line.request_target, "/yourproblem")) {
        return httpServer.HandlerResult.Failed(
            "You did something wrong",
            httpServer.Response.StatusCode.StatusBadRequest,
        );
    }
    if (std.mem.eql(u8, request_line.request_target, "/myproblem")) {
        return httpServer.HandlerResult.Failed(
            "Ooops my bad",
            httpServer.Response.StatusCode.StatusInternalServerError,
        );
    }
    _ = try writer.write("All good frfr\n");
    _ = allocator;
    return httpServer.HandlerResult.Success();
}
