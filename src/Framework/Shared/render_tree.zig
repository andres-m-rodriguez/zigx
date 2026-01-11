const std = @import("std");

pub fn fmtSpec(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8) "{s}" else "{any}",
        .int, .comptime_int => "{d}",
        .float, .comptime_float => "{d}",
        .bool => "{}",
        else => "{any}",
    };
}

pub const FrameType = enum(u8) {
    element,
    text,
    attribute,
    event,
    region,
};

pub const ElementData = struct {
    tag: []const u8,
    dom_handle: u32 = 0,
};

pub const TextData = struct {
    content: []const u8,
};

pub const AttributeData = struct {
    name: []const u8,
    value: []const u8,
};

pub const EventData = struct {
    name: []const u8,
    handler_id: u32,
};

pub const FrameData = union(FrameType) {
    element: ElementData,
    text: TextData,
    attribute: AttributeData,
    event: EventData,
    region: void,
};

pub const RenderFrame = struct {
    frame_type: FrameType,
    sequence: u32,
    data: FrameData,
    subtree_length: u32 = 0,
};

pub const RenderTree = struct {
    frames: []const RenderFrame,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RenderTree) void {
        self.allocator.free(self.frames);
    }
};

pub const RenderTreeBuilder = struct {
    frames: std.ArrayList(RenderFrame),
    element_stack: std.ArrayList(usize),
    tag_stack: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RenderTreeBuilder {
        return .{
            .frames = .{},
            .element_stack = .{},
            .tag_stack = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RenderTreeBuilder) void {
        self.frames.deinit(self.allocator);
        self.element_stack.deinit(self.allocator);
        self.tag_stack.deinit(self.allocator);
    }

    pub fn openElement(self: *RenderTreeBuilder, seq: u32, tag: []const u8) !usize {
        const idx = self.frames.items.len;
        try self.frames.append(self.allocator, .{
            .frame_type = .element,
            .sequence = seq,
            .data = .{ .element = .{ .tag = tag } },
            .subtree_length = 0,
        });
        try self.element_stack.append(self.allocator, idx);
        try self.tag_stack.append(self.allocator, tag);
        return idx;
    }

    pub fn closeElement(self: *RenderTreeBuilder) !void {
        if (self.element_stack.items.len == 0) return error.NoOpenElement;

        const open_idx = self.element_stack.pop();
        const tag = self.tag_stack.pop();

        const subtree_len = self.frames.items.len - open_idx;

        self.frames.items[open_idx].subtree_length = @intCast(subtree_len);

        try self.frames.append(self.allocator, .{
            .frame_type = .region,
            .sequence = self.frames.items[open_idx].sequence,
            .data = .{ .region = {} },
            .subtree_length = 0,
        });

        _ = tag;
    }

    pub fn addText(self: *RenderTreeBuilder, seq: u32, content: []const u8) !void {
        try self.frames.append(self.allocator, .{
            .frame_type = .text,
            .sequence = seq,
            .data = .{ .text = .{ .content = content } },
            .subtree_length = 0,
        });
    }

    pub fn addAttribute(self: *RenderTreeBuilder, seq: u32, name: []const u8, value: []const u8) !void {
        try self.frames.append(self.allocator, .{
            .frame_type = .attribute,
            .sequence = seq,
            .data = .{ .attribute = .{ .name = name, .value = value } },
            .subtree_length = 0,
        });
    }

    pub fn addEvent(self: *RenderTreeBuilder, seq: u32, name: []const u8, handler_id: u32) !void {
        try self.frames.append(self.allocator, .{
            .frame_type = .event,
            .sequence = seq,
            .data = .{ .event = .{ .name = name, .handler_id = handler_id } },
            .subtree_length = 0,
        });
    }

    pub fn build(self: *RenderTreeBuilder) !RenderTree {
        if (self.element_stack.items.len > 0) {
            return error.UnclosedElements;
        }

        return .{
            .frames = try self.frames.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }
};

pub fn toHtmlString(allocator: std.mem.Allocator, tree: RenderTree) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var tag_stack = std.ArrayList([]const u8){};
    defer tag_stack.deinit(allocator);

    var in_opening_tag = false;

    for (tree.frames) |frame| {
        switch (frame.frame_type) {
            .element => {
                if (in_opening_tag) {
                    try result.append(allocator, '>');
                }

                try result.append(allocator, '<');
                try result.appendSlice(allocator, frame.data.element.tag);
                try tag_stack.append(allocator, frame.data.element.tag);
                in_opening_tag = true;
            },
            .attribute => {
                try result.append(allocator, ' ');
                try result.appendSlice(allocator, frame.data.attribute.name);
                try result.appendSlice(allocator, "=\"");
                try appendHtmlEscaped(allocator, &result, frame.data.attribute.value);
                try result.append(allocator, '"');
            },
            .event => {
                try result.appendSlice(allocator, " data-zigx-");
                try result.appendSlice(allocator, frame.data.event.name);
                try result.appendSlice(allocator, "=\"");
                try std.fmt.format(result.writer(allocator), "{d}", .{frame.data.event.handler_id});
                try result.append(allocator, '"');
            },
            .text => {
                if (in_opening_tag) {
                    try result.append(allocator, '>');
                    in_opening_tag = false;
                }
                try result.appendSlice(allocator, frame.data.text.content);
            },
            .region => {
                if (in_opening_tag) {
                    try result.append(allocator, '>');
                    in_opening_tag = false;
                }

                if (tag_stack.items.len > 0) {
                    const tag = tag_stack.pop().?;
                    try result.appendSlice(allocator, "</");
                    try result.appendSlice(allocator, tag);
                    try result.append(allocator, '>');
                }
            },
        }
    }

    return result.toOwnedSlice(allocator);
}

fn appendHtmlEscaped(allocator: std.mem.Allocator, result: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '<' => try result.appendSlice(allocator, "&lt;"),
            '>' => try result.appendSlice(allocator, "&gt;"),
            '&' => try result.appendSlice(allocator, "&amp;"),
            '"' => try result.appendSlice(allocator, "&quot;"),
            '\'' => try result.appendSlice(allocator, "&#39;"),
            else => try result.append(allocator, c),
        }
    }
}

