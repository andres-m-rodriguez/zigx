const std = @import("std");
const RequestContext = @import("context.zig").RequestContext;

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,

    pub fn fromString(method: []const u8) ?Method {
        if (std.mem.eql(u8, method, "GET")) return .GET;
        if (std.mem.eql(u8, method, "POST")) return .POST;
        if (std.mem.eql(u8, method, "PUT")) return .PUT;
        if (std.mem.eql(u8, method, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, method, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, method, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, method, "OPTIONS")) return .OPTIONS;
        return null;
    }
};

pub const RouteKey = struct {
    method: Method,
    path: []const u8,

    pub fn hash(self: RouteKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(@tagName(self.method));
        hasher.update(":");
        hasher.update(self.path);
        return hasher.final();
    }

    pub fn eql(a: RouteKey, b: RouteKey) bool {
        return a.method == b.method and std.mem.eql(u8, a.path, b.path);
    }
};

const RouteContext = struct {
    pub fn hash(ctx: RouteContext, key: RouteKey) u64 {
        _ = ctx;
        return key.hash();
    }
    pub fn eql(ctx: RouteContext, a: RouteKey, b: RouteKey) bool {
        _ = ctx;
        return a.eql(b);
    }
};

pub const Handler = *const fn (ctx: *RequestContext) anyerror!void;

pub const Router = struct {
    routes: std.HashMap(RouteKey, Handler, RouteContext, std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Router {
        return Router{
            .routes = std.HashMap(RouteKey, Handler, RouteContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        var it = self.routes.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.path);
        }
        self.routes.deinit();
    }

    pub fn addRoute(self: *Router, method: Method, path: []const u8, handler: Handler) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        try self.routes.put(RouteKey{
            .method = method,
            .path = path_copy,
        }, handler);
    }

    pub fn match(self: *Router, method_str: []const u8, path: []const u8) ?Handler {
        const method = Method.fromString(method_str) orelse return null;
        return self.routes.get(RouteKey{
            .method = method,
            .path = path,
        });
    }
};
