const std = @import("std");

// Import test files so they're included in the test build
test {
    _ = @import("Http/Request/Tests/header_test.zig");
    _ = @import("Http/Request/Tests/request_test.zig");
    _ = @import("Http/Request/Tests/requestLine_test.zig");
}

pub const ChunkReader = struct {
    data: []const u8,
    num_bytes_per_read: usize,
    pos: usize = 0,
    interface: std.Io.Reader,

    pub fn init(data: []const u8, num_bytes_per_read: usize, buffer: []u8) ChunkReader {
        return .{
            .data = data,
            .num_bytes_per_read = num_bytes_per_read,
            .interface = .{
                .vtable = &.{
                    .stream = stream,
                },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
        };
    }

    fn stream(io_reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *ChunkReader = @alignCast(@fieldParentPtr("interface", io_reader));

        if (self.pos >= self.data.len) {
            return error.EndOfStream;
        }

        const max_read = @min(self.num_bytes_per_read, limit.toInt() orelse self.num_bytes_per_read);
        const end_index = @min(self.pos + max_read, self.data.len);
        const chunk = self.data[self.pos..end_index];

        try writer.writeAll(chunk);
        self.pos += chunk.len;

        return chunk.len;
    }

    pub fn reader(self: *ChunkReader) *std.Io.Reader {
        return &self.interface;
    }
};
