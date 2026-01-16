const std = @import("std");
const common = @import("common");
const zigxParser = @import("zigxParser");
const zigServerParser = @import("zigServerParser");
const render_tree = @import("render_tree");

const Writer = common.Writer;
const Node = zigxParser.Node;

pub fn generate(allocator: std.mem.Allocator, server_dir: []const u8, doc: zigxParser.ZigxDocument) !void {
    var path_buf: [512]u8 = undefined;
    const file_path = std.fmt.bufPrint(&path_buf, "{s}/{s}.zig", .{ server_dir, doc.file_name }) catch return error.PathTooLong;

    var out_file = try std.fs.cwd().createFile(file_path, .{});
    defer out_file.close();

    var buf: [4096]u8 = undefined;
    var writer = out_file.writer(&buf);
    const w = &writer.interface;

    var parser = zigServerParser.ZigParser.init(doc.server_code);
    var zig_doc = parser.parse(allocator) catch return error.ParseError;
    defer zig_doc.deinit(allocator);

    try writeHeader(w, doc.file_name, &zig_doc);
    try writeServerCode(w, doc.server_code);
    try writeHandler(w, doc);
    try writer.interface.flush();
}

fn writeHeader(w: *Writer, file_name: []const u8, zig_doc: *const zigServerParser.ZigFile) !void {
    try w.print(
        \\
    , .{});

    if (!zig_doc.hasImport("std")) {
        try w.writeAll(common.std_import);
    }

    try w.writeAll(common.server_imports);
    try w.writeAll("const render_tree = @import(\"render_tree\");\n");

    try w.print(
        \\
        \\pub const page_title = "{s}";
        \\
        \\
    , .{file_name});
}

fn writeServerCode(w: *Writer, server_code: []const u8) !void {
    if (server_code.len > 0) {
        try w.writeAll(server_code);
        try w.writeAll("\n\n");
    }
}

fn writeHandler(w: *Writer, doc: zigxParser.ZigxDocument) !void {
    try writeRenderTreeHandler(w, doc);
}

fn writeHandlerIdTable(w: *Writer, doc: zigxParser.ZigxDocument) !void {
    if (doc.event_handlers.len == 0) return;

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

fn writeRenderTreeHandler(w: *Writer, doc: zigxParser.ZigxDocument) !void {
    try writeHandlerIdTable(w, doc);

    try w.writeAll("pub fn handler(ctx: *RequestContext) !Response {\n");

    try w.writeAll(common.page_context_creation);
    try w.writeAll("\n\n");

    try w.writeAll(common.init_call_logic);
    try w.writeAll("\n\n");

    try w.writeAll(
        \\    var builder = render_tree.RenderTreeBuilder{};
        \\    errdefer builder.deinit(ctx.allocator);
        \\
        \\
    );

    var seq: u32 = 0;
    for (doc.content) |node| {
        try writeRenderNodeCode(w, node, &seq, 1);
    }

    try w.writeAll(
        \\
        \\    var tree = try builder.build(ctx.allocator);
        \\    defer tree.deinit(ctx.allocator);
        \\
        \\    const content_html = try render_tree.toHtmlString(ctx.allocator, tree);
        \\    defer ctx.allocator.free(content_html);
        \\
        \\    var h: std.Io.Writer.Allocating = .init(ctx.allocator);
        \\    errdefer h.deinit();
        \\
        \\    try h.writer.writeAll("<!DOCTYPE html><html><head><title>
    );
    try w.writeAll(doc.file_name);
    try w.writeAll(
        \\</title></head><body><div id=\"zigx-root\">");
        \\    try h.writer.writeAll(content_html);
        \\    try h.writer.writeAll("</div>");
        \\
    );

    if (hasClientCode(doc)) {
        try w.writeAll(
            \\
            \\    try h.writer.writeAll("<script src=\"/_zigx/runtime.js\"></script>");
            \\    try h.writer.writeAll("<script>ZigxRuntime.load('/_zigx/
        );
        try w.writeAll(doc.file_name);
        try w.writeAll(
            \\.wasm');</script>");
            \\
        );
    }

    try w.writeAll(
        \\
        \\    try h.writer.writeAll("</body></html>");
        \\
        \\    return Response.html(try h.toOwnedSlice());
        \\}
        \\
    );
}

fn writeRenderNodeCode(w: *Writer, node: Node, seq: *u32, indent: usize) !void {
    switch (node) {
        .html => |text| {
            if (text.len > 0) {
                try writeIndent(w, indent);
                try w.print("try builder.addText(ctx.allocator, {d}, \"", .{seq.*});
                try writeEscapedForString(w, text);
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
            try w.print("try builder.addText(ctx.allocator, {d}, text);\n", .{seq.*});
            try writeIndent(w, indent);
            try w.writeAll("}\n");
            seq.* += 1;
        },
        .event_handler => |eh| {
            try writeIndent(w, indent);
            try w.print("try builder.addEvent(ctx.allocator, {d}, \"{s}\", handler_ids.{s});\n", .{ seq.*, eh.event[2..], eh.handler });
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

fn hasClientCode(doc: zigxParser.ZigxDocument) bool {
    return doc.client_code.len > 0;
}

fn writeIndent(w: *Writer, indent: usize) !void {
    for (0..indent) |_| {
        try w.writeAll("    ");
    }
}

fn writeEscapedForString(w: *Writer, content: []const u8) !void {
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
