const std = @import("std");
const lexer = @import("lexer.zig");

/// AST Node types for the template
pub const Node = union(enum) {
    /// Raw HTML text
    html: []const u8,
    /// Expression to evaluate: @{expr} or @identifier
    expression: []const u8,
    /// For loop: @for(collection) |item| { body }
    for_loop: ForLoop,
    /// If statement: @if(condition) { body } @else { else_body }
    if_stmt: IfStmt,
    /// While loop: @while(condition) |item| { body }
    while_loop: WhileLoop,

    pub const ForLoop = struct {
        collection: []const u8,
        capture: []const u8,
        body: []const Node,
    };

    pub const IfStmt = struct {
        condition: []const u8,
        then_body: []const Node,
        else_body: ?[]const Node,
    };

    pub const WhileLoop = struct {
        condition: []const u8,
        capture: ?[]const u8,
        body: []const Node,
    };

    /// Free all memory associated with this node
    pub fn deinit(self: Node, allocator: std.mem.Allocator) void {
        switch (self) {
            .html => |text| allocator.free(text),
            .expression => |expr| allocator.free(expr),
            .for_loop => |loop| {
                allocator.free(loop.collection);
                allocator.free(loop.capture);
                for (loop.body) |child| {
                    child.deinit(allocator);
                }
                allocator.free(loop.body);
            },
            .if_stmt => |stmt| {
                allocator.free(stmt.condition);
                for (stmt.then_body) |child| {
                    child.deinit(allocator);
                }
                allocator.free(stmt.then_body);
                if (stmt.else_body) |else_nodes| {
                    for (else_nodes) |child| {
                        child.deinit(allocator);
                    }
                    allocator.free(else_nodes);
                }
            },
            .while_loop => |loop| {
                allocator.free(loop.condition);
                if (loop.capture) |cap| allocator.free(cap);
                for (loop.body) |child| {
                    child.deinit(allocator);
                }
                allocator.free(loop.body);
            },
        }
    }
};

pub const ZigxDocument = struct {
    file_name: []const u8,
    route: []const u8,
    content: []const Node, // AST nodes for the template
    server_code: []const u8,
    client_code: []const u8,

    pub fn deinit(self: *ZigxDocument, allocator: std.mem.Allocator) void {
        allocator.free(self.file_name);
        allocator.free(self.route);
        for (self.content) |node| {
            node.deinit(allocator);
        }
        allocator.free(self.content);
        allocator.free(self.server_code);
        allocator.free(self.client_code);
    }
};

pub fn parse(allocator: std.mem.Allocator, reader: *std.Io.Reader, file_name: []const u8) !ZigxDocument {
    var server_buf = std.ArrayList(u8){};
    errdefer server_buf.deinit(allocator);

    var client_buf = std.ArrayList(u8){};
    errdefer client_buf.deinit(allocator);

    var nodes = std.ArrayList(Node){};
    errdefer {
        for (nodes.items) |node| {
            node.deinit(allocator);
        }
        nodes.deinit(allocator);
    }

    var zigx_lexer = lexer.Lexer.init(reader);
    defer zigx_lexer.deinit(allocator);

    var custom_route: ?[]const u8 = null;
    errdefer if (custom_route) |r| allocator.free(r);

    while (true) {
        const token = try zigx_lexer.next(allocator);

        switch (token.kind) {
            .Eof => break,
            .RouteDirective => {
                if (token.lexeme.len > 0) {
                    custom_route = try allocator.dupe(u8, token.lexeme);
                }
            },
            .HtmlText => {
                if (token.lexeme.len > 0) {
                    const text = try allocator.dupe(u8, token.lexeme);
                    try nodes.append(allocator, Node{ .html = text });
                }
            },
            .ServerBlock => {
                try server_buf.appendSlice(allocator, token.lexeme);
            },
            .ClientBlock => {
                try client_buf.appendSlice(allocator, token.lexeme);
            },
            .Expression, .ExpressionBlock => {
                const expr = try allocator.dupe(u8, token.lexeme);
                try nodes.append(allocator, Node{ .expression = expr });
            },
            .ForBlock => {
                const cf = token.control_flow orelse return error.MissingControlFlowData;
                const node = try parseForLoop(allocator, cf);
                freeControlFlowData(allocator, cf); // Free lexer allocations
                try nodes.append(allocator, node);
            },
            .IfBlock => {
                const cf = token.control_flow orelse return error.MissingControlFlowData;
                const node = try parseIfStmt(allocator, cf);
                freeControlFlowData(allocator, cf);
                try nodes.append(allocator, node);
            },
            .WhileBlock => {
                const cf = token.control_flow orelse return error.MissingControlFlowData;
                const node = try parseWhileLoop(allocator, cf);
                freeControlFlowData(allocator, cf);
                try nodes.append(allocator, node);
            },
        }
    }

    const owned_file_name = try allocator.dupe(u8, file_name);
    errdefer allocator.free(owned_file_name);

    const route = if (custom_route) |r| r else try std.fmt.allocPrint(allocator, "/{s}", .{file_name});
    errdefer if (custom_route == null) allocator.free(route);

    return ZigxDocument{
        .file_name = owned_file_name,
        .route = route,
        .content = try nodes.toOwnedSlice(allocator),
        .server_code = try server_buf.toOwnedSlice(allocator),
        .client_code = try client_buf.toOwnedSlice(allocator),
    };
}

