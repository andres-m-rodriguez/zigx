const std = @import("std");
const router = @import("router.zig");
const server = @import("server.zig");
const context = @import("context.zig");
pub const Request = server.Request;
pub const Response = server.Response;
pub const RequestContext = context.RequestContext;

pub const App = struct {
    allocator: std.mem.Allocator,
    port: u16,
    app_router: router.Router,

    pub fn init(allocator: std.mem.Allocator, port: u16) !App {
        return App{
            .allocator = allocator,
            .port = port,
            .app_router = router.Router.init(),
        };
    }

    pub fn deinit(self: *App, allocator: std.mem.Allocator) void {
        self.app_router.deinit(allocator);
    }

    pub fn get(self: *App, path: []const u8, handler: router.Handler) void {
        self.app_router.addRoute(self.allocator, .GET, path, handler) catch {};
    }

    pub fn post(self: *App, path: []const u8, handler: router.Handler) void {
        self.app_router.addRoute(self.allocator, .POST, path, handler) catch {};
    }

    pub fn put(self: *App, path: []const u8, handler: router.Handler) void {
        self.app_router.addRoute(self.allocator, .PUT, path, handler) catch {};
    }

    pub fn delete(self: *App, path: []const u8, handler: router.Handler) void {
        self.app_router.addRoute(self.allocator, .DELETE, path, handler) catch {};
    }

    pub fn patch(self: *App, path: []const u8, handler: router.Handler) void {
        self.app_router.addRoute(self.allocator, .PATCH, path, handler) catch {};
    }

    pub fn listen(self: *App) !void {
        var http_server = try server.create(self.port, internalHandler, self);
        defer http_server.deinit();
        try http_server.run(self.allocator);
    }

    fn internalHandler(ctx: *context.ServerContext) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ctx.app_instance orelse return error.NoAppInstance));

        const request_line = ctx.req.request_line orelse return error.MalformedRequest;

        const path = request_line.request_target;
        const method = request_line.method;

        const match_result = self.app_router.match(
            ctx.allocator,
            method,
            path,
        ) orelse {
            // No route found → 404
            var headers = try Response.getDefaultResponseHeaders(ctx.allocator, 0);
            try headers.replace("Content-Type", "text/html", ctx.allocator);

            const body = "<h1>404 Not Found</h1>";
            var len_buf: [20]u8 = undefined;
            const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch unreachable;
            try headers.replace("Content-Length", len_str, ctx.allocator);

            try ctx.writer.writeStatusLine(.StatusNotFound);
            try ctx.writer.writeHeaders(&headers);
            _ = try ctx.writer.writeBody(body);
            return;
        };

        // Build RequestContext from ServerContext
        var req_ctx = RequestContext.fromServerContext(ctx, match_result.params);

        // Call user's handler
        match_result.handler(&req_ctx) catch {
            if (!req_ctx.headers_sent) {
                var headers = try Response.getDefaultResponseHeaders(ctx.allocator, 0);

                const body = "<h1>500 Internal Server Error</h1>";
                var len_buf: [20]u8 = undefined;
                const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch unreachable;
                try headers.replace("Content-Length", len_str, ctx.allocator);

                try ctx.writer.writeStatusLine(.StatusInternalServerError);
                try ctx.writer.writeHeaders(&headers);
                _ = try ctx.writer.writeBody(body);
            }
            return;
        };
    }
};
