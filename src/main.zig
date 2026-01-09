const std = @import("std");
const zigx = @import("zigx.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigx.App.init(allocator, 42069);
    defer app.deinit(allocator);

    app.get("/", indexHandler);
    app.get("/users", usersHandler);
    app.post("/users", createUserHandler);
    app.get("/error", errorHandler);
    app.get("/users/id:int", usersByIdHandler);

    try app.listen();
}

fn indexHandler(ctx: *zigx.RequestContext) !zigx.Response {
    return zigx.Response.fmtHtml(ctx.allocator, @embedFile("index.html"), .{"Andres"});
}
fn usersByIdHandler(ctx: *zigx.RequestContext) !zigx.Response {
    const id = try ctx.params.get("id").?.asInt();
    return try zigx.Response.fmtJson(ctx.allocator, .{
        .name = "User",
        .id = id,
    });
}

fn usersHandler(_: *zigx.RequestContext) !zigx.Response {
    return zigx.Response.json(
        \\{"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}
    );
}

fn createUserHandler(_: *zigx.RequestContext) !zigx.Response {
    return zigx.Response.json(
        \\{"status": "created", "id": 3}
    ).withStatus(.created);
}

fn errorHandler(_: *zigx.RequestContext) !zigx.Response {
    return zigx.Response.html(
        \\<html>
        \\  <head><title>500 Error</title></head>
        \\  <body>
        \\    <h1>Internal Server Error</h1>
        \\    <p>Okay, you know what? This one is on me.</p>
        \\  </body>
        \\</html>
    ).withStatus(.internal_server_error);
}
