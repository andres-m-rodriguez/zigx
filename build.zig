const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("Zigx", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Create the zigxParser module first so it can be shared
    const zigx_compiler_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Compiler/zigxParser.zig"),
        .target = b.graph.host,
    });

    // Create the render_tree module (shared between server and client)
    // Host version for code generation
    const render_tree_host_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Shared/render_tree.zig"),
        .target = b.graph.host,
    });

    // Native version for the server executable
    const render_tree_native_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Shared/render_tree.zig"),
        .target = target,
    });

    // Create the zig server parser module (for parsing zig code to find imports)
    const zig_server_parser_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Compiler/server/parser.zig"),
        .target = b.graph.host,
    });

    // Create codegen modules with zigxParser dependency
    const codegen_placeholders = b.createModule(.{
        .root_source_file = b.path("build/codegen/placeholders.zig"),
        .target = b.graph.host,
    });

    const codegen_common = b.createModule(.{
        .root_source_file = b.path("build/codegen/common.zig"),
        .target = b.graph.host,
        .imports = &.{
            .{ .name = "placeholders", .module = codegen_placeholders },
        },
    });

    const codegen_server = b.createModule(.{
        .root_source_file = b.path("build/codegen/server.zig"),
        .target = b.graph.host,
        .imports = &.{
            .{ .name = "common", .module = codegen_common },
            .{ .name = "zigxParser", .module = zigx_compiler_mod },
            .{ .name = "zigServerParser", .module = zig_server_parser_mod },
            .{ .name = "render_tree", .module = render_tree_host_mod },
        },
    });

    const codegen_client = b.createModule(.{
        .root_source_file = b.path("build/codegen/client.zig"),
        .target = b.graph.host,
        .imports = &.{
            .{ .name = "common", .module = codegen_common },
            .{ .name = "zigxParser", .module = zigx_compiler_mod },
            .{ .name = "render_tree", .module = render_tree_host_mod },
        },
    });

    const codegen_routes = b.createModule(.{
        .root_source_file = b.path("build/codegen/routes.zig"),
        .target = b.graph.host,
        .imports = &.{
            .{ .name = "common", .module = codegen_common },
            .{ .name = "zigxParser", .module = zigx_compiler_mod },
        },
    });

    const zigx_generator = b.addExecutable(.{
        .name = "zigx_generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/gen_zigx.zig"),
            .target = b.graph.host,
            .imports = &.{
                .{ .name = "zigxParser", .module = zigx_compiler_mod },
                .{ .name = "codegen/server.zig", .module = codegen_server },
                .{ .name = "codegen/client.zig", .module = codegen_client },
                .{ .name = "codegen/routes.zig", .module = codegen_routes },
            },
        }),
    });

    // Run the generator - outputs to src/gen/ (gitignored)
    // Creates: src/gen/routes.zig, src/gen/server/*.zig, src/gen/client/*.zig
    const zigx_files_scanner = b.addRunArtifact(zigx_generator);
    zigx_files_scanner.addArg("src/gen/routes.zig");

    // ============================================
    // WASM Client Compilation
    // ============================================

    // WASM target for client-side code
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Create the render_tree module for WASM target
    const render_tree_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Shared/render_tree.zig"),
        .target = wasm_target,
    });

    // Create the differ module for WASM target (depends on render_tree)
    const differ_wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Client/differ.zig"),
        .target = wasm_target,
        .imports = &.{
            .{ .name = "render_tree", .module = render_tree_wasm_mod },
        },
    });

    // Create the client runtime module for WASM
    const client_runtime_mod = b.createModule(.{
        .root_source_file = b.path("src/Framework/Client/runtime.zig"),
        .target = wasm_target,
    });

    // Build MyCounter WASM (MVP: hardcoded, later: scan src/gen/client/)
    const client_wasm = b.addExecutable(.{
        .name = "MyCounter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen/client/MyCounter.zig"),
            .target = wasm_target,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "runtime", .module = client_runtime_mod },
                .{ .name = "render_tree", .module = render_tree_wasm_mod },
                .{ .name = "differ", .module = differ_wasm_mod },
            },
        }),
    });
    // WASM library - no entry point needed
    client_wasm.entry = .disabled;
    // WASM needs to export memory
    client_wasm.export_memory = true;
    // Force dynamic exports to be retained
    client_wasm.rdynamic = true;

    // Make WASM depend on generator
    client_wasm.step.dependOn(&zigx_files_scanner.step);

    // Install WASM to src/gen/wasm/ so it can be @embedFile'd by the server
    const install_wasm = b.addInstallArtifact(client_wasm, .{
        .dest_dir = .{ .override = .{ .custom = "../src/gen/wasm" } },
    });
    install_wasm.step.dependOn(&client_wasm.step);

    // Create a step to build all WASM files
    const wasm_step = b.step("wasm", "Build WASM client modules");
    wasm_step.dependOn(&client_wasm.step);

    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "Zigx",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "Zigx" is the name you will use in your source code to
                // import this module (e.g. `@import("Zigx")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "Zigx", .module = mod },
                // render_tree is used by generated server code
                .{ .name = "render_tree", .module = render_tree_native_mod },
            },
        }),
    });
    // Ensure generator runs before compilation
    exe.step.dependOn(&zigx_files_scanner.step);
    // Also build and install WASM clients before the server (so @embedFile works)
    exe.step.dependOn(&install_wasm.step);
    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.step.dependOn(&zigx_files_scanner.step);

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.step.dependOn(&zigx_files_scanner.step);

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Make the default build step depend on tests passing first
    b.getInstallStep().dependOn(&run_mod_tests.step);
    b.getInstallStep().dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
