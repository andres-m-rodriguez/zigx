const std = @import("std");
pub const placeholders = @import("placeholders");

pub const Writer = std.Io.Writer;

pub fn writeEscapedString(w: *Writer, content: []const u8) !void {
    for (content) |c| {
        switch (c) {
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            else => try w.writeByte(c),
        }
    }
}

pub fn writeFormatString(w: *Writer, content: []const u8) !void {
    var i: usize = 0;

    while (i < content.len) {
        if (placeholders.detectPlaceholder(content, i)) |len| {
            try w.writeAll("{s}");
            i += len;
            continue;
        }

        const c = content[i];
        switch (c) {
            '{' => try w.writeAll("{{"), // Escape { for format string
            '}' => try w.writeAll("}}"), // Escape } for format string
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            else => try w.writeByte(c),
        }
        i += 1;
    }
}

pub fn writeLine(w: *Writer, indent: usize, line: []const u8) !void {
    try writeIndent(w, indent);
    try w.writeAll(line);
    try w.writeAll("\n");
}

pub fn writeIndent(w: *Writer, indent: usize) !void {
    for (0..indent) |_| {
        try w.writeAll("    ");
    }
}

// Standard imports for generated server files that contain framework files
pub const server_imports =
    \\const app_mod = @import("../../Framework/Http/Server/app.zig");
    \\const context_mod = @import("../../Framework/Http/Server/context.zig");
    \\const Response = app_mod.Response;
    \\const RequestContext = app_mod.RequestContext;
    \\const PageContext = context_mod.PageContext;
    \\
    \\
    \\fn zigxFmtSpec(comptime T: type) []const u8 {
    \\    return switch (@typeInfo(T)) {
    \\        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8) "{s}" else "{any}",
    \\        .int, .comptime_int => "{d}",
    \\        .float, .comptime_float => "{d}",
    \\        .bool => "{}",
    \\        else => "{any}",
    \\    };
    \\}
    \\
;

// Additional import needed when using writer-based output (control flow)
pub const std_import = "const std = @import(\"std\");\n";
//Just placeholder for now but someday!
pub const client_imports =
    \\// This file is intended to be compiled to WebAssembly
    \\
;

// Very fun how many times I got this wrong : D
pub const init_call_logic =
    \\    // Call init() if defined by user
    \\    if (@hasDecl(@This(), "init")) {
    \\        const init_fn = @field(@This(), "init");
    \\        const InitFn = @TypeOf(init_fn);
    \\        const params = @typeInfo(InitFn).@"fn".params;
    \\        if (params.len > 0 and params[0].type == *const PageContext) {
    \\            try init_fn(&page_ctx);
    \\        } else {
    \\            try init_fn();
    \\        }
    \\    }
;

pub const page_context_creation =
    \\    // Create PageContext for server code
    \\    const page_ctx = PageContext{
    \\        .allocator = ctx.allocator,
    \\        .request = ctx.request,
    \\        .params = ctx.params,
    \\    };
;
