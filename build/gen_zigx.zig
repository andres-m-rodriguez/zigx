const std = @import("std");
const zigxParser = @import("zigxParser");

// Import codegen modules
const serverGen = @import("codegen/server.zig");
const clientGen = @import("codegen/client.zig");
const routesGen = @import("codegen/routes.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // exe name
    const output_path = args.next() orelse return error.MissingOutputPath;

    // Open project root
    var root = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer root.close();

    // Get the base gen directory from output_path (e.g., "src/gen" from "src/gen/routes.zig")
    const gen_dir = std.fs.path.dirname(output_path) orelse "src/gen";

    std.fs.cwd().makePath(gen_dir) catch {};

    var server_dir_buf: [256]u8 = undefined;
    const server_dir = std.fmt.bufPrint(&server_dir_buf, "{s}/server", .{gen_dir}) catch return error.PathTooLong;
    std.fs.cwd().makePath(server_dir) catch {};

    var client_dir_buf: [256]u8 = undefined;
    const client_dir = std.fmt.bufPrint(&client_dir_buf, "{s}/client", .{gen_dir}) catch return error.PathTooLong;
    std.fs.cwd().makePath(client_dir) catch {};

    // Collect all .zigx files
    var zigx_documents = std.ArrayList(zigxParser.ZigxDocument){};
    defer {
        for (zigx_documents.items) |*doc| {
            doc.deinit(allocator);
        }
        zigx_documents.deinit(allocator);
    }

    var walker = try root.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zigx")) continue;

        var file = try std.fs.cwd().openFile(entry.path, .{});
        defer file.close();
        var file_reading_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(&file_reading_buffer);

        const basename = std.fs.path.basename(entry.path);
        const name_without_ext = basename[0 .. basename.len - 5]; // removes ".zigx"
        const zigx_document = try zigxParser.parse(allocator, &file_reader.interface, name_without_ext);
        try zigx_documents.append(allocator, zigx_document);
    }

    // Generate files using codegen modules
    for (zigx_documents.items) |zigx_document| {
        try serverGen.generate(allocator, server_dir, zigx_document);
        try clientGen.generate(allocator, client_dir, zigx_document);
    }

    // Generate main routes.zig
    try routesGen.generate(allocator, output_path, zigx_documents.items);
}
