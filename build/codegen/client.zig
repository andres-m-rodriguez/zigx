const std = @import("std");
const common = @import("common");
const zigxParser = @import("zigxParser");

const Writer = common.Writer;
const Node = zigxParser.Node;

pub fn generate(allocator: std.mem.Allocator, client_dir: []const u8, doc: zigxParser.ZigxDocument) !void {
    if (doc.client_code.len == 0) return;

    var path_buf: [512]u8 = undefined;
    const file_path = std.fmt.bufPrint(&path_buf, "{s}/{s}.zig", .{ client_dir, doc.file_name }) catch return error.PathTooLong;

    var out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    var buf: [65536]u8 = undefined;
    var writer = out_file.writer(&buf);
    const w = &writer.interface;

    try writeHeader(w, doc.file_name);
    try writeClientCode(w, doc.client_code);
    try writeHandlerIdTable(w, doc);
    try writeRenderState(w);
    try writeRenderFunction(w, doc);
    try writeUpdateFunction(w);
    try writeWasmExports(w, doc);
    try writer.interface.flush();

    _ = allocator;
}

fn writeHeader(w: *Writer, file_name: []const u8) !void {
    try w.print(
        \\const std = @import("std");
        \\const rt = @import("runtime");
        \\const render_tree = @import("render_tree");
        \\
        \\pub const page_title = "{s}";
        \\
        \\
    , .{file_name});
}

fn writeClientCode(w: *Writer, client_code: []const u8) !void {
    try w.writeAll(client_code);
    try w.writeAll("\n");
}

fn writeHandlerIdTable(w: *Writer, doc: zigxParser.ZigxDocument) !void {
    try w.writeAll(
        \\
        \\const handler_ids = struct {
        \\
    );

    for (doc.event_handlers, 0..) |eh, idx| {
        try w.print("    pub const {s} = {d};\n", .{ eh.handler, idx });
    }

    try w.writeAll(
        \\};
        \\
        \\
    );
}

fn writeRenderState(w: *Writer) !void {
    try w.writeAll(
        \\var wasm_allocator = std.heap.wasm_allocator;
        \\
        \\var arena_a: std.heap.ArenaAllocator = undefined;
        \\var arena_b: std.heap.ArenaAllocator = undefined;
        \\var using_arena_a: bool = true;
        \\var arenas_initialized: bool = false;
        \\
        \\var root_handle: u32 = 0;
        \\
        \\fn getCurrentAllocator() std.mem.Allocator {
        \\    if (!arenas_initialized) {
        \\        arena_a = std.heap.ArenaAllocator.init(wasm_allocator);
        \\        arena_b = std.heap.ArenaAllocator.init(wasm_allocator);
        \\        arenas_initialized = true;
        \\    }
        \\    return if (using_arena_a) arena_a.allocator() else arena_b.allocator();
        \\}
        \\
        \\fn swapArenas() void {
        \\    using_arena_a = !using_arena_a;
        \\    if (using_arena_a) {
        \\        _ = arena_a.reset(.retain_capacity);
        \\    } else {
        \\        _ = arena_b.reset(.retain_capacity);
        \\    }
        \\}
        \\
        \\
    );
}

fn writeRenderFunction(w: *Writer, doc: zigxParser.ZigxDocument) !void {
    try w.writeAll(
        \\fn render(allocator: std.mem.Allocator) !render_tree.RenderTree {
        \\    var builder = render_tree.RenderTreeBuilder{};
        \\    errdefer builder.deinit(allocator);
        \\
        \\
    );

    var seq: u32 = 0;
    for (doc.content) |node| {
        try writeRenderNodeCode(w, node, &seq, 1);
    }

    try w.writeAll(
        \\
        \\    return builder.build(allocator);
        \\}
        \\
        \\
    );
}

