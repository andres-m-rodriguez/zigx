const std = @import("std");
const router = @import("router.zig");
const server = @import("server.zig");
const context = @import("context.zig");
const response_mod = @import("../Response/response.zig");
const routes = @import("../../../gen/routes.zig");

pub const Response = response_mod.Response;
pub const StatusCode = response_mod.StatusCode;
pub const RequestContext = context.RequestContext;
pub const Handler = router.Handler;
pub const Params = router.Params;
pub const Param = router.Param;
pub const Method = router.Method;

// Embedded static files for Zigx client runtime
const zigx_runtime_js = @embedFile("../../Client/zigx-runtime.js");

pub const App = struct {
    port: u16,
    app_router: router.Router,

    pub fn init(port: u16) App {
        return App{
            .port = port,
            .app_router = router.Router.init(),
        };
    }

    pub fn deinit(self: *App, allocator: std.mem.Allocator) void {
        self.app_router.deinit(allocator);
    }

    pub fn get(self: *App, allocator: std.mem.Allocator, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(allocator, .GET, path, handler) catch {};
    }

    pub fn post(self: *App, allocator: std.mem.Allocator, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(allocator, .POST, path, handler) catch {};
    }

    pub fn put(self: *App, allocator: std.mem.Allocator, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(allocator, .PUT, path, handler) catch {};
    }

    pub fn delete(self: *App, allocator: std.mem.Allocator, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(allocator, .DELETE, path, handler) catch {};
    }

    pub fn patch(self: *App, allocator: std.mem.Allocator, path: []const u8, handler: Handler) void {
        self.app_router.addRoute(allocator, .PATCH, path, handler) catch {};
    }

    pub fn addZigxPages(self: *App, allocator: std.mem.Allocator) void {
        routes.registerRoutes(allocator, self);
        // Add Zigx static file routes
        self.addZigxStaticRoutes(allocator);
    }

    fn addZigxStaticRoutes(self: *App, allocator: std.mem.Allocator) void {
        // Serve the JavaScript runtime
        self.app_router.addRoute(allocator, .GET, "/_zigx/runtime.js", zigxRuntimeHandler) catch {};
        // Serve WASM files (MVP: specific route, later: dynamic param)
        self.app_router.addRoute(allocator, .GET, "/_zigx/MyCounter.wasm", zigxWasmHandler) catch {};
    }

    fn zigxRuntimeHandler(_: *RequestContext) anyerror!Response {
        return Response{
            .status_code = .ok,
            .content_type = "application/javascript",
            .body = zigx_runtime_js,
        };
    }

    fn zigxWasmHandler(_: *RequestContext) anyerror!Response {
        // WASM is embedded at compile time (build.zig ensures it's built first)
        const wasm_data = @embedFile("../../../gen/wasm/MyCounter.wasm");
        return Response{
            .status_code = .ok,
            .content_type = "application/wasm",
            .body = wasm_data,
        };
    }

    pub fn listen(self: *App, allocator: std.mem.Allocator) !void {
        var http_server = try server.create(self.port, internalHandler, self);
        defer http_server.deinit();
        try http_server.run(allocator);
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
