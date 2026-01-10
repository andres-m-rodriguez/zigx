const std = @import("std");
const App = @import("../app.zig").App;
const RequestContext = @import("../app.zig").RequestContext;
const Response = @import("../app.zig").Response;
const RequestMod = @import("../../Request/request.zig");
const ResponseMod = @import("../../Response/response.zig");
const Method = @import("../../Request/method.zig").Method;
const net = std.net;

fn testHandler(ctx: *RequestContext) !Response {
    if (ctx.path()) |target| {
        if (std.mem.eql(u8, target, "/error")) {
            return Response.text("Error response").withStatus(.bad_request);
        }
    }
    return Response.text("OK");
}

test "no memory leaks - App route registration" {
    const allocator = std.testing.allocator;

    var app = App.init(0);
    defer app.deinit(allocator);

    app.get(allocator, "/", testHandler);
    app.get(allocator, "/error", testHandler);
    app.post(allocator, "/data", testHandler);
}

test "no memory leaks - request parsing" {
    const allocator = std.testing.allocator;

    var default_headers = try ResponseMod.getDefaultResponseHeaders(allocator, 0);
    defer default_headers.deinit(allocator);

    const data = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var req = try RequestMod.requestFromReader(&reader, allocator);
    defer req.deinit(allocator);

    try std.testing.expect(req.request_line != null);
    try std.testing.expectEqualStrings("/", req.request_line.?.request_target);
    try std.testing.expectEqual(Method.GET, req.request_line.?.method);
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
        var default_headers = try ResponseMod.getDefaultResponseHeaders(allocator, 0);
        defer default_headers.deinit(allocator);

        var reader: std.Io.Reader = .fixed(data);
        var req = try RequestMod.requestFromReader(&reader, allocator);
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

    var app = App.init(0);
    app.get(allocator, "/", testHandler);
    app.get(allocator, "/api", testHandler);
    app.post(allocator, "/data", testHandler);
    app.deinit(allocator);

    for (0..10) |_| {
        var default_headers = try ResponseMod.getDefaultResponseHeaders(allocator, 0);
        defer default_headers.deinit(allocator);

        const data = "POST /api HTTP/1.1\r\nHost: localhost\r\nContent-Length: 13\r\n\r\n{\"key\":\"val\"}";
        var reader: std.Io.Reader = .fixed(data);

        var req = try RequestMod.requestFromReader(&reader, allocator);
        defer req.deinit(allocator);
    }
}

test "Response builders" {
    const html_resp = Response.html("<h1>Hello</h1>");
    try std.testing.expectEqualStrings("<h1>Hello</h1>", html_resp.body);
    try std.testing.expectEqualStrings("text/html", html_resp.content_type);
    try std.testing.expectEqual(ResponseMod.StatusCode.ok, html_resp.status_code);

    const json_resp = Response.json("{\"key\": \"value\"}");
    try std.testing.expectEqualStrings("application/json", json_resp.content_type);

    const text_resp = Response.text("Hello");
    try std.testing.expectEqualStrings("text/plain", text_resp.content_type);

    const error_resp = Response.text("Bad request").withStatus(.bad_request);
    try std.testing.expectEqual(ResponseMod.StatusCode.bad_request, error_resp.status_code);

    const not_found = Response.notFound();
    try std.testing.expectEqual(ResponseMod.StatusCode.not_found, not_found.status_code);
}

test "Response.fmtJson" {
    const allocator = std.testing.allocator;

    const resp = try Response.fmtJson(allocator, .{
        .name = "Test",
        .value = 42,
    });
    defer resp.deinit(allocator);

    try std.testing.expect(resp.owned);
    try std.testing.expectEqualStrings("application/json", resp.content_type);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "Test") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "42") != null);
}