fn writeRenderNodeCode(w: *Writer, node: Node, seq: *u32, indent: usize) !void {
    switch (node) {
        .html => |text| {
            if (text.len > 0) {
                try writeIndent(w, indent);
                try w.print("try builder.addText(allocator, {d}, \"", .{seq.*});
                try writeEscapedString(w, text);
                try w.writeAll("\");\n");
                seq.* += 1;
            }
        },
        .expression => |expr| {
            try writeIndent(w, indent);
            try w.writeAll("{\n");
            try writeIndent(w, indent + 1);
            try w.writeAll("var buf: [256]u8 = undefined;\n");
            try writeIndent(w, indent + 1);
            try w.print("const text = std.fmt.bufPrint(&buf, render_tree.fmtSpec(@TypeOf({s})), .{{{s}}}) catch \"?\";\n", .{ expr, expr });
            try writeIndent(w, indent + 1);
            try w.print("try builder.addText(allocator, {d}, text);\n", .{seq.*});
            try writeIndent(w, indent);
            try w.writeAll("}\n");
            seq.* += 1;
        },
        .event_handler => |eh| {
            try writeIndent(w, indent);
            try w.print("try builder.addEvent(allocator, {d}, \"{s}\", handler_ids.{s});\n", .{ seq.*, eh.event[2..], eh.handler });
            seq.* += 1;
        },
        .for_loop => |loop| {
            try writeIndent(w, indent);
            try w.print("for ({s}) |{s}| {{\n", .{ loop.collection, loop.capture });

            for (loop.body) |child| {
                try writeRenderNodeCode(w, child, seq, indent + 1);
            }

            try writeIndent(w, indent);
            try w.writeAll("}\n");
        },
        .if_stmt => |stmt| {
            try writeIndent(w, indent);
            try w.print("if ({s}) {{\n", .{stmt.condition});

            for (stmt.then_body) |child| {
                try writeRenderNodeCode(w, child, seq, indent + 1);
            }

            if (stmt.else_body) |else_nodes| {
                try writeIndent(w, indent);
                try w.writeAll("} else {\n");

                for (else_nodes) |child| {
                    try writeRenderNodeCode(w, child, seq, indent + 1);
                }
            }

            try writeIndent(w, indent);
            try w.writeAll("}\n");
        },
        .while_loop => |loop| {
            try writeIndent(w, indent);
            try w.print("while ({s})", .{loop.condition});

            if (loop.capture) |cap| {
                try w.print(" |{s}|", .{cap});
            }

            try w.writeAll(" {\n");

            for (loop.body) |child| {
                try writeRenderNodeCode(w, child, seq, indent + 1);
            }

            try writeIndent(w, indent);
            try w.writeAll("}\n");
        },
    }
}

fn writeUpdateFunction(w: *Writer) !void {
    try w.writeAll(
        \\fn update() void {
        \\    const allocator = getCurrentAllocator();
        \\
        \\    var new_tree = render(allocator) catch {
        \\        rt.log("Render error");
        \\        return;
        \\    };
        \\    defer new_tree.deinit(allocator);
        \\
        \\    if (root_handle == 0) {
        \\        root_handle = rt.getRootHandle();
        \\    }
        \\
        \\    const html = render_tree.toHtmlString(allocator, new_tree) catch {
        \\        rt.log("toHtmlString error");
        \\        return;
        \\    };
        \\    defer allocator.free(html);
        \\
        \\    rt.setInnerHTML(root_handle, html);
        \\
        \\    swapArenas();
        \\}
        \\
        \\
    );
}

fn writeWasmExports(w: *Writer, doc: zigxParser.ZigxDocument) !void {
    try w.writeAll(
        \\
    );

    for (doc.event_handlers) |eh| {
        try w.print(
            \\export fn _zigx_{s}() callconv(std.builtin.CallingConvention.c) void {{
            \\    {s}();
            \\    update();
            \\}}
            \\
            \\
        , .{ eh.handler, eh.handler });
    }

    for (doc.event_handlers, 0..) |eh, idx| {
        try w.print(
            \\export fn _zigx_handler_{d}() callconv(std.builtin.CallingConvention.c) void {{
            \\    {s}();
            \\    update();
            \\}}
            \\
            \\
        , .{ idx, eh.handler });
    }

    try w.writeAll(
        \\export fn _zigx_init() callconv(std.builtin.CallingConvention.c) void {
        \\    if (root_handle == 0) {
        \\        root_handle = rt.getRootHandle();
        \\    }
        \\}
        \\
    );
}

fn writeIndent(w: *Writer, indent: usize) !void {
    for (0..indent) |_| {
        try w.writeAll("    ");
    }
}

fn writeEscapedString(w: *Writer, content: []const u8) !void {
    for (content) |c| {
        switch (c) {
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            else => try w.writeByte(c),
        }
    }
}
