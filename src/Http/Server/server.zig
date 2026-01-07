const std = @import("std");
const builtin = @import("builtin");
pub const Request = @import("../Request/request.zig");
pub const Response = @import("../Response/response.zig");
pub const ServerContext = @import("context.zig").ServerContext;

pub const Handler = *const fn (ctx: *ServerContext) anyerror!void;

pub const HttpServer = struct {
    port: u16,
    address: std.net.Address,
    listener: std.net.Server,
    handler: Handler,
    app_instance: ?*anyopaque = null,

    pub fn deinit(self: *HttpServer) void {
        self.listener.deinit();
    }

    pub fn run(self: *HttpServer, allocator: std.mem.Allocator) !void {
        std.debug.print("Listening on port {}\n", .{self.port});

        var request_count: usize = 0;
        const max_requests: ?usize = if (builtin.is_test or builtin.mode == .Debug) 5 else null;

        while (true) {
            const connection = try self.listener.accept();
            _ = std.Thread.spawn(.{}, handleConnection, .{ allocator, connection, self }) catch |err| {
                std.debug.print("Failed to spawn thread: {}\n", .{err});
                connection.stream.close();
            };

            request_count += 1;
            if (max_requests) |max| {
                if (request_count >= max) {
                    std.debug.print("Test mode: reached {} requests, shutting down\n", .{max});
                    return;
                }
            }
        }
    }
};

pub fn create(port: u16, handler: Handler, app_instance: ?*anyopaque) !HttpServer {
    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    const listener = try address.listen(.{});

    return HttpServer{
        .port = port,
        .address = address,
        .listener = listener,
        .handler = handler,
        .app_instance = app_instance,
    };
}

fn handleConnection(allocator: std.mem.Allocator, connection: std.net.Server.Connection, httpServer: *HttpServer) void {
    defer connection.stream.close();

    // Areana allocator per request because we are smart like that
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const request_allocator = arena.allocator();

    var default_headers = Response.getDefaultResponseHeaders(request_allocator, 0) catch return;

    //Yes 1 byte at a time :D

    var read_buffer: [1]u8 = undefined;
    var stream_reader = connection.stream.reader(&read_buffer);

    //Yes idk what this buffer fully does since its internal BUT...we ball
    var write_buffer: [4096]u8 = undefined;
    var con_writer = connection.stream.writer(&write_buffer);
    var response_writer = Response.ResponseWriter{
        .writer = &con_writer.interface,
    };

    var req = Request.requestFromReader(stream_reader.interface(), request_allocator) catch {
        response_writer.writeStatusLine(Response.StatusCode.StatusInternalServerError) catch return;
        response_writer.writeHeaders(&default_headers) catch return;
        return;
    };

    var body_writer = Response.ResponseWriter{
        .writer = &con_writer.interface,
    };

    var ctx = ServerContext{
        .allocator = request_allocator,
        .writer = &body_writer,
        .req = &req,
        .app_instance = httpServer.app_instance,
    };

    httpServer.handler(&ctx) catch |err| {
        std.debug.print("{}", .{err});
        response_writer.writeStatusLine(Response.StatusCode.StatusInternalServerError) catch return;
        response_writer.writeHeaders(&default_headers) catch return;
        return;
    };

    response_writer.flush() catch return;
}
