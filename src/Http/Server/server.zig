const std = @import("std");
const request = @import("../Request/request.zig");
const response = @import("../Response/response.zig");
pub const HttpServer = struct {
    port: u16,
    address: std.net.Address,
    listener: std.net.Server,

    pub fn deinit(self: *HttpServer) void {
        self.listener.deinit();
    }

    pub fn run(self: *HttpServer, allocator: std.mem.Allocator) !void {
        std.debug.print("Listening on port {}\n", .{self.port});

        while (true) {
            const connection = try self.listener.accept();
            _ = std.Thread.spawn(.{}, handleConnection, .{ allocator, connection }) catch |err| {
                std.debug.print("Failed to spawn thread: {}\n", .{err});
                connection.stream.close();
            };
        }
    }
};

pub fn create(port: u16) !HttpServer {
    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    const listener = try address.listen(.{});

    return HttpServer{
        .port = port,
        .address = address,
        .listener = listener,
    };
}

fn handleConnection(allocator: std.mem.Allocator, connection: std.net.Server.Connection) void {
    std.debug.print("Request recieved.\n", .{});
    defer connection.stream.close();

    var read_buffer: [1]u8 = undefined;
    var stream_reader = connection.stream.reader(&read_buffer);

    var req = request.requestFromReader(stream_reader.interface(), allocator) catch |err| {
        std.debug.print("Request parse error: {}\n", .{err});
        return;
    };
    defer req.deinit(allocator); // free everything

    var write_buffer: [4096]u8 = undefined;
    var stream_writer = connection.stream.writer(&write_buffer);

    writeResponse(&stream_writer.interface, allocator) catch return;
    // The great one and only flush!
    // You shall not be forgotten...
    stream_writer.interface.flush() catch return;
}

fn writeResponse(writer: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    try response.writeStatusLine(writer, response.StatusCode.StatusOk);
    var default_headers = try response.getDefaultHeaders(allocator, 0);
    defer default_headers.deinit(allocator);
    try response.writeHeaders(writer, default_headers);
}
