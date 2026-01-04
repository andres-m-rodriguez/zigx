const std = @import("std");

const ParseResult = union(enum) {
    complete: struct {
        request_line: RequestLine,
        bytes_consumed: usize,
    },
    incomplete: struct {
        bytes_read: usize,
    },

    pub fn Complete(value: RequestLine, bytes_consumed: usize) ParseResult {
        return ParseResult{
            .complete = .{
                .request_line = value,
                .bytes_consumed = bytes_consumed,
            },
        };
    }
    pub fn Incomplete(bytes_consumed: usize) ParseResult {
        return ParseResult{
            .incomplete = .{
                .bytes_read = bytes_consumed,
            },
        };
    }
};

pub const RequestLine = struct {
    http_version: []const u8,
    request_target: []const u8,
    method: []const u8,

    pub fn deinit(self: *RequestLine, allocator: std.mem.Allocator) void {
        allocator.free(self.method);
        allocator.free(self.request_target);
        allocator.free(self.http_version);
    }
};

pub const Error = std.mem.Allocator.Error || error{
    MalformedRequestLine,
    InvalidMethod,
    InvalidVersion,
    InvalidTarget,
};
pub fn parse(allocator: std.mem.Allocator, data: []u8) Error!ParseResult {
    const rn_delimiter = "\r\n";
    const rn_index = std.mem.indexOf(u8, data, rn_delimiter) orelse return ParseResult.Incomplete(data.len);
    const request_line_bytes = data[0..rn_index];

    var request_line = try parseRequestLine(allocator, request_line_bytes);
    errdefer request_line.deinit(allocator);
    try validate_request_line(request_line);
    return ParseResult.Complete(request_line, rn_index + rn_delimiter.len);
}
pub fn parseRequestLine(allocator: std.mem.Allocator, line: []u8) Error!RequestLine {
    var parts_iterator = std.mem.splitScalar(u8, line, ' ');

    const method_raw = parts_iterator.next() orelse return Error.MalformedRequestLine;
    const target_raw = parts_iterator.next() orelse return Error.MalformedRequestLine;
    const version_raw = parts_iterator.next() orelse return Error.MalformedRequestLine;

    if (parts_iterator.next() != null) return Error.MalformedRequestLine;

    var version_iterator = std.mem.splitScalar(u8, version_raw, '/');
    _ = version_iterator.next() orelse return Error.MalformedRequestLine; // "HTTP"
    const version_value = version_iterator.next() orelse return Error.MalformedRequestLine;

    const method = try allocator.dupe(u8, method_raw);
    errdefer allocator.free(method);
    const request_target = try allocator.dupe(u8, target_raw);
    errdefer allocator.free(request_target);
    const http_version = try allocator.dupe(u8, version_value);

    return RequestLine{
        .method = method,
        .request_target = request_target,
        .http_version = http_version,
    };
}

fn validate_request_line(requestLine: RequestLine) Error!void {
    if (!std.mem.eql(u8, requestLine.http_version, "1.1")) {
        return Error.InvalidVersion;
    }
}