test "RenderTreeBuilder basic element" {
    const allocator = std.testing.allocator;

    var builder = RenderTreeBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.openElement(0, "div");
    try builder.addAttribute(1, "class", "container");
    try builder.addText(2, "Hello");
    try builder.closeElement();

    var tree = try builder.build();
    defer tree.deinit();

    try std.testing.expectEqual(@as(usize, 4), tree.frames.len);
    try std.testing.expectEqual(FrameType.element, tree.frames[0].frame_type);
    try std.testing.expectEqual(FrameType.attribute, tree.frames[1].frame_type);
    try std.testing.expectEqual(FrameType.text, tree.frames[2].frame_type);
    try std.testing.expectEqual(FrameType.region, tree.frames[3].frame_type);
}

test "RenderTreeBuilder nested elements" {
    const allocator = std.testing.allocator;

    var builder = RenderTreeBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder.openElement(0, "div");
    _ = try builder.openElement(1, "span");
    try builder.addText(2, "nested");
    try builder.closeElement();
    try builder.closeElement();

    var tree = try builder.build();
    defer tree.deinit();

    try std.testing.expectEqual(@as(usize, 5), tree.frames.len);
}

test "toHtmlString basic" {
    const allocator = std.testing.allocator;

    var builder = RenderTreeBuilder.init(allocator);

    _ = try builder.openElement(0, "div");
    try builder.addAttribute(1, "class", "test");
    try builder.addText(2, "Hello");
    try builder.closeElement();

    var tree = try builder.build();
    defer tree.deinit();

    const html = try toHtmlString(allocator, tree);
    defer allocator.free(html);

    try std.testing.expectEqualStrings("<div class=\"test\">Hello</div>", html);

    builder.deinit();
}

test "toHtmlString with event" {
    const allocator = std.testing.allocator;

    var builder = RenderTreeBuilder.init(allocator);

    _ = try builder.openElement(0, "button");
    try builder.addEvent(1, "click", 0);
    try builder.addText(2, "Click me");
    try builder.closeElement();

    var tree = try builder.build();
    defer tree.deinit();

    const html = try toHtmlString(allocator, tree);
    defer allocator.free(html);

    try std.testing.expectEqualStrings("<button data-zigx-click=\"0\">Click me</button>", html);

    builder.deinit();
}
