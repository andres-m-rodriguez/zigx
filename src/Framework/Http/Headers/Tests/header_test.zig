const std = @import("std");
const headers = @import("../headers.zig");

// Header parsing tests
test "Valid single header" {
    var hdrs: headers.Headers = .{};
    defer hdrs.deinit(std.testing.allocator);

    const data = "Host: localhost:42069\r\n\r\n";
    const result = try headers.parse(&hdrs, data, std.testing.allocator);
    if (result != .complete) return error.Incomplete;

    try std.testing.expectEqual(@as(usize, 25), result.complete.bytes_consumed);
    try std.testing.expect(result == .complete);
    try std.testing.expectEqualStrings("localhost:42069", hdrs.get("Host").?);
}

test "Invalid spacing header" {
    var hdrs: headers.Headers = .{};
    defer hdrs.deinit(std.testing.allocator);

    const data = "       Host : localhost:42069       \r\n\r\n";
    const result = headers.parse(&hdrs, data, std.testing.allocator);

    try std.testing.expectError(error.InvalidHeaderFormat, result);
}

test "Multiple headers" {
    var hdrs: headers.Headers = .{};
    defer hdrs.deinit(std.testing.allocator);

    const data = "Host: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";
    const result = try headers.parse(&hdrs, data, std.testing.allocator);

    try std.testing.expect(result == .complete);
    try std.testing.expectEqual(@as(u32, 3), hdrs.count());
    try std.testing.expectEqualStrings("localhost:42069", hdrs.get("Host").?);
    try std.testing.expectEqualStrings("curl/7.81.0", hdrs.get("User-Agent").?);
    try std.testing.expectEqualStrings("*/*", hdrs.get("Accept").?);
}

test "Duplicate header keys combined with comma" {
    var hdrs: headers.Headers = .{};
    defer hdrs.deinit(std.testing.allocator);

    const data = "Accept: text/html\r\nAccept: application/json\r\n\r\n";
    const result = try headers.parse(&hdrs, data, std.testing.allocator);

    try std.testing.expect(result == .complete);
    try std.testing.expectEqual(@as(u32, 1), hdrs.count());
    try std.testing.expectEqualStrings("text/html,application/json", hdrs.get("Accept").?);
}

test "Incomplete headers without terminating CRLF" {
    var hdrs: headers.Headers = .{};
    defer hdrs.deinit(std.testing.allocator);

    const data = "Host: localhost:42069\r\nUser-Agent: curl";
    const result = try headers.parse(&hdrs, data, std.testing.allocator);

    try std.testing.expect(result == .incomplete);
    try std.testing.expectEqual(@as(usize, 23), result.incomplete.bytes_consumed);
}
