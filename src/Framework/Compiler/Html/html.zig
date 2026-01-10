const std = @import("std");
const Allocator = std.mem.Allocator;

///This will look very similar to razor in the C# world because those are the far away lands where I come from

//Needed to not fuck up the print and know what type to print correctly
pub fn fmtSpec(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8) "{s}" else "{any}",
        .int, .comptime_int => "{d}",
        .float, .comptime_float => "{d}",
        .bool => "{}",
        else => "{any}",
    };
}

pub const Attribute = struct {
    name: []const u8,
    val: []const u8,
};

pub const Content = union(enum) {
    text: []const u8,
    raw_html: []const u8,
    elem: *Element,
    dynamic: DynamicContent,
};

pub const DynamicContent = struct {
    format_spec: []const u8,
    value_ptr: *const anyopaque,
    write_fn: *const fn (*const anyopaque, *std.Io.Writer) anyerror!void,
};

pub const Element = struct {
    tag_name: []const u8,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(Content),
    self_closing: bool,
    allocator: Allocator,

    const Self = @This();

    pub fn create(alloc: Allocator, name: []const u8) Self {
        return .{
            .tag_name = name,
            .attributes = std.ArrayList(Attribute).init(alloc),
            .children = std.ArrayList(Content).init(alloc),
            .self_closing = false,
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |item| {
            switch (item) {
                .elem => |el| {
                    el.deinit();
                    self.allocator.destroy(el);
                },
                else => {},
            }
        }
        self.children.deinit();
        self.attributes.deinit();
    }

    pub fn selfClosing(self: *Self) *Self {
        self.self_closing = true;
        return self;
    }

    pub fn attr(self: *Self, name: []const u8, val_str: []const u8) *Self {
        self.attributes.append(.{ .name = name, .val = val_str }) catch {};
        return self;
    }

    pub fn class(self: *Self, val_str: []const u8) *Self {
        return self.attr("class", val_str);
    }

    pub fn id(self: *Self, val_str: []const u8) *Self {
        return self.attr("id", val_str);
    }

    pub fn href(self: *Self, val_str: []const u8) *Self {
        return self.attr("href", val_str);
    }

    pub fn src(self: *Self, val_str: []const u8) *Self {
        return self.attr("src", val_str);
    }

    pub fn style(self: *Self, val_str: []const u8) *Self {
        return self.attr("style", val_str);
    }

    pub fn text(self: *Self, content: []const u8) *Self {
        self.children.append(.{ .text = content }) catch {};
        return self;
    }

    pub fn raw(self: *Self, content: []const u8) *Self {
        self.children.append(.{ .raw_html = content }) catch {};
        return self;
    }

    pub fn child(self: *Self, el: *Element) *Self {
        self.children.append(.{ .elem = el }) catch {};
        return self;
    }

    pub fn val(self: *Self, v: anytype) *Self {
        const T = @TypeOf(v);
        const ptr = self.allocator.create(T) catch return self;
        ptr.* = v;

        const write_fn = struct {
            fn write(vp: *const anyopaque, w: *std.Io.Writer) anyerror!void {
                const typed_ptr: *const T = @ptrCast(@alignCast(vp));
                try std.fmt.format(w, fmtSpec(T), .{typed_ptr.*});
            }
        }.write;

        self.children.append(.{
            .dynamic = .{
                .format_spec = fmtSpec(T),
                .value_ptr = ptr,
                .write_fn = write_fn,
            },
        }) catch {};
        return self;
    }

    pub fn render(self: *const Self, w: *std.Io.Writer) !void {
        try w.writeAll("<");
        try w.writeAll(self.tag_name);

        for (self.attributes.items) |attribute| {
            try w.writeAll(" ");
            try w.writeAll(attribute.name);
            try w.writeAll("=\"");
            try escapeHtml(w, attribute.val);
            try w.writeAll("\"");
        }

        if (self.self_closing) {
            try w.writeAll(" />");
            return;
        }

        try w.writeAll(">");

        for (self.children.items) |content| {
            switch (content) {
                .text => |t| try escapeHtml(w, t),
                .raw_html => |h| try w.writeAll(h),
                .elem => |e| try e.render(w),
                .dynamic => |d| {
                    try d.write_fn(d.value_ptr, w);
                },
            }
        }

        try w.writeAll("</");
        try w.writeAll(self.tag_name);
        try w.writeAll(">");
    }

    pub fn renderToString(self: *const Self, alloc: std.mem.Allocator) ![]u8 {
        var h: std.Io.Writer.Allocating = .init(alloc);
        errdefer h.deinit();
        try self.render(&h.writer);
        return h.toOwnedSlice();
    }
};

pub fn elem(alloc: Allocator, name: []const u8) *Element {
    const el = alloc.create(Element) catch unreachable;
    el.* = Element.create(alloc, name);
    return el;
}

pub fn div(alloc: Allocator) *Element {
    return elem(alloc, "div");
}
pub fn span(alloc: Allocator) *Element {
    return elem(alloc, "span");
}
pub fn p(alloc: Allocator) *Element {
    return elem(alloc, "p");
}
pub fn h1(alloc: Allocator) *Element {
    return elem(alloc, "h1");
}
pub fn h2(alloc: Allocator) *Element {
    return elem(alloc, "h2");
}
pub fn h3(alloc: Allocator) *Element {
    return elem(alloc, "h3");
}
pub fn anchor(alloc: Allocator) *Element {
    return elem(alloc, "a");
}
pub fn ul(alloc: Allocator) *Element {
    return elem(alloc, "ul");
}
pub fn ol(alloc: Allocator) *Element {
    return elem(alloc, "ol");
}
pub fn li(alloc: Allocator) *Element {
    return elem(alloc, "li");
}
pub fn table(alloc: Allocator) *Element {
    return elem(alloc, "table");
}
pub fn tr(alloc: Allocator) *Element {
    return elem(alloc, "tr");
}
pub fn td(alloc: Allocator) *Element {
    return elem(alloc, "td");
}
pub fn th(alloc: Allocator) *Element {
    return elem(alloc, "th");
}
pub fn form(alloc: Allocator) *Element {
    return elem(alloc, "form");
}
pub fn input(alloc: Allocator) *Element {
    return elem(alloc, "input").selfClosing();
}
pub fn button(alloc: Allocator) *Element {
    return elem(alloc, "button");
}
pub fn img(alloc: Allocator) *Element {
    return elem(alloc, "img").selfClosing();
}
pub fn br(alloc: Allocator) *Element {
    return elem(alloc, "br").selfClosing();
}
pub fn hr(alloc: Allocator) *Element {
    return elem(alloc, "hr").selfClosing();
}
pub fn strong(alloc: Allocator) *Element {
    return elem(alloc, "strong");
}
pub fn em(alloc: Allocator) *Element {
    return elem(alloc, "em");
}
pub fn nav(alloc: Allocator) *Element {
    return elem(alloc, "nav");
}
pub fn header(alloc: Allocator) *Element {
    return elem(alloc, "header");
}
pub fn footer(alloc: Allocator) *Element {
    return elem(alloc, "footer");
}
pub fn main_(alloc: Allocator) *Element {
    return elem(alloc, "main");
}
pub fn section(alloc: Allocator) *Element {
    return elem(alloc, "section");
}
pub fn article(alloc: Allocator) *Element {
    return elem(alloc, "article");
}

pub const HtmlWriter = struct {
    inner: *std.Io.Writer,

    const Self = @This();

    pub fn create(w: *std.Io.Writer) Self {
        return .{ .inner = w };
    }

    /// Write raw HTML (no escaping)
    pub fn writeRaw(self: *Self, content: []const u8) !void {
        try self.inner.writeAll(content);
    }

    /// Write a value with auto-detected format spec
    pub fn writeValue(self: *Self, v: anytype) !void {
        try std.fmt.format(self.inner, fmtSpec(@TypeOf(v)), .{v});
    }

    /// Write HTML-escaped text
    pub fn writeText(self: *Self, content: []const u8) !void {
        try escapeHtml(self.inner, content);
    }

    /// Write an opening tag
    pub fn open(self: *Self, comptime name: []const u8) !void {
        try self.inner.writeAll("<" ++ name ++ ">");
    }

    /// Write a closing tag
    pub fn close(self: *Self, comptime name: []const u8) !void {
        try self.inner.writeAll("</" ++ name ++ ">");
    }

    /// Write a self-closing tag
    pub fn selfClose(self: *Self, comptime name: []const u8) !void {
        try self.inner.writeAll("<" ++ name ++ " />");
    }

    /// Write opening tag with class
    pub fn openWithClass(self: *Self, comptime name: []const u8, class_value: []const u8) !void {
        try self.inner.writeAll("<" ++ name ++ " class=\"");
        try escapeHtml(self.inner, class_value);
        try self.inner.writeAll("\">");
    }

    /// Write a complete element with text content
    pub fn element(self: *Self, comptime name: []const u8, content: anytype) !void {
        try self.open(name);
        try self.writeValue(content);
        try self.close(name);
    }

    /// Render an Element tree
    pub fn renderElement(self: *Self, el: *const Element) !void {
        try el.render(self.inner);
    }

    /// Get underlying writer
    pub fn getWriter(self: *Self) *std.Io.Writer {
        return self.inner;
    }
};

/// Create an HtmlWriter from a writer interface
pub fn htmlWriter(w: *std.Io.Writer) HtmlWriter {
    return HtmlWriter.create(w);
}

pub fn tag(comptime t: []const u8, comptime content: []const u8) []const u8 {
    return "<" ++ t ++ ">" ++ content ++ "</" ++ t ++ ">";
}

pub fn tagClass(comptime t: []const u8, comptime cls: []const u8, comptime content: []const u8) []const u8 {
    return "<" ++ t ++ " class=\"" ++ cls ++ "\">" ++ content ++ "</" ++ t ++ ">";
}

pub fn voidTag(comptime t: []const u8) []const u8 {
    return "<" ++ t ++ " />";
}

pub const ct = struct {
    pub fn div_(comptime content: []const u8) []const u8 {
        return tag("div", content);
    }
    pub fn span_(comptime content: []const u8) []const u8 {
        return tag("span", content);
    }
    pub fn p_(comptime content: []const u8) []const u8 {
        return tag("p", content);
    }
    pub fn h1_(comptime content: []const u8) []const u8 {
        return tag("h1", content);
    }
    pub fn h2_(comptime content: []const u8) []const u8 {
        return tag("h2", content);
    }
    pub fn h3_(comptime content: []const u8) []const u8 {
        return tag("h3", content);
    }
    pub fn li_(comptime content: []const u8) []const u8 {
        return tag("li", content);
    }
    pub fn strong_(comptime content: []const u8) []const u8 {
        return tag("strong", content);
    }
    pub fn em_(comptime content: []const u8) []const u8 {
        return tag("em", content);
    }
    pub const br_ = voidTag("br");
    pub const hr_ = voidTag("hr");
};

pub fn escapeHtml(w: *std.Io.Writer, content: []const u8) !void {
    for (content) |c| {
        switch (c) {
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '&' => try w.writeAll("&amp;"),
            '"' => try w.writeAll("&quot;"),
            '\'' => try w.writeAll("&#39;"),
            else => try w.writeByte(c),
        }
    }
}

pub fn escapeHtmlAlloc(alloc: std.mem.Allocator, content: []const u8) ![]u8 {
    var h: std.Io.Writer.Allocating = .init(alloc);
    errdefer h.deinit();
    try escapeHtml(&h.writer, content);
    return h.toOwnedSlice();
}
