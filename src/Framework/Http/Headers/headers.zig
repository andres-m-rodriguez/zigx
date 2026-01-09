const std = @import("std");

pub const ParseResult = union(enum) {
    complete: struct {
        bytes_consumed: usize,
    },
    incomplete: struct {
        bytes_consumed: usize,
    },

    pub fn Complete(bytes_consumed: usize) ParseResult {
        return ParseResult{
            .complete = .{
                .bytes_consumed = bytes_consumed,
            },
        };
    }

    pub fn Incomplete(bytes_read: usize) ParseResult {
        return ParseResult{
            .incomplete = .{
                .bytes_consumed = bytes_read,
            },
        };
    }
};
pub const Error = std.mem.Allocator.Error || error{
    InvalidHeaderFormat,
    InvalidSpacing,
    HeaderKeyEmpty,
    HeaderKeyMalformed,
};
pub const HeaderError = error{InvalidInteger};
pub const Headers = struct {
    map: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub fn get(self: *const Headers, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }
    pub fn getInt(self: *const Headers, key: []const u8) HeaderError!?i64 {
        const value = self.map.get(key) orelse return null;
        return std.fmt.parseInt(i64, value, 10) catch return error.InvalidInteger;
    }

    pub fn replace(self: *Headers, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
        const gop = try self.map.getOrPut(allocator, key);

        if (gop.found_existing) {
            allocator.free(gop.value_ptr.*);
        } else {
            gop.key_ptr.* = try allocator.dupe(u8, key);
        }

        gop.value_ptr.* = try allocator.dupe(u8, value);
    }
    pub fn delete(self: *Headers, key: []const u8, allocator: std.mem.Allocator) bool {
        const entry = self.map.fetchRemove(key) orelse return false;
        allocator.free(entry.key);
        allocator.free(entry.value);

        return true;
    }
    pub fn set(self: *Headers, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
        const key_copy = try allocator.dupe(u8, key);
        const gop = try self.map.getOrPut(allocator, key_copy);

        if (gop.found_existing) {
            // Combine values with comma
            const new_value = try std.fmt.allocPrint(allocator, "{s},{s}", .{ gop.value_ptr.*, value });

            allocator.free(gop.value_ptr.*);
            allocator.free(key_copy);

            gop.value_ptr.* = new_value;
        } else {
            gop.value_ptr.* = try allocator.dupe(u8, value);
        }
    }

    pub fn deinit(self: *Headers, allocator: std.mem.Allocator) void {
        var deinit_iterator = self.map.iterator();
        while (deinit_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.map.deinit(allocator);
    }

    pub fn count(self: *const Headers) u32 {
        return self.map.count();
    }

    pub fn iterator(self: *const Headers) std.StringHashMapUnmanaged([]const u8).Iterator {
        return self.map.iterator();
    }
};

pub fn parse(hdrs: *Headers, data: []const u8, allocator: std.mem.Allocator) Error!ParseResult {
    const rn_delimiter = "\r\n";
    var read: usize = 0;
    while (true) {
        const rn_index = std.mem.indexOf(u8, data[read..], rn_delimiter) orelse
            return ParseResult.Incomplete(read);

        if (rn_index == 0)
            return ParseResult.Complete(read + rn_delimiter.len);

        var parsed_header = try parseHeader(data[read .. read + rn_index]);
        try validate_header(&parsed_header);
        try hdrs.set(parsed_header.key, parsed_header.value, allocator);
        read += rn_index + rn_delimiter.len;
    }
}
const Header = struct {
    key: []const u8,
    value: []const u8,
};
fn parseHeader(data: []const u8) !Header {
    const colon_index = std.mem.indexOf(u8, data, ":") orelse return Error.InvalidHeaderFormat;
    const field_name = data[0..colon_index];
    const field_value_raw = data[colon_index + 1 ..];
    const field_value = std.mem.trim(u8, field_value_raw, " \t");

    return Header{ .key = field_name, .value = field_value };
}
fn validate_header(header: *Header) !void {
    if (header.key.len == 0) return Error.HeaderKeyEmpty;
    if (std.mem.indexOfAny(u8, header.key, " \t")) |_|
        return Error.InvalidHeaderFormat;

    if (!isValidTokenString(header.key))
        return Error.HeaderKeyMalformed;
}

const token_chars = blk: {
    var table = [_]bool{false} ** 256;
    for ('A'..'Z' + 1) |c| table[c] = true;
    for ('a'..'z' + 1) |c| table[c] = true;
    for ('0'..'9' + 1) |c| table[c] = true;
    for ("!#$%&'*+-.^_`|~") |c| table[c] = true;
    break :blk table;
};

fn isToken(char: u8) bool {
    return token_chars[char];
}
fn isValidTokenString(str: []const u8) bool {
    for (str) |char| {
        if (!isToken(char)) return false;
    }
    return true;
}
