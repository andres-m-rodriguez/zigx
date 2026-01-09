const std = @import("std");
const router = @import("router.zig");
const server = @import("server.zig");
const context = @import("context.zig");
const response_mod = @import("../Response/response.zig");

pub const Response = response_mod.Response;
pub const StatusCode = response_mod.StatusCode;
pub const RequestContext = context.RequestContext;
pub const Handler = router.Handler;
pub const Params = router.Params;
pub const Param = router.Param;
pub const Method = router.Method;

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

    pub fn get(self: *App, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(self.allocator, .GET, path, handler) catch {};
    }

    pub fn post(self: *App, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(self.allocator, .POST, path, handler) catch {};
    }

    pub fn put(self: *App, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(self.allocator, .PUT, path, handler) catch {};
    }

    pub fn delete(self: *App, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(self.allocator, .DELETE, path, handler) catch {};
    }

    pub fn patch(self: *App, path: []const u8, handler: Handler) void {
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
            const not_found = Response.notFound();
            try ctx.writer.writeResponse(ctx.allocator, not_found);
            return;
        };

        var req_ctx = RequestContext{
            .allocator = ctx.allocator,
            .request = ctx.req,
            .params = match_result.params,
            .writer = ctx.writer,
        };

        const user_response = match_result.handler(&req_ctx) catch {
            const error_response = Response.internalError();
            try ctx.writer.writeResponse(ctx.allocator, error_response);
            return;
        };
        defer user_response.deinit(ctx.allocator);

        try ctx.writer.writeResponse(ctx.allocator, user_response);
    }
};
