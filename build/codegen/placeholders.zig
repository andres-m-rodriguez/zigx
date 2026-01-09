const std = @import("std");

pub const EXPR_PREFIX = "__ZIGX_EXPR_";
pub const EXPR_SUFFIX = "__";

pub fn createPlaceholder(buf: []u8, index: usize) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}{d}{s}", .{ EXPR_PREFIX, index, EXPR_SUFFIX });
}

pub fn detectPlaceholder(content: []const u8, pos: usize) ?usize {
    if (pos + EXPR_PREFIX.len > content.len) return null;
    if (!std.mem.startsWith(u8, content[pos..], EXPR_PREFIX)) return null;

    var j = pos + EXPR_PREFIX.len;
    while (j < content.len and content[j] >= '0' and content[j] <= '9') : (j += 1) {}
    if (j + EXPR_SUFFIX.len <= content.len and
        std.mem.eql(u8, content[j .. j + EXPR_SUFFIX.len], EXPR_SUFFIX))
    {
        return j + EXPR_SUFFIX.len - pos;
    }

    return null;
}

// "__ZIGX_EXPR_5__" returns 5
pub fn parseIndex(placeholder: []const u8) ?usize {
    if (!std.mem.startsWith(u8, placeholder, EXPR_PREFIX)) return null;

    const num_start = EXPR_PREFIX.len;
    var num_end = num_start;
    while (num_end < placeholder.len and placeholder[num_end] >= '0' and placeholder[num_end] <= '9') {
        num_end += 1;
    }

    if (num_end == num_start) return null;
    return std.fmt.parseInt(usize, placeholder[num_start..num_end], 10) catch null;
}

test "createPlaceholder" {
    var buf: [32]u8 = undefined;
    const p0 = try createPlaceholder(&buf, 0);
    try std.testing.expectEqualStrings("__ZIGX_EXPR_0__", p0);
}

test "detectPlaceholder" {
    const content = "Hello __ZIGX_EXPR_0__ world";
    const len = detectPlaceholder(content, 6);
    try std.testing.expectEqual(@as(usize, 15), len.?);
}

test "parseIndex" {
    try std.testing.expectEqual(@as(usize, 0), parseIndex("__ZIGX_EXPR_0__").?);
    try std.testing.expectEqual(@as(usize, 42), parseIndex("__ZIGX_EXPR_42__").?);
    try std.testing.expectEqual(@as(?usize, null), parseIndex("invalid"));
}
