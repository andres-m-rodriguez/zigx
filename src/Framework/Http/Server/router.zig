const std = @import("std");
const Response = @import("../Response/response.zig").Response;
pub const Method = @import("../Request/method.zig").Method;

const RouteContext = struct {
    pub fn hash(ctx: RouteContext, key: Method) u64 {
        _ = ctx;
        return @intFromEnum(key);
    }
    pub fn eql(ctx: RouteContext, a: Method, b: Method) bool {
        _ = ctx;
        return a == b;
    }
};

pub const RequestContext = @import("context.zig").RequestContext;

pub const Handler = *const fn (ctx: *RequestContext) anyerror!Response;

pub const Node = struct {
    param_information: ?ParamInformation,
    path: []const u8,
    nodes: std.StringHashMapUnmanaged(Node),
    next_param_node: ?*Node,
    handlers: std.HashMapUnmanaged(
        Method,
        Handler,
        RouteContext,
        std.hash_map.default_max_load_percentage,
    ),
    pub fn addNextParamNode(self: *Node, allocator: std.mem.Allocator, paramNode: Node) !void {
        if (self.next_param_node) |_| {
            return error.NodeAlreadyExists;
        }
        const ptr = try allocator.create(Node);
        ptr.* = paramNode;
        self.next_param_node = ptr;
    }
    pub fn addHandler(self: *Node, allocator: std.mem.Allocator, method: Method, handler: Handler) !void {
        try self.handlers.put(allocator, method, handler);
    }
    pub fn addNode(self: *Node, allocator: std.mem.Allocator, newValuePath: []const u8, newValue: Node) !void {
        const new_value_path_copy = try allocator.dupe(u8, newValuePath);
        errdefer allocator.free(new_value_path_copy);

        try self.nodes.put(allocator, new_value_path_copy, newValue);
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        defer self.handlers.deinit(allocator);
        defer self.nodes.deinit(allocator);
        var nodes_iterator = self.nodes.iterator();
        if (self.next_param_node) |next_param_node| {
            next_param_node.deinit(allocator);
            allocator.destroy(next_param_node);
        }
        while (nodes_iterator.next()) |node| {
            allocator.free(node.key_ptr.*);
            node.value_ptr.deinit(allocator);
        }
    }
};
fn createNode(
    allocator: std.mem.Allocator,
    path: []const u8,
    param: ?ParamInformation,
) !*Node {
    const node = try allocator.create(Node);
    node.* = .{
        .param_information = param,
        .path = path,
        .nodes = .empty,
        .next_param_node = null,
        .handlers = .empty,
    };
    return node;
}

pub const Param = struct {
    name: []const u8,
    value: []const u8,

    pub fn asInt(self: Param) !i64 {
        return std.fmt.parseInt(i64, self.value, 10);
    }

    pub fn asUsize(self: Param) !usize {
        return std.fmt.parseInt(usize, self.value, 10);
    }
};
pub const Params = struct {
    items: []const Param,

    pub fn get(self: Params, name: []const u8) ?Param {
        for (self.items) |p| {
            if (std.mem.eql(u8, p.name, name)) return p;
        }
        return null;
    }
};

pub const ParamTypes = enum {
    str,
    int,
    guid,

    pub fn fromString(type_str: []const u8) ParamTypes {
        if (std.mem.eql(u8, type_str, "int")) return .int;
        if (std.mem.eql(u8, type_str, "guid")) return .guid;
        return .str;
    }
};

pub const ParamInformation = struct {
    param_type: ParamTypes,
    name: []const u8,

    pub fn isParam(segment: []const u8) bool {
        return std.mem.indexOfScalar(u8, segment, ':') != null;
    }

    pub fn parse(segment: []const u8) ?ParamInformation {
        const colon_index = std.mem.indexOfScalar(u8, segment, ':') orelse return null;

        const name = segment[0..colon_index];
        const type_str = segment[colon_index + 1 ..];

        if (name.len == 0 or type_str.len == 0) return null;

        return ParamInformation{
            .param_type = ParamTypes.fromString(type_str),
            .name = name,
        };
    }
};

pub const MatchResult = struct {
    handler: Handler,
    params: Params,
};

