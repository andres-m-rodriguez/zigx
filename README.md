# Zigx

> **Warning**: This is an experimental toy project. Do not use in production.....like at all!

Zigx is a proof-of-concept full-stack web framework written in Zig. It explores the idea of single-file `.zigx` components that compile to server-side Zig code with plans for client-side WebAssembly.

## Status

**Experimental** - This project exists for learning and exploration. Expect breaking changes, incomplete features, and rough edges.

## Quick Start

```zig
const std = @import("std");
const zigx = @import("zigx.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try zigx.App.init(allocator, 8080);
    defer app.deinit(allocator);

    // Register .zigx pages automatically
    app.addZigxPages();

    // Or add manual routes
    app.get("/api/hello", helloHandler);

    try app.listen();
}

fn helloHandler(ctx: *zigx.RequestContext) !zigx.Response {
    return zigx.Response.json(
        \\{"message": "Hello, World!"}
    );
}
```

## The `.zigx` Format

Zigx uses a custom single-file component format that combines HTML templates with server-side Zig code.

### Basic Page

```zigx
@route("/")

<h1>@{getTitle()}</h1>
<p>Welcome to @{getFrameworkName()}!</p>
<p>Hello, @user_name!</p>

<a href="/about">About</a>

@server{
    const std = @import("std");
    var user_name: []const u8 = undefined;

    pub fn init() !void {
        user_name = "World";
    }

    pub fn getTitle() []const u8 {
        return "Home";
    }

    pub fn getFrameworkName() []const u8 {
        return "Zigx Framework";
    }
}
```

### Route Parameters

Routes support typed parameters that are automatically parsed:

```zigx
@route("/counter/:initial:int")

<h1>Counter</h1>
<p>Value: @counter</p>

@server{
    const std = @import("std");
    var counter: usize = 0;

    pub fn init(ctx: *const PageContext) !void {
        if (ctx.getParam("initial")) |initial_str| {
            counter = std.fmt.parseInt(usize, initial_str, 10) catch 0;
        }
    }
}
```

### API Routes

Pages can define additional API endpoints using the `routes()` function:

```zigx
@route("/users")

<h1>Users</h1>
<div id="users-list">Loading...</div>

<script>
    fetch('/api/users')
        .then(res => res.json())
        .then(data => {
            const list = document.getElementById('users-list');
            list.innerHTML = data.users.map(u =>
                `<div>${u.name} - ${u.email}</div>`
            ).join('');
        });
</script>

@server{
    pub fn routes(app: *app_mod.App) void {
        app.get("/api/users", getUsers);
        app.post("/api/users", createUser);
    }

    fn getUsers(_: *RequestContext) !Response {
        return Response.json(
            \\{"users": [
            \\  {"id": 1, "name": "Alice", "email": "alice@example.com"},
            \\  {"id": 2, "name": "Bob", "email": "bob@example.com"}
            \\]}
        );
    }

    fn createUser(ctx: *RequestContext) !Response {
        // Access request body, headers, etc.
        _ = ctx;
        return Response.json(
            \\{"status": "created", "id": 3}
        ).withStatus(.created);
    }
}
```

### Control Flow (Planned) - SSR section 

Template loops for rendering lists with SSR:

```zigx
@route("/users")

<h1>Users (@{users.len} total)</h1>

<ul class="user-list">
    @for(users) |user| {
        <li class="user-card">
            <img src="@{user.avatar}" alt="@{user.name}" />
            <div class="user-info">
                <h3>@{user.name}</h3>
                <p>@{user.email}</p>
                @if(user.is_admin) {
                    <span class="badge">Admin</span>
                }
            </div>
        </li>
    }
</ul>

@if(users.len == 0) {
    <p class="empty-state">No users found.</p>
}

@server{
    const std = @import("std");

    pub const User = struct {
        id: usize,
        name: []const u8,
        email: []const u8,
        avatar: []const u8,
        is_admin: bool,
    };

    var users: []const User = &.{};

    pub fn init(ctx: *const PageContext) !void {
        // In real app, fetch from database
        users = &.{
            .{ .id = 1, .name = "Alice", .email = "alice@example.com", .avatar = "/avatars/1.png", .is_admin = true },
            .{ .id = 2, .name = "Bob", .email = "bob@example.com", .avatar = "/avatars/2.png", .is_admin = false },
            .{ .id = 3, .name = "Charlie", .email = "charlie@example.com", .avatar = "/avatars/3.png", .is_admin = false },
        };
        _ = ctx;
    }
}
```

