const std = @import("std");
const App = @import("../app.zig").App;
const RequestContext = @import("../app.zig").RequestContext;
const Request = @import("../../Request/request.zig");
const Response = @import("../../Response/response.zig");
const net = std.net;

fn testHandler(ctx: *RequestContext) !void {
    const request_line = ctx.req.request_line orelse return;

    if (std.mem.eql(u8, request_line.request_target, "/error")) {
        try ctx.sendResponse(.StatusBadRequest, "text/plain", "Error response");
        return;
    }

    try ctx.text("OK");
}

test "no memory leaks - App route registration" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator, 0);
    defer app.deinit();

    app.get("/", testHandler);
    app.get("/error", testHandler);
    app.post("/data", testHandler);
}

test "no memory leaks - request parsing" {
    const allocator = std.testing.allocator;

    var default_headers = try Response.getDefaultResponseHeaders(allocator, 0);
    defer default_headers.deinit(allocator);

    const data = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var req = try Request.requestFromReader(&reader, allocator);
    defer req.deinit(allocator);

    try std.testing.expect(req.request_line != null);
    try std.testing.expectEqualStrings("/", req.request_line.?.request_target);
    try std.testing.expectEqualStrings("GET", req.request_line.?.method);
}

test "no memory leaks - multiple request parsing" {
    const allocator = std.testing.allocator;

    const requests = [_][]const u8{
        "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "POST /data HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nhello",
        "GET /error HTTP/1.1\r\nHost: localhost\r\n\r\n",
        "PUT /update HTTP/1.1\r\nHost: localhost\r\nContent-Length: 11\r\n\r\nsome update",
    };

    for (requests) |data| {
        var default_headers = try Response.getDefaultResponseHeaders(allocator, 0);
        defer default_headers.deinit(allocator);

        var reader: std.Io.Reader = .fixed(data);
        var req = try Request.requestFromReader(&reader, allocator);
        defer req.deinit(allocator);

        try std.testing.expect(req.request_line != null);
    }
}

test "no memory leaks - with GPA explicit check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("LEAK DETECTED!\n", .{});
            @panic("Memory leak detected");
        }
    }
    const allocator = gpa.allocator();

    // Test App lifecycle
    var app = try App.init(allocator, 0);
    app.get("/", testHandler);
    app.get("/api", testHandler);
    app.post("/data", testHandler);
    app.deinit();

    // Test request parsing multiple times
    for (0..10) |_| {
        var default_headers = try Response.getDefaultResponseHeaders(allocator, 0);
        defer default_headers.deinit(allocator);

        const data = "POST /api HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n{\"key\":\"val\"}";
        var reader: std.Io.Reader = .fixed(data);

        var req = try Request.requestFromReader(&reader, allocator);
        defer req.deinit(allocator);
    }
}
