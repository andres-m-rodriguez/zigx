const std = @import("std");
const builtin = @import("builtin");
pub const Request = @import("../Request/request.zig");
pub const Response = @import("../Response/response.zig");

pub const HandlerResult = union(enum) {
    success: struct {},
    failed: struct {
        status_code: Response.StatusCode,
        message: []const u8,
    },

    pub fn Failed(message: []const u8, statusCode: Response.StatusCode) HandlerResult {
        return HandlerResult{
            .failed = .{
                .message = message,
                .status_code = statusCode,
            },
        };
    }
    pub fn Success() HandlerResult {
        return HandlerResult{
            .success = .{},
        };
    }
};
pub const HttpServer = struct {
    port: u16,
    address: std.net.Address,
    listener: std.net.Server,
    handler: *const fn (allocator: std.mem.Allocator, writer: *Response.ResponseWriter, req: *Request.Request) anyerror!HandlerResult,
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

pub fn create(port: u16, errorHandler: *const fn (
    allocator: std.mem.Allocator,
    writer: *Response.ResponseWriter,
    req: *Request.Request,
) anyerror!HandlerResult) !HttpServer {
    const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    const listener = try address.listen(.{});

    return HttpServer{
        .port = port,
        .address = address,
        .listener = listener,
        .handler = errorHandler,
    };
}

fn handleConnection(allocator: std.mem.Allocator, connection: std.net.Server.Connection, httpServer: *HttpServer) void {
    defer connection.stream.close();
    var default_headers = Response.getDefaultResponseHeaders(allocator, 0) catch return;
    defer default_headers.deinit(allocator);

    var read_buffer: [1]u8 = undefined;
    var stream_reader = connection.stream.reader(&read_buffer);

    var write_buffer: [4096]u8 = undefined;
    var con_writer = connection.stream.writer(&write_buffer);
    var response_writer = Response.ResponseWriter{
        .writer = &con_writer.interface,
    };

    var req = Request.requestFromReader(stream_reader.interface(), allocator) catch {
        response_writer.writeStatusLine(Response.StatusCode.StatusInternalServerError) catch return;
        response_writer.writeHeaders(&default_headers) catch return;
        return;
    };
    defer req.deinit(allocator); // free everything

    var body_writer = Response.ResponseWriter{
        .writer = &con_writer.interface,
    };

    _ = httpServer.handler(allocator, &body_writer, &req) catch {
        response_writer.writeStatusLine(Response.StatusCode.StatusInternalServerError) catch return;
        response_writer.writeHeaders(&default_headers) catch return;
        return;
    };

    // The great one and only flush!
    // You shall not be forgotten...
    response_writer.flush() catch return;
}