This would generate HTML like:

```html
<h1>Users (3 total)</h1>

<ul class="user-list">
    <li class="user-card">
        <img src="/avatars/1.png" alt="Alice" />
        <div class="user-info">
            <h3>Alice</h3>
            <p>alice@example.com</p>
            <span class="badge">Admin</span>
        </div>
    </li>
    <li class="user-card">
        <img src="/avatars/2.png" alt="Bob" />
        <div class="user-info">
            <h3>Bob</h3>
            <p>bob@example.com</p>
        </div>
    </li>
    <!-- ... -->
</ul>
```

## Features

### HTTP Server

| Feature | Description |
|---------|-------------|
| Routing | `app.get()`, `app.post()`, `app.put()`, `app.delete()`, `app.patch()` |
| Route params | `/users/:id:int`, `/posts/:slug:str`, `/items/:uuid:guid` |
| JSON responses | `Response.json(...)` or `Response.fmtJson(allocator, struct)` |
| HTML responses | `Response.html(...)` or `Response.fmtHtml(allocator, template, args)` |
| Status codes | `.withStatus(.created)`, `.withStatus(.not_found)`, etc. |
| Request context | Access to params, headers, body via `RequestContext` |

### `.zigx` Compilation

| Feature | Description |
|---------|-------------|
| Route directive | `@route("/path")` defines the page URL |
| Expressions | `@{expression}` or `@variable` for dynamic content |
| Server block | `@server{...}` contains Zig code for SSR |
| Init function | `pub fn init()` or `pub fn init(ctx: *const PageContext)` |
| Custom routes | `pub fn routes(app: *App)` to register API endpoints |
| Auto-registration | `app.addZigxPages()` registers all `.zigx` files |

### Response Examples

```zig
// Static JSON
Response.json(\\{"status": "ok"})

// Dynamic JSON from struct
Response.fmtJson(allocator, .{
    .name = "User",
    .id = 42,
})

// Static HTML
Response.html("<h1>Hello</h1>")

// Templated HTML
Response.fmtHtml(allocator, "<h1>Hello, {s}!</h1>", .{"World"})

// With status code
Response.json(\\{"error": "not found"}).withStatus(.not_found)
```

## Project Structure

```
Zigx/
├── src/
│   ├── main.zig              # Entry point
│   ├── zigx.zig              # Public API exports
│   ├── Framework/
│   │   ├── Compiler/         # .zigx lexer and parser
│   │   └── Http/             # Server, router, request/response
│   └── App/
│       └── Pages/            # Your .zigx pages go here
│           ├── Home.zigx
│           ├── About.zigx
│           └── ...
├── build/
│   ├── gen_zigx.zig          # Code generator
│   └── codegen/              # Code generation modules
└── src/gen/                  # Auto-generated (gitignored)
    ├── routes.zig            # Route registry
    └── server/               # Generated handlers
```

## Current State

**What's working:**

- HTTP/1.1 server with multi-threaded connection handling
- Trie-based router with typed parameters
- `.zigx` file parsing and lexing
- Server-side code generation from `.zigx` files
- Expression interpolation with comptime type detection
- JSON and HTML response builders
- Route registration via `@server{ pub fn routes(...) }`
- Page initialization with `init()` / `init(ctx)`

**What's not built yet:**

- Client-side WASM compilation (`@client{}` blocks)
- Reactive data binding (`@bind`)
- Event handlers (`@onclick`)
- Template control flow (`@for`, `@if`)
- Client-server hydration

## Goals

1. Learn Zig deeply through a non-trivial project
2. Explore comptime capabilities for code generation
3. Experiment with Zig's WASM compilation target
4. Build something fun

## Non-Goals

- Production readiness
- Performance benchmarks
- Comprehensive HTTP compliance
- Competing with established frameworks

## License

MIT
