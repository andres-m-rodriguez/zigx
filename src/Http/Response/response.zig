const std = @import("std");
const header = @import("../Headers/headers.zig");

pub const StatusCode = enum(u16) {
    ok = 200,
    created = 201,
    no_content = 204,
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    internal_server_error = 500,
    service_unavailable = 503,

    pub fn phrase(self: StatusCode) []const u8 {
        return switch (self) {
            .ok => "OK",
            .created => "Created",
            .no_content => "No Content",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .internal_server_error => "Internal Server Error",
            .service_unavailable => "Service Unavailable",
        };
    }
};

pub const Response = struct {
    status_code: StatusCode,
    content_type: []const u8,
    body: []const u8,
    owned: bool = false,
    skip_write: bool = false,
    raw_write: bool = false,

    pub fn html(body: []const u8) Response {
        return .{
            .status_code = .ok,
            .content_type = "text/html",
            .body = body,
        };
    }

    pub fn text(body: []const u8) Response {
        return .{
            .status_code = .ok,
            .content_type = "text/plain",
            .body = body,
        };
    }

    pub fn json(body: []const u8) Response {
        return .{
            .status_code = .ok,
            .content_type = "application/json",
            .body = body,
        };
    }

    pub fn notFound() Response {
        return .{
            .status_code = .not_found,
            .content_type = "text/html",
            .body = "<h1>404 Not Found</h1>",
        };
    }

    pub fn status(code: StatusCode) Response {
        return .{
            .status_code = code,
            .content_type = "text/plain",
            .body = "",
        };
    }

    pub fn internalError() Response {
        return .{
            .status_code = .internal_server_error,
            .content_type = "text/html",
            .body = "<h1>500 Internal Server Error</h1>",
        };
    }

    pub fn empty() Response {
        return .{
            .status_code = .no_content,
            .content_type = "",
            .body = "",
            .skip_write = true,
        };
    }

    pub fn chunkEnding() Response {
        return .{
            .status_code = .ok,
            .content_type = "",
            .body = "0\r\n\r\n",
            .raw_write = true,
        };
    }

    pub fn fmtJson(allocator: std.mem.Allocator, value: anytype) !Response {
        const json_str = try std.json.Stringify.valueAlloc(allocator, value, .{});
        return .{
            .status_code = .ok,
            .content_type = "application/json",
            .body = json_str,
            .owned = true,
        };
    }

    pub fn fmt(allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !Response {
        const body = try std.fmt.allocPrint(allocator, format, args);
        return .{
            .status_code = .ok,
            .content_type = "text/plain",
            .body = body,
            .owned = true,
        };
    }

    pub fn fmtHtml(allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !Response {
        const body = try std.fmt.allocPrint(allocator, format, args);
        return .{
            .status_code = .ok,
            .content_type = "text/html",
            .body = body,
            .owned = true,
        };
    }

    pub fn withStatus(self: Response, code: StatusCode) Response {
        var resp = self;
        resp.status_code = code;
        return resp;
    }

    pub fn withContentType(self: Response, content_type: []const u8) Response {
        var resp = self;
        resp.content_type = content_type;
        return resp;
    }

    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.body);
        }
    }
};

pub const ResponseWriter = struct {
    writer: *std.Io.Writer,

    pub fn writeStatusLine(self: *ResponseWriter, status_code: StatusCode) !void {
        try self.writer.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status_code), status_code.phrase() });
    }

    pub fn writeChunk(self: *ResponseWriter, reader: *std.Io.Reader) !bool {
        var buf: [32]u8 = undefined;
        const amount_read = try reader.readSliceShort(&buf);
        try self.writer.print("{x}\r\n", .{amount_read});
        try self.writer.writeAll(buf[0..amount_read]);
        try self.writer.writeAll("\r\n");

        return buf.len == amount_read;
    }

    pub fn writeChunkEnd(self: *ResponseWriter) !void {
        _ = try self.writeBody("0\r\n\r\n");
    }

    pub fn writeHeaders(self: *ResponseWriter, headers: *header.Headers) !void {
        var headers_iterator = headers.iterator();
        while (headers_iterator.next()) |header_entry| {
            try self.writer.print("{s}: {s}\r\n", .{ header_entry.key_ptr.*, header_entry.value_ptr.* });
        }

        try self.writer.print("\r\n", .{});
    }

    pub fn writeBody(self: *ResponseWriter, bytes: []const u8) !usize {
        return try self.writer.write(bytes);
    }

    pub fn flush(self: *ResponseWriter) !void {
        try self.writer.flush();
    }

    pub fn writeResponse(self: *ResponseWriter, allocator: std.mem.Allocator, response: Response) !void {
        if (response.skip_write) return;

        if (response.raw_write) {
            _ = try self.writeBody(response.body);
            return;
        }

        var headers = header.Headers{};
        defer headers.deinit(allocator);

        const content_len_str = try std.fmt.allocPrint(allocator, "{d}", .{response.body.len});
        defer allocator.free(content_len_str);

        try headers.set("Content-Length", content_len_str, allocator);
        try headers.set("Connection", "close", allocator);
        try headers.set("Content-Type", response.content_type, allocator);

        try self.writeStatusLine(response.status_code);
        try self.writeHeaders(&headers);
        _ = try self.writeBody(response.body);
    }
};

pub fn getDefaultResponseHeaders(allocator: std.mem.Allocator, content_length: usize) !header.Headers {
    var h = header.Headers{};
    errdefer h.deinit(allocator);

    const content_len_str = try std.fmt.allocPrint(allocator, "{d}", .{content_length});
    defer allocator.free(content_len_str);

    try h.set("Content-Length", content_len_str, allocator);
    try h.set("Connection", "close", allocator);
    try h.set("Content-Type", "text/plain", allocator);

    return h;
}
