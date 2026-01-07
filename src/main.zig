const std = @import("std");
const App = @import("Http/Server/app.zig").App;
const RequestContext = @import("Http/Server/app.zig").RequestContext;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try App.init(allocator, 42069);
    defer app.deinit();

    // Register routes
    app.get("/", indexHandler);
    app.get("/users", usersHandler);
    app.post("/users", createUserHandler);
    app.get("/error", errorHandler);

    try app.listen();
}

fn indexHandler(ctx: *RequestContext) !void {
    try ctx.html(
        \\<html>
        \\  <head><title>Home</title></head>
        \\  <body>
        \\    <h1>Welcome!</h1>
        \\    <p>Your request was an absolute banger.</p>
        \\  </body>
        \\</html>
    );
}

fn usersHandler(ctx: *RequestContext) !void {
    try ctx.json(
        \\{"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}
    );
}

fn createUserHandler(ctx: *RequestContext) !void {
    _ = ctx.req.request_body.items; // Access POST body if needed
    try ctx.json(
        \\{"status": "created", "id": 3}
    );
}

fn errorHandler(ctx: *RequestContext) !void {
    try ctx.sendResponse(.StatusInternalServerError, "text/html",
        \\<html>
        \\  <head><title>500 Error</title></head>
        \\  <body>
        \\    <h1>Internal Server Error</h1>
        \\    <p>Okay, you know what? This one is on me.</p>
        \\  </body>
        \\</html>
    );
}
