const std = @import("std");
const requestLine = @import("../requestLine.zig");
const Method = @import("../method.zig").Method;

// Valid request line tests
test "parse valid GET request line" {
    var data = "GET /index.html HTTP/1.1\r\n".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .complete);
    try std.testing.expectEqual(@as(usize, 26), result.complete.bytes_consumed);

    var rl = result.complete.request_line;
    defer rl.deinit(std.testing.allocator);

    try std.testing.expectEqual(Method.GET, rl.method);
    try std.testing.expectEqualStrings("/index.html", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

test "parse valid POST request line" {
    var data = "POST /api/users HTTP/1.1\r\n".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .complete);

    var rl = result.complete.request_line;
    defer rl.deinit(std.testing.allocator);

    try std.testing.expectEqual(Method.POST, rl.method);
    try std.testing.expectEqualStrings("/api/users", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

test "parse valid DELETE request line" {
    var data = "DELETE /api/resource/123 HTTP/1.1\r\n".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .complete);

    var rl = result.complete.request_line;
    defer rl.deinit(std.testing.allocator);

    try std.testing.expectEqual(Method.DELETE, rl.method);
    try std.testing.expectEqualStrings("/api/resource/123", rl.request_target);
}

test "parse request line with query string" {
    var data = "GET /search?q=hello&page=1 HTTP/1.1\r\n".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .complete);

    var rl = result.complete.request_line;
    defer rl.deinit(std.testing.allocator);

    try std.testing.expectEqual(Method.GET, rl.method);
    try std.testing.expectEqualStrings("/search?q=hello&page=1", rl.request_target);
}

test "parse request line with root path" {
    var data = "GET / HTTP/1.1\r\n".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .complete);

    var rl = result.complete.request_line;
    defer rl.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/", rl.request_target);
}

// Incomplete request line tests
test "incomplete request line without CRLF" {
    var data = "GET /index.html HTTP/1.1".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .incomplete);
    try std.testing.expectEqual(@as(usize, 24), result.incomplete.bytes_read);
}

test "incomplete request line partial CRLF" {
    var data = "GET /index.html HTTP/1.1\r".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .incomplete);
}

test "incomplete request line empty input" {
    var data = "".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .incomplete);
    try std.testing.expectEqual(@as(usize, 0), result.incomplete.bytes_read);
}

// Malformed request line tests
test "malformed request line too few parts" {
    var data = "GET /index.html\r\n".*;
    const result = requestLine.parse(std.testing.allocator, &data);

    try std.testing.expectError(error.MalformedRequestLine, result);
}

test "malformed request line only method" {
    var data = "GET\r\n".*;
    const result = requestLine.parse(std.testing.allocator, &data);

    try std.testing.expectError(error.MalformedRequestLine, result);
}

test "malformed request line too many parts" {
    var data = "GET /index.html HTTP/1.1 extra\r\n".*;
    const result = requestLine.parse(std.testing.allocator, &data);

    try std.testing.expectError(error.MalformedRequestLine, result);
}

test "malformed request line empty" {
    var data = "\r\n".*;
    const result = requestLine.parse(std.testing.allocator, &data);

    try std.testing.expectError(error.MalformedRequestLine, result);
}

test "invalid HTTP version 1.0" {
    var data = "GET /index.html HTTP/1.0\r\n".*;
    const result = requestLine.parse(std.testing.allocator, &data);

    try std.testing.expectError(error.InvalidVersion, result);
}

test "invalid HTTP version 2.0" {
    var data = "GET /index.html HTTP/2.0\r\n".*;
    const result = requestLine.parse(std.testing.allocator, &data);

    try std.testing.expectError(error.InvalidVersion, result);
}

// Bytes consumed tests
test "bytes consumed includes CRLF" {
    var data = "GET / HTTP/1.1\r\nHost: localhost\r\n".*;
    const result = try requestLine.parse(std.testing.allocator, &data);

    try std.testing.expect(result == .complete);
    // "GET / HTTP/1.1\r\n" = 16 bytes
    try std.testing.expectEqual(@as(usize, 16), result.complete.bytes_consumed);

    var rl = result.complete.request_line;
    defer rl.deinit(std.testing.allocator);
}

// parseRequestLine direct tests
test "parseRequestLine valid line" {
    var line = "PUT /resource HTTP/1.1".*;
    var rl = try requestLine.parseRequestLine(std.testing.allocator, &line);
    defer rl.deinit(std.testing.allocator);

    try std.testing.expectEqual(Method.PUT, rl.method);
    try std.testing.expectEqualStrings("/resource", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

test "parseRequestLine malformed no version slash" {
    var line = "GET /index.html HTTP1.1".*;
    const result = requestLine.parseRequestLine(std.testing.allocator, &line);

    try std.testing.expectError(error.MalformedRequestLine, result);
}
