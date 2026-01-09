const std = @import("std");
const Response = @import("../Response/response.zig");
const Request = @import("../Request/request.zig");
const router = @import("router.zig");
const header = @import("../Headers/headers.zig");

pub const ServerContext = struct {
    allocator: std.mem.Allocator,
    writer: *Response.ResponseWriter,
    req: *Request.Request,
    app_instance: ?*anyopaque = null,
};

// Context for .zigx pages - read-only, no response writing
pub const PageContext = struct {
    allocator: std.mem.Allocator,
    request: *const Request.Request,
    params: router.Params,

    pub fn getParam(self: *const PageContext, name: []const u8) ?[]const u8 {
        if (self.params.get(name)) |param| {
            return param.value;
        }
        return null;
    }

    pub fn body(self: *const PageContext) []const u8 {
        return self.request.request_body.items;
    }

    pub fn getHeader(self: *const PageContext, name: []const u8) ?[]const u8 {
        if (self.request.request_headers) |*headers| {
            return headers.get(name);
        }
        return null;
    }

    pub fn method(self: *const PageContext) ?@import("../Request/method.zig").Method {
        if (self.request.request_line) |line| {
            return line.method;
        }
        return null;
    }

    pub fn path(self: *const PageContext) ?[]const u8 {
        if (self.request.request_line) |line| {
            return line.request_target;
        }
        return null;
    }
};

pub const RequestContext = struct {
    allocator: std.mem.Allocator,
    request: *const Request.Request,
    params: router.Params,
    writer: *Response.ResponseWriter,

    pub fn body(self: *const RequestContext) []const u8 {
        return self.request.request_body.items;
    }

    pub fn getHeader(self: *const RequestContext, name: []const u8) ?[]const u8 {
        if (self.request.request_headers) |*headers| {
            return headers.get(name);
        }
        return null;
    }

    pub fn method(self: *const RequestContext) ?@import("../Request/method.zig").Method {
        if (self.request.request_line) |line| {
            return line.method;
        }
        return null;
    }

    pub fn path(self: *const RequestContext) ?[]const u8 {
        if (self.request.request_line) |line| {
            return line.request_target;
        }
        return null;
    }

    pub fn jsonBody(self: *const RequestContext, comptime T: type) !T {
        const body_bytes = self.body();
        return try std.json.parseFromSlice(T, self.allocator, body_bytes, .{});
    }

    pub fn startChunked(self: *RequestContext, status_code: Response.StatusCode, content_type: []const u8) !void {
        var headers = header.Headers{};
        defer headers.deinit(self.allocator);

        try headers.set("Transfer-Encoding", "chunked", self.allocator);
        try headers.set("Connection", "close", self.allocator);
        try headers.set("Content-Type", content_type, self.allocator);

        try self.writer.writeStatusLine(status_code);
        try self.writer.writeHeaders(&headers);
    }

    pub fn writeChunk(self: *RequestContext, data: []const u8) !void {
        try self.writer.writer.print("{x}\r\n", .{data.len});
        try self.writer.writer.writeAll(data);
        try self.writer.writer.writeAll("\r\n");
    }

    pub fn flush(self: *RequestContext) !void {
        try self.writer.flush();
    }
};