pub const Router = struct {
    routes: std.StringHashMapUnmanaged(Node),

    pub fn init() Router {
        return Router{
            .routes = std.StringHashMapUnmanaged(Node){},
        };
    }

    fn getOrCreateRoot(self: *Router, allocator: std.mem.Allocator, root_segment: []const u8) !*Node {
        if (self.routes.getPtr(root_segment)) |existing_node| {
            return existing_node;
        }

        const root_segment_copy = try allocator.dupe(u8, root_segment);
        errdefer allocator.free(root_segment_copy);

        const new_node = try createNode(
            allocator,
            root_segment_copy,
            ParamInformation.parse(root_segment),
        );
        defer allocator.destroy(new_node);

        try self.routes.put(allocator, root_segment_copy, new_node.*);
        return self.routes.getPtr(root_segment_copy).?;
    }

    pub fn deinit(self: *Router, allocator: std.mem.Allocator) void {
        var routes_iterator = self.routes.iterator();
        while (routes_iterator.next()) |entry| {
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.routes.deinit(allocator);
    }

    pub fn addRoute(
        self: *Router,
        allocator: std.mem.Allocator,
        method: Method,
        path: []const u8,
        handler: Handler,
    ) !void {
        var segments_iterator = std.mem.splitScalar(u8, path, '/');
        const root_segment = segments_iterator.next() orelse return error.NoValidUrl;
        var current_node = try self.getOrCreateRoot(allocator, root_segment);

        while (segments_iterator.next()) |segment| {
            const is_last_segment = segments_iterator.peek() == null;
            const param_info = ParamInformation.parse(segment);

            if (param_info) |param| {
                if (current_node.next_param_node) |next_node| {
                    current_node = next_node;
                } else {
                    const new_node = try createNode(allocator, segment, param);
                    current_node.next_param_node = new_node;
                    current_node = new_node;
                }
            } else {
                if (current_node.nodes.getPtr(segment)) |next_node| {
                    current_node = next_node;
                } else {
                    const segment_copy = try allocator.dupe(u8, segment);
                    errdefer allocator.free(segment_copy);

                    const new_node = try createNode(allocator, segment_copy, null);
                    defer allocator.destroy(new_node);
                    try current_node.nodes.put(allocator, segment_copy, new_node.*);
                    current_node = current_node.nodes.getPtr(segment_copy).?;
                }
            }

            if (is_last_segment) {
                try current_node.addHandler(allocator, method, handler);
            }
        }
    }

    pub fn match(self: *Router, allocator: std.mem.Allocator, method: Method, path: []const u8) ?MatchResult {
        var segments_iterator = std.mem.splitScalar(u8, path, '/');
        const root_segment = segments_iterator.next() orelse return null;
        var current_node = self.routes.get(root_segment) orelse return null;

        var params_list = std.ArrayListUnmanaged(Param){};
        while (segments_iterator.next()) |segment| {
            if (current_node.nodes.get(segment)) |next_node| {
                current_node = next_node;
            } else if (current_node.next_param_node) |param_node| {
                if (param_node.param_information) |param_info| {
                    params_list.append(allocator, .{
                        .name = param_info.name,
                        .value = segment,
                    }) catch return null;
                }
                current_node = param_node.*;
            } else {
                params_list.deinit(allocator);
                return null;
            }
        }

        const matched_handler = current_node.handlers.get(method) orelse {
            params_list.deinit(allocator);
            return null;
        };

        return MatchResult{
            .handler = matched_handler,
            .params = .{ .items = params_list.toOwnedSlice(allocator) catch return null },
        };
    }
};

fn testHandlerA(_: *RequestContext) anyerror!Response {
    return Response.text("handler A");
}
fn testHandlerB(_: *RequestContext) anyerror!Response {
    return Response.text("handler B");
}

test "router1" {
    var rtr = Router.init();
    defer rtr.deinit(std.testing.allocator);

    try rtr.addRoute(std.testing.allocator, .GET, "/users", testHandlerA);

    const result = rtr.match(std.testing.allocator, .GET, "/users");
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.handler == testHandlerA);
}

test "router2" {
    var rtr = Router.init();
    defer rtr.deinit(std.testing.allocator);

    try rtr.addRoute(std.testing.allocator, .GET, "/users", testHandlerA);
    try rtr.addRoute(std.testing.allocator, .POST, "/users", testHandlerB);

    const get_result = rtr.match(std.testing.allocator, .GET, "/users");
    const post_result = rtr.match(std.testing.allocator, .POST, "/users");

    try std.testing.expect(get_result.?.handler == testHandlerA);
    try std.testing.expect(post_result.?.handler == testHandlerB);
}

test "router3" {
    var rtr = Router.init();
    defer rtr.deinit(std.testing.allocator);

    try rtr.addRoute(std.testing.allocator, .GET, "/users", testHandlerA);

    try std.testing.expect(rtr.match(std.testing.allocator, .GET, "/posts") == null);
    try std.testing.expect(rtr.match(std.testing.allocator, .DELETE, "/users") == null);
}

test "router4 - param extraction" {
    var rtr = Router.init();
    defer rtr.deinit(std.testing.allocator);

    try rtr.addRoute(std.testing.allocator, .GET, "/users/id:int", testHandlerA);

    const result = rtr.match(std.testing.allocator, .GET, "/users/42");
    defer std.testing.allocator.free(result.?.params.items);

    try std.testing.expect(result != null);
    try std.testing.expect(result.?.handler == testHandlerA);

    const id_param = result.?.params.get("id");
    try std.testing.expect(id_param != null);
    try std.testing.expectEqualStrings("42", id_param.?.value);

    const id_int = try id_param.?.asInt();
    try std.testing.expect(id_int == 42);
}
