const std = @import("std");
const Response = @import("../Response/response.zig");
const Request = @import("../Request/request.zig");

/// Internal context passed from server to app layer
pub const ServerContext = struct {
    allocator: std.mem.Allocator,
    writer: *Response.ResponseWriter,
    req: *Request.Request,
    app_instance: ?*anyopaque = null,
};

/// User-friendly context passed to route handlers
pub const RequestContext = struct {
    allocator: std.mem.Allocator,
    writer: *Response.ResponseWriter,
    req: *Request.Request,
    headers_sent: bool = false,

    pub fn fromServerContext(ctx: *ServerContext) RequestContext {
        return RequestContext{
            .allocator = ctx.allocator,
            .writer = ctx.writer,
            .req = ctx.req,
        };
    }

    pub fn html(self: *RequestContext, body: []const u8) !void {
        try self.sendResponse(.StatusOk, "text/html", body);
    }

    pub fn text(self: *RequestContext, body: []const u8) !void {
        try self.sendResponse(.StatusOk, "text/plain", body);
    }

    pub fn json(self: *RequestContext, body: []const u8) !void {
        try self.sendResponse(.StatusOk, "application/json", body);
    }

    pub fn status(self: *RequestContext, status_code: Response.StatusCode) !void {
        try self.sendResponse(status_code, "text/plain", "");
    }

    pub fn notFound(self: *RequestContext) !void {
        try self.sendResponse(.StatusNotFound, "text/html", "<h1>404 Not Found</h1>");
    }

    pub fn sendResponse(self: *RequestContext, status_code: Response.StatusCode, content_type: []const u8, body: []const u8) !void {
        if (self.headers_sent) return;
        self.headers_sent = true;

        var headers = Response.getDefaultResponseHeaders(self.allocator, body.len) catch return;
        defer headers.deinit(self.allocator);

        try headers.replace("Content-Type", content_type, self.allocator);

        try self.writer.writeStatusLine(status_code);
        try self.writer.writeHeaders(&headers);
        _ = try self.writer.writeBody(body);
    }
};
