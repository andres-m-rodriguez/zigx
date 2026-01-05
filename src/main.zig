const std = @import("std");
const httpServer = @import("Http/Server/server.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var http_server = try httpServer.create(42069, handle);
    try http_server.run(allocator);
    defer http_server.deinit();
}

fn handle(
    allocator: std.mem.Allocator,
    writer: *httpServer.Response.ResponseWriter,
    r: *httpServer.Request.Request,
) !httpServer.HandlerResult {
    var default_headers = try httpServer.Response.getDefaultHeaders(allocator, 0);
    defer default_headers.deinit(allocator);

    var body_buffer = std.ArrayList(u8){};
    defer body_buffer.deinit(allocator);
    try body_buffer.appendSlice(allocator, response200());
    var status_code = httpServer.Response.StatusCode.StatusOk;
    const request_line = r.request_line orelse return httpServer.Request.Error.MalformedRequestLine;

    try default_headers.replace("Content-Type", "text/html", allocator);

    if (std.mem.eql(u8, request_line.request_target, "/yourproblem")) {
        body_buffer.clearRetainingCapacity(); // clear existing content
        try body_buffer.appendSlice(allocator, response400());
        status_code = httpServer.Response.StatusCode.StatusBadRequest;
    } else if (std.mem.eql(u8, request_line.request_target, "/myproblem")) {
        body_buffer.clearRetainingCapacity();
        try body_buffer.appendSlice(allocator, response500());
        status_code = httpServer.Response.StatusCode.StatusInternalServerError;
    } else if (std.mem.startsWith(u8, request_line.request_target, "/httpbin/stream/")) {
        const number_str = request_line.request_target["/httpbin/stream/".len..];
        const number = std.fmt.parseInt(u32, number_str, 10) catch unreachable;

        var url_buf: [256]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buf, "http://httpbin.org/stream/{d}", .{number});

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const uri = try std.Uri.parse(url);
        var req = try client.request(.GET, uri, .{});
        defer req.deinit();
        try req.sendBodiless();
        var redirect_buf: [4096]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);
        const reader = response.reader(&.{});

        if (!(response.head.status.class() == .success)) {
            body_buffer.clearRetainingCapacity();
            try body_buffer.appendSlice(allocator, response500());
            status_code = httpServer.Response.StatusCode.StatusInternalServerError;
        }

        _ = default_headers.delete("Content-Length", allocator);
        try default_headers.replace("Content-Type", "text/plain", allocator);
        try default_headers.set("Transfer-Encoding", "chunked", allocator);
        //
        try writer.writeStatusLine(httpServer.Response.StatusCode.StatusOk);
        try writer.writeHeaders(&default_headers);

        var read_all = try writer.writeChunk(reader);

        while (read_all) {
            read_all = try writer.writeChunk(reader);
        }

        try writer.writeChunkEnd();
        return httpServer.HandlerResult.Success();
    }

    const body_length = body_buffer.items.len;
    var body_lenght_buf: [20]u8 = undefined;
    const length_str = std.fmt.bufPrint(&body_lenght_buf, "{d}", .{body_length}) catch unreachable;
    default_headers.replace("Content-Length", length_str, allocator) catch unreachable;

    writer.writeStatusLine(httpServer.Response.StatusCode.StatusOk) catch unreachable;
    writer.writeHeaders(&default_headers) catch unreachable;
    _ = try writer.writeBody(body_buffer.items);
    return httpServer.HandlerResult.Success();
}
fn response500() []const u8 {
    return 
    \\<html>
    \\  <head>
    \\    <title>500 Internal Server Error</title>
    \\  </head>
    \\  <body>
    \\    <h1>Internal Server Error</h1>
    \\    <p>Okay, you know what? This one is on me.</p>
    \\  </body>
    \\</html>
    ;
}
fn response400() []const u8 {
    return 
    \\<html>
    \\  <head>
    \\    <title>400 Bad Request</title>
    \\  </head>
    \\  <body>
    \\    <h1>Bad Request</h1>
    \\    <p>Your request honestly kinda sucked.</p>
    \\  </body>
    \\</html>
    ;
}
fn response200() []const u8 {
    return 
    \\<html>
    \\  <head>
    \\    <title>200 OK</title>
    \\  </head>
    \\  <body>
    \\    <h1>Success!</h1>
    \\    <p>Your request was an absolute banger.</p>
    \\  </body>
    \\</html>
    ;
}
