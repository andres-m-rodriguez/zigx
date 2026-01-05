const std = @import("std");
const Server = @import("../server.zig");
const Request = Server.Request;
const Response = Server.Response;
const net = std.net;

fn testHandler(
    allocator: std.mem.Allocator,
    writer: *Response.ResponseWriter,
    req: *Request.Request,
) !Server.HandlerResult {
    _ = allocator;
    const request_line = req.request_line orelse return Request.Error.MalformedRequestLine;

    if (std.mem.eql(u8, request_line.request_target, "/error")) {
        return Server.HandlerResult.Failed(
            "Error response",
            Response.StatusCode.StatusBadRequest,
        );
    }

    _ = try writer.writer.write("OK");
    return Server.HandlerResult.Success();
}

test "no memory leaks - success path" {
    const allocator = std.testing.allocator;

    // Simulate what handleConnection does
    var default_headers = try Response.getDefaultHeaders(allocator, 0);
    defer default_headers.deinit(allocator);

    const data = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var req = try Request.requestFromReader(&reader, allocator);
    defer req.deinit(allocator);

    var body_buffer: std.ArrayList(u8) = .empty;
    defer body_buffer.deinit(allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &body_buffer);
    var response_writer = Response.ResponseWriter{
        .writer = &aw.writer,
    };

    const result = try testHandler(allocator, &response_writer, &req);
    try std.testing.expect(result == .success);

    body_buffer = aw.toArrayList();
    const body_length = body_buffer.items.len;
    var body_length_buf: [20]u8 = undefined;
    const length_str = std.fmt.bufPrint(&body_length_buf, "{d}", .{body_length}) catch unreachable;
    try default_headers.replace("Content-Length", length_str, allocator);
}

test "no memory leaks - error path" {
    const allocator = std.testing.allocator;

    var default_headers = try Response.getDefaultHeaders(allocator, 0);
    defer default_headers.deinit(allocator);

    const data = "GET /error HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var req = try Request.requestFromReader(&reader, allocator);
    defer req.deinit(allocator);

    var body_buffer: std.ArrayList(u8) = .empty;
    defer body_buffer.deinit(allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &body_buffer);
    var response_writer = Response.ResponseWriter{
        .writer = &aw.writer,
    };

    const result = try testHandler(allocator, &response_writer, &req);
    try std.testing.expect(result == .failed);

    // Simulate error response path
    var len_buf: [20]u8 = undefined;
    const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{result.failed.message.len}) catch unreachable;
    try default_headers.replace("Content-Length", len_str, allocator);
}

test "no memory leaks - multiple requests" {
    const allocator = std.testing.allocator;

    const requests = [_][]const u8{
        "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "POST /data HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nhello",
        "GET /error HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "PUT /update HTTP/1.1\r\nHost: localhost\r\nContent-Length: 11\r\n\r\nsome update",
    };

    for (requests) |data| {
        var default_headers = try Response.getDefaultHeaders(allocator, 0);
        defer default_headers.deinit(allocator);

        var reader: std.Io.Reader = .fixed(data);
        var req = try Request.requestFromReader(&reader, allocator);
        defer req.deinit(allocator);

        var body_buffer: std.ArrayList(u8) = .empty;
        defer body_buffer.deinit(allocator);
        var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &body_buffer);
        var response_writer = Response.ResponseWriter{
            .writer = &aw.writer,
        };

        const result = try testHandler(allocator, &response_writer, &req);

        if (result == .failed) {
            var len_buf: [20]u8 = undefined;
            const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{result.failed.message.len}) catch unreachable;
            try default_headers.replace("Content-Length", len_str, allocator);
        } else {
            body_buffer = aw.toArrayList();
            var len_buf: [20]u8 = undefined;
            const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body_buffer.items.len}) catch unreachable;
            try default_headers.replace("Content-Length", len_str, allocator);
        }
    }
}

test "no memory leaks - with GPA explicit check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in server handling!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    // Run multiple request cycles
    for (0..10) |_| {
        var default_headers = try Response.getDefaultHeaders(allocator, 0);
        defer default_headers.deinit(allocator);

        const data = "POST /api HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n{\"key\":\"val\"}";
        var reader: std.Io.Reader = .fixed(data);

        var req = try Request.requestFromReader(&reader, allocator);
        defer req.deinit(allocator);

        var body_buffer: std.ArrayList(u8) = .empty;
        defer body_buffer.deinit(allocator);
        var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &body_buffer);
        var response_writer = Response.ResponseWriter{
            .writer = &aw.writer,
        };

        const result = try testHandler(allocator, &response_writer, &req);
        try std.testing.expect(result == .success);

        body_buffer = aw.toArrayList();
        var len_buf: [20]u8 = undefined;
        const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body_buffer.items.len}) catch unreachable;
        try default_headers.replace("Content-Length", len_str, allocator);
    }
}

test "no memory leaks - full server integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED in full server integration!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    // Start server in a separate thread
    var http_server = try Server.create(0, testHandler); // port 0 = random available port
    defer http_server.deinit();

    const server_port = http_server.listener.listen_address.getPort();

    const server_thread = try std.Thread.spawn(.{}, struct {
        fn run(server: *Server.HttpServer, alloc: std.mem.Allocator) void {
            server.run(alloc) catch {};
        }
    }.run, .{ &http_server, allocator });

    // Give server a moment to start
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Send 5 requests to trigger shutdown
    for (0..5) |_| {
        const stream = net.tcpConnectToHost(allocator, "127.0.0.1", server_port) catch continue;
        defer stream.close();

        const request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
        var write_buf: [1]u8 = undefined;
        var writer = stream.writer(&write_buf);
        writer.interface.writeAll(request) catch continue;
        writer.interface.flush() catch continue;

        // Small delay to let server process
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    // Wait for server to shut down
    server_thread.join();
}
