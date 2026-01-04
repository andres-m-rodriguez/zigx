const std = @import("std");
pub const headers = @import("../Headers/headers.zig");
pub const requestLine = @import("requestLine.zig");

const Request = struct {
    request_line: ?requestLine.RequestLine = null,
    request_headers: headers.Headers = undefined,
    request_body: std.ArrayList(u8) = undefined,

    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        self.request_headers.deinit(allocator);
        if (self.request_line) |*rl| rl.deinit(allocator);
        self.request_body.deinit(allocator);
    }
};
const ParsingState = struct {
    state: State = .Init,

    const State = enum {
        Init, //Request line parsing state
        Headers,
        BodyInit,
        Body,
        Done,
    };

    pub fn next(self: *ParsingState) void {
        switch (self.state) {
            .Init => self.state = ParsingState.State.Headers,
            .Headers => self.state = ParsingState.State.BodyInit,
            .BodyInit => self.state = ParsingState.State.Body,
            .Body => self.state = ParsingState.State.Done,
            .Done => {},
        }
    }
    pub fn complete(self: *ParsingState) void {
        self.state = ParsingState.State.Done;
    }
    pub fn done(self: *ParsingState) bool {
        return self.state == State.Done;
    }
};

pub const Error = requestLine.Error || headers.Error ||
    std.Io.Reader.Error || error{ RequestIncomplete, RequestEmpty };

pub fn requestFromReader(reader: *std.Io.Reader, allocator: std.mem.Allocator) Error!Request {
    var request_state = ParsingState{};
    var request = Request{
        .request_headers = headers.Headers{},
        .request_body = std.ArrayList(u8){},
    };
    errdefer request.deinit(allocator);
    var current_line = std.ArrayList(u8){};

    defer current_line.deinit(allocator);
    var consumed: usize = 0;

    while (true) {
        //We check how much we can read going foward...ensuring at least 1 byte comes in, if not then we close
        const data = reader.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => {
                if (current_line.items.len == 0) return Error.RequestEmpty;
                return Error.RequestIncomplete;
            },
            error.ReadFailed => return Error.ReadFailed,
        };

        reader.toss(data.len); // Consume it
        try current_line.appendSlice(allocator, data);
        while (true) {
            switch (request_state.state) {
                .Init => {
                    const parsing_result = try requestLine.parse(
                        allocator,
                        current_line.items[consumed..],
                    );
                    if (parsing_result == .complete) {
                        consumed += parsing_result.complete.bytes_consumed;
                        request.request_line = parsing_result.complete.request_line;
                        request_state.next();
                    } else {
                        break;
                    }
                },
                .Headers => {
                    const parsing_result = try headers.parse(
                        &request.request_headers,
                        current_line.items[consumed..],
                        allocator,
                    );
                    if (parsing_result == .complete) {
                        consumed += parsing_result.complete.bytes_consumed;
                        request_state.next();
                    } else {
                        if (parsing_result == .incomplete) {
                            consumed += parsing_result.incomplete.bytes_consumed;
                        }
                        break;
                    }
                },
                .BodyInit => {
                    const content_length = request.request_headers.getInt("Content-Length") catch null orelse {
                        return request;
                    };
                    try request.request_body.ensureTotalCapacity(allocator, @intCast(content_length));
                    request_state.next();
                },
                .Body => {
                    const content_length: usize = @intCast(request.request_headers.getInt("Content-Length") catch null orelse {
                        return request;
                    });

                    if (request.request_body.items.len == content_length) {
                        return request;
                    }

                    const bytes_needed = content_length - request.request_body.items.len;
                    const available = current_line.items.len - consumed;
                    const to_read = @min(bytes_needed, available);

                    try request.request_body.appendSlice(allocator, current_line.items[consumed..][0..to_read]);
                    consumed += to_read;

                    if (request.request_body.items.len == content_length) {
                        return request;
                    }
                    break;
                },
                .Done => {
                    return request;
                },
            }
        }
    }
    return request;
}