const ParseError = error{
    OutOfMemory,
    MissingControlFlowData,
    MissingCapture,
    UnexpectedEof,
    ExpectedOpenBrace,
    ExpectedPipe,
    UnexpectedToken,
    EndOfStream,
    ReadFailed,
};

/// Free the lexer-allocated control flow data after parser has copied it
fn freeControlFlowData(allocator: std.mem.Allocator, cf: lexer.ControlFlowData) void {
    allocator.free(cf.param);
    if (cf.capture) |cap| allocator.free(cap);
    allocator.free(cf.body);
    if (cf.else_body) |eb| allocator.free(eb);
}

/// Parse the body content of a control flow block into AST nodes
fn parseBody(allocator: std.mem.Allocator, body_content: []const u8) ParseError![]const Node {
    // Create a reader from the body string using .fixed
    var body_reader: std.Io.Reader = .fixed(body_content);

    var body_lexer = lexer.Lexer.init(&body_reader);
    defer body_lexer.deinit(allocator);

    var nodes = std.ArrayList(Node){};
    errdefer {
        for (nodes.items) |node| {
            node.deinit(allocator);
        }
        nodes.deinit(allocator);
    }

    while (true) {
        const token = try body_lexer.next(allocator);

        switch (token.kind) {
            .Eof => break,
            .HtmlText => {
                if (token.lexeme.len > 0) {
                    const text = try allocator.dupe(u8, token.lexeme);
                    try nodes.append(allocator, Node{ .html = text });
                }
            },
            .Expression, .ExpressionBlock => {
                const expr = try allocator.dupe(u8, token.lexeme);
                try nodes.append(allocator, Node{ .expression = expr });
            },
            .ForBlock => {
                const cf = token.control_flow orelse return error.MissingControlFlowData;
                const node = try parseForLoop(allocator, cf);
                freeControlFlowData(allocator, cf);
                try nodes.append(allocator, node);
            },
            .IfBlock => {
                const cf = token.control_flow orelse return error.MissingControlFlowData;
                const node = try parseIfStmt(allocator, cf);
                freeControlFlowData(allocator, cf);
                try nodes.append(allocator, node);
            },
            .WhileBlock => {
                const cf = token.control_flow orelse return error.MissingControlFlowData;
                const node = try parseWhileLoop(allocator, cf);
                freeControlFlowData(allocator, cf);
                try nodes.append(allocator, node);
            },
            // These shouldn't appear inside control flow bodies
            .RouteDirective, .ServerBlock, .ClientBlock => {},
        }
    }

    return try nodes.toOwnedSlice(allocator);
}

fn parseForLoop(allocator: std.mem.Allocator, cf: lexer.ControlFlowData) ParseError!Node {
    const collection = try allocator.dupe(u8, cf.param);
    errdefer allocator.free(collection);

    const capture = try allocator.dupe(u8, cf.capture orelse return error.MissingCapture);
    errdefer allocator.free(capture);

    const body = try parseBody(allocator, cf.body);

    return Node{
        .for_loop = .{
            .collection = collection,
            .capture = capture,
            .body = body,
        },
    };
}

fn parseIfStmt(allocator: std.mem.Allocator, cf: lexer.ControlFlowData) ParseError!Node {
    const condition = try allocator.dupe(u8, cf.param);
    errdefer allocator.free(condition);

    const then_body = try parseBody(allocator, cf.body);
    errdefer {
        for (then_body) |node| {
            node.deinit(allocator);
        }
        allocator.free(then_body);
    }

    var else_body: ?[]const Node = null;
    if (cf.else_body) |else_content| {
        else_body = try parseBody(allocator, else_content);
    }

    return Node{
        .if_stmt = .{
            .condition = condition,
            .then_body = then_body,
            .else_body = else_body,
        },
    };
}

fn parseWhileLoop(allocator: std.mem.Allocator, cf: lexer.ControlFlowData) ParseError!Node {
    const condition = try allocator.dupe(u8, cf.param);
    errdefer allocator.free(condition);

    var capture: ?[]const u8 = null;
    if (cf.capture) |cap| {
        capture = try allocator.dupe(u8, cap);
    }
    errdefer if (capture) |cap| allocator.free(cap);

    const body = try parseBody(allocator, cf.body);

    return Node{
        .while_loop = .{
            .condition = condition,
            .capture = capture,
            .body = body,
        },
    };
}
