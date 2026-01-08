# Zigx

> **Warning**: This is an experimental toy project. Do not use in production.

Zigx is a proof-of-concept full-stack web framework written in Zig. It explores the idea of single-file components that compile to both server-side Zig and client-side WebAssembly.

## Status

**Experimental** - This project exists for learning and exploration. Expect breaking changes, incomplete features, and rough edges.

## Vision

Zigx aims to provide a unified development experience where a single `.zigx` file contains:

- HTML templates with reactive bindings
- Client-side logic that compiles to WASM
- Server-side logic for data loading and SSR

### Example Component

```zigx
<div class="todo-app">
    <h1>Todos (@todos.items.len remaining)</h1>

    <input @bind="new_todo_text" placeholder="What needs to be done?" />
    <button @onclick="addTodo">Add</button>

    <ul>
        @for (todos.items) |todo| {
            <li class="@if (todo.completed) 'done' else ''">
                <input type="checkbox"
                       checked="@todo.completed"
                       @onclick="toggleTodo(todo.id)" />
                <span>@todo.text</span>
                <button @onclick="deleteTodo(todo.id)">x</button>
            </li>
        }
    </ul>

    <p>Loaded @initial_count todos from database</p>
</div>

@server {
    const db = @import("db.zig");

    pub const Todo = struct {
        id: usize,
        text: []const u8,
        completed: bool,
    };

    // Runs on page load - fetches initial data for SSR
    pub fn load(allocator: Allocator) ![]Todo {
        return try db.query(allocator, "SELECT * FROM todos WHERE user_id = ?", .{ctx.user.id});
    }
}

@client {
    // State - initialized from @server.load() result
    todos: std.ArrayList(Todo),
    new_todo_text: []const u8 = "",
    initial_count: usize,

    pub fn init(server_data: []Todo) void {
        initial_count = server_data.len;
        todos = std.ArrayList(Todo).fromSlice(allocator, server_data);
    }

    pub fn addTodo() !void {
        if (new_todo_text.len == 0) return;

        const todo = Todo{
            .id = generateId(),
            .text = new_todo_text,
            .completed = false,
        };
        try todos.append(todo);
        new_todo_text = "";

        // Sync to server
        try @fetch("/api/todos", .{ .method = .POST, .body = todo });
    }

    pub fn toggleTodo(id: usize) void {
        for (todos.items) |*todo| {
            if (todo.id == id) {
                todo.completed = !todo.completed;
                break;
            }
        }
    }

    pub fn deleteTodo(id: usize) void {
        todos.items = filter(todos.items, |t| t.id != id);
        try @fetch("/api/todos/" ++ id, .{ .method = .DELETE });
    }
}
```

This example demonstrates:

| Feature | How it's used |
|---------|---------------|
| Server data loading | `@server.load()` fetches todos from database |
| SSR | Initial HTML rendered with todo list on server |
| Hydration | `@client.init()` receives server data when WASM loads |
| Reactive state | `todos`, `new_todo_text` trigger re-renders on change |
| Event binding | `@onclick`, `@bind` connect DOM to WASM handlers |
| Control flow | `@for`, `@if` in templates |
| Server sync | `@fetch` calls back to server API |

### Expected Output

When compiled, a `.zigx` file produces:

| Output | Description |
|--------|-------------|
| Server module | Zig code that handles SSR and data loading |
| Client WASM | WebAssembly binary for browser interactivity |
| Hydration glue | JavaScript to load WASM and bind events |

## Current State

The HTTP server foundation is functional:

- HTTP/1.1 request parsing
- Multi-threaded connection handling
- Route registration (GET, POST, PUT, DELETE, etc.)
- Response generation

What's not built yet:

- `.zigx` file parser
- Template compilation
- WASM code generation
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
