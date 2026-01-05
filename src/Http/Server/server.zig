const std = @import("std");
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
    handler: *const fn (allocator: std.mem.Allocator, writer: *std.Io.Writer, req: *Request.Request) anyerror!HandlerResult,
    pub fn deinit(self: *HttpServer) void {
        self.listener.deinit();
    }

    pub fn run(self: *HttpServer, allocator: std.mem.Allocator) !void {
        std.debug.print("Listening on port {}\n", .{self.port});

        while (true) {
            const connection = try self.listener.accept();
            _ = std.Thread.spawn(.{}, handleConnection, .{ allocator, connection, self }) catch |err| {
                std.debug.print("Failed to spawn thread: {}\n", .{err});
                connection.stream.close();
            };
        }
    }
};

pub fn create(port: u16, errorHandler: *const fn (allocator: std.mem.Allocator, writer: *std.Io.Writer, req: *Request.Request) anyerror!HandlerResult) !HttpServer {
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
    var default_headers = Response.getDefaultHeaders(allocator, 0) catch return;
    defer default_headers.deinit(allocator);

    var read_buffer: [1]u8 = undefined;
    var stream_reader = connection.stream.reader(&read_buffer);

    var write_buffer: [4096]u8 = undefined;
    var response_writer = connection.stream.writer(&write_buffer);

    var req = Request.requestFromReader(stream_reader.interface(), allocator) catch {
        Response.writeStatusLine(&response_writer.interface, Response.StatusCode.StatusInternalServerError) catch return;
        Response.writeHeaders(&response_writer.interface, default_headers) catch return;
        return;
    };
    defer req.deinit(allocator); // free everything

    var body_buffer: std.ArrayList(u8) = .empty;
    defer body_buffer.deinit(allocator);
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &body_buffer);

    const results = httpServer.handler(allocator, &aw.writer, &req) catch {
        Response.writeStatusLine(&response_writer.interface, Response.StatusCode.StatusInternalServerError) catch return;
        Response.writeHeaders(&response_writer.interface, default_headers) catch return;
        return;
    };
    if (results == .failed) {
        var len_buf: [20]u8 = undefined;
        const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{results.failed.message.len}) catch unreachable;
        default_headers.replace("Content-Length", len_str, allocator) catch return;

        Response.writeStatusLine(&response_writer.interface, results.failed.status_code) catch return;
        Response.writeHeaders(&response_writer.interface, default_headers) catch return;
        response_writer.interface.writeAll(results.failed.message) catch return;
        response_writer.interface.flush() catch return;
        return;
    }
    body_buffer = aw.toArrayList();
    const body_length = body_buffer.items.len;
    var body_lenght_buf: [20]u8 = undefined;
    const length_str = std.fmt.bufPrint(&body_lenght_buf, "{d}", .{body_length}) catch unreachable;
    default_headers.replace("Content-Length", length_str, allocator) catch unreachable;

    Response.writeStatusLine(&response_writer.interface, Response.StatusCode.StatusOk) catch unreachable;
    Response.writeHeaders(&response_writer.interface, default_headers) catch unreachable;
    response_writer.interface.writeAll(body_buffer.items) catch return;

    // The great one and only flush!
    // You shall not be forgotten...
    response_writer.interface.flush() catch return;
}
