const std = @import("std");
const http = @import("../request.zig");
const root = @import("../../../root.zig");

const ChunkReader = root.ChunkReader;

// Fixed buffer tests
test "Good GET Request line" {
    const data = "GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);
    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("GET", rl.method);
    try std.testing.expectEqualStrings("/", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

test "Good GET Request line with path" {
    const data = "GET /coffee HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);
    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("GET", rl.method);
    try std.testing.expectEqualStrings("/coffee", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

// Chunked tests (like the Go version)
test "Good GET Request line - chunked 3 bytes" {
    const data = "GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";
    var buf: [1024]u8 = undefined;
    var chunk_reader = ChunkReader.init(data, 3, &buf);

    var request = try http.requestFromReader(chunk_reader.reader(), std.testing.allocator);
    defer request.deinit(std.testing.allocator);
    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("GET", rl.method);
    try std.testing.expectEqualStrings("/", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

test "Good GET Request line with path - chunked 1 byte" {
    const data = "GET /coffee HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";
    var buf: [1024]u8 = undefined;
    var chunk_reader = ChunkReader.init(data, 1, &buf);

    var request = try http.requestFromReader(chunk_reader.reader(), std.testing.allocator);
    defer request.deinit(std.testing.allocator);
    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("GET", rl.method);
    try std.testing.expectEqualStrings("/coffee", rl.request_target);
    try std.testing.expectEqualStrings("1.1", rl.http_version);
}

// Body tests
test "POST request with JSON body" {
    const body = "{\"name\":\"test\",\"value\":123}";
    const data = "POST /api/data HTTP/1.1\r\nHost: localhost:42069\r\nContent-Type: application/json\r\nContent-Length: 27\r\n\r\n" ++ body;
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("POST", rl.method);
    try std.testing.expectEqualStrings("/api/data", rl.request_target);
    try std.testing.expectEqualStrings(body, request.request_body.items);
}

test "POST request with form body" {
    const body = "username=john&password=secret";
    const data = "POST /login HTTP/1.1\r\nHost: localhost:42069\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 29\r\n\r\n" ++ body;
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("POST", rl.method);
    try std.testing.expectEqualStrings(body, request.request_body.items);
}

test "Request with no Content-Length has empty body" {
    const data = "GET /index.html HTTP/1.1\r\nHost: localhost:42069\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), request.request_body.items.len);
}

test "Request with Content-Length 0 has empty body" {
    const data = "POST /empty HTTP/1.1\r\nHost: localhost:42069\r\nContent-Length: 0\r\n\r\n";
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), request.request_body.items.len);
}

test "POST request with body - chunked 1 byte" {
    const body = "{\"key\":\"value\"}";
    const data = "POST /api HTTP/1.1\r\nHost: localhost\r\nContent-Length: 15\r\n\r\n" ++ body;
    var buf: [1024]u8 = undefined;
    var chunk_reader = ChunkReader.init(data, 1, &buf);

    var request = try http.requestFromReader(chunk_reader.reader(), std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("POST", rl.method);
    try std.testing.expectEqualStrings(body, request.request_body.items);
}

test "POST request with body - chunked 5 bytes" {
    const body = "Hello, World! This is a test body.";
    const data = "POST /message HTTP/1.1\r\nHost: localhost\r\nContent-Length: 34\r\n\r\n" ++ body;
    var buf: [1024]u8 = undefined;
    var chunk_reader = ChunkReader.init(data, 5, &buf);

    var request = try http.requestFromReader(chunk_reader.reader(), std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(body, request.request_body.items);
}

test "PUT request with body" {
    const body = "<xml><data>test</data></xml>";
    const data = "PUT /resource/1 HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/xml\r\nContent-Length: 28\r\n\r\n" ++ body;
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    const rl = request.request_line orelse return error.MissingRequestLine;
    try std.testing.expectEqualStrings("PUT", rl.method);
    try std.testing.expectEqualStrings("/resource/1", rl.request_target);
    try std.testing.expectEqualStrings(body, request.request_body.items);
}

test "Large body" {
    const body = "A" ** 1000;
    const data = "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000\r\n\r\n" ++ body;
    var reader: std.Io.Reader = .fixed(data);

    var request = try http.requestFromReader(&reader, std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1000), request.request_body.items.len);
    try std.testing.expectEqualStrings(body, request.request_body.items);
}

test "Large body - chunked" {
    const body = "B" ** 500;
    const data = "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 500\r\n\r\n" ++ body;
    var buf: [2048]u8 = undefined;
    var chunk_reader = ChunkReader.init(data, 7, &buf);

    var request = try http.requestFromReader(chunk_reader.reader(), std.testing.allocator);
    defer request.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 500), request.request_body.items.len);
    try std.testing.expectEqualStrings(body, request.request_body.items);
}
