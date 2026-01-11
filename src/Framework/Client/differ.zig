// Differ - Compares RenderTrees and produces patches for DOM updates
// Uses O(n) sequence-based diffing similar to Blazor

const std = @import("std");
const render_tree = @import("render_tree");

const RenderTree = render_tree.RenderTree;
const RenderFrame = render_tree.RenderFrame;
const FrameType = render_tree.FrameType;

/// Types of patches that can be applied to the DOM
pub const PatchType = enum(u8) {
    /// Create a new element
    create_element,
    /// Create a new text node
    create_text,
    /// Remove an element from the DOM
    remove_element,
    /// Update text content of a text node
    update_text,
    /// Set an attribute on an element
    set_attribute,
    /// Remove an attribute from an element
    remove_attribute,
    /// Attach an event listener
    attach_event,
    /// Detach an event listener
    detach_event,
};

/// Data for create_element patch
pub const CreateElementData = struct {
    tag: []const u8,
    /// Sequence number for handle assignment
    sequence: u32,
};

/// Data for create_text patch
pub const CreateTextData = struct {
    content: []const u8,
    sequence: u32,
};

/// Data for text update patch
pub const TextData = struct {
    content: []const u8,
};

/// Data for attribute patch
pub const AttributeData = struct {
    name: []const u8,
    value: []const u8,
};

/// Data for event patch
pub const EventData = struct {
    name: []const u8,
    handler_id: u32,
};

/// Tagged union for patch-specific data
pub const PatchData = union(PatchType) {
    create_element: CreateElementData,
    create_text: CreateTextData,
    remove_element: void,
    update_text: TextData,
    set_attribute: AttributeData,
    remove_attribute: struct { name: []const u8 },
    attach_event: EventData,
    detach_event: EventData,
};

/// A single patch to apply to the DOM
pub const Patch = struct {
    /// Type of patch operation
    patch_type: PatchType,
    /// Handle of the target element (0 for new elements)
    target_handle: u32,
    /// Handle of the parent element (for insertions)
    parent_handle: u32,
    /// Handle of the reference element (insert before this, 0 = append)
    ref_handle: u32,
    /// Patch-specific data
    data: PatchData,
};

/// Result of the diff operation
pub const DiffResult = struct {
    patches: []Patch,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiffResult) void {
        self.allocator.free(self.patches);
    }
};

/// Handle mapping from sequence numbers to DOM handles
/// Used to track which elements exist in the current DOM
pub const HandleMap = struct {
    map: std.AutoHashMapUnmanaged(u32, u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HandleMap {
        return .{
            .map = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HandleMap) void {
        self.map.deinit(self.allocator);
    }

    pub fn put(self: *HandleMap, sequence: u32, handle: u32) !void {
        try self.map.put(self.allocator, sequence, handle);
    }

    pub fn get(self: *HandleMap, sequence: u32) ?u32 {
        return self.map.get(sequence);
    }

    pub fn remove(self: *HandleMap, sequence: u32) void {
        _ = self.map.remove(sequence);
    }

    pub fn contains(self: *HandleMap, sequence: u32) bool {
        return self.map.contains(sequence);
    }
};

/// Diff two render trees and produce patches
pub fn diff(
    allocator: std.mem.Allocator,
    old_tree: ?RenderTree,
    new_tree: RenderTree,
    handle_map: *HandleMap,
    root_handle: u32,
) !DiffResult {
    var patches = std.ArrayList(Patch){};
    errdefer patches.deinit(allocator);

    // Build a set of sequences present in old tree
    var old_sequences: std.AutoHashMapUnmanaged(u32, usize) = .{};
    defer old_sequences.deinit(allocator);

    if (old_tree) |old| {
        for (old.frames, 0..) |frame, idx| {
            try old_sequences.put(allocator, frame.sequence, idx);
        }
    }

    // Build a set of sequences present in new tree
    var new_sequences: std.AutoHashMapUnmanaged(u32, usize) = .{};
    defer new_sequences.deinit(allocator);

    for (new_tree.frames, 0..) |frame, idx| {
        try new_sequences.put(allocator, frame.sequence, idx);
    }

    // Track parent stack for insertions
    var parent_stack = std.ArrayList(u32){};
    defer parent_stack.deinit(allocator);
    try parent_stack.append(allocator, root_handle);

    // First pass: Process new tree, generate create/update patches
    var new_idx: usize = 0;
    while (new_idx < new_tree.frames.len) {
        const new_frame = new_tree.frames[new_idx];
        const old_idx = old_sequences.get(new_frame.sequence);

        const current_parent = if (parent_stack.items.len > 0)
            parent_stack.items[parent_stack.items.len - 1]
        else
            root_handle;

        if (old_idx) |oi| {
            // Sequence exists in both - check if content changed
            const old_frame = if (old_tree) |old| old.frames[oi] else unreachable;

            switch (new_frame.frame_type) {
                .element => {
                    // Element exists, push to parent stack
                    const handle = handle_map.get(new_frame.sequence) orelse 0;
                    try parent_stack.append(allocator, handle);
                },
                .text => {
                    // Check if text content changed
                    if (!std.mem.eql(u8, new_frame.data.text.content, old_frame.data.text.content)) {
                        const handle = handle_map.get(new_frame.sequence) orelse 0;
                        try patches.append(allocator, .{
                            .patch_type = .update_text,
                            .target_handle = handle,
                            .parent_handle = current_parent,
                            .ref_handle = 0,
                            .data = .{ .update_text = .{ .content = new_frame.data.text.content } },
                        });
                    }
                },
                .attribute => {
                    // Check if attribute value changed
                    if (!std.mem.eql(u8, new_frame.data.attribute.value, old_frame.data.attribute.value)) {
                        const parent_seq = getParentSequence(new_tree.frames, new_idx);
                        const handle = if (parent_seq) |ps| handle_map.get(ps) orelse 0 else current_parent;
                        try patches.append(allocator, .{
                            .patch_type = .set_attribute,
                            .target_handle = handle,
                            .parent_handle = 0,
                            .ref_handle = 0,
                            .data = .{ .set_attribute = .{
                                .name = new_frame.data.attribute.name,
                                .value = new_frame.data.attribute.value,
                            } },
                        });
                    }
                },
                .event => {
                    // Events don't change, but if handler ID changed, rebind
                    if (new_frame.data.event.handler_id != old_frame.data.event.handler_id) {
                        const parent_seq = getParentSequence(new_tree.frames, new_idx);
                        const handle = if (parent_seq) |ps| handle_map.get(ps) orelse 0 else current_parent;
                        // Detach old
                        try patches.append(allocator, .{
                            .patch_type = .detach_event,
                            .target_handle = handle,
                            .parent_handle = 0,
                            .ref_handle = 0,
                            .data = .{ .detach_event = .{
                                .name = old_frame.data.event.name,
                                .handler_id = old_frame.data.event.handler_id,
                            } },
                        });
                        // Attach new
                        try patches.append(allocator, .{
                            .patch_type = .attach_event,
                            .target_handle = handle,
                            .parent_handle = 0,
                            .ref_handle = 0,
                            .data = .{ .attach_event = .{
                                .name = new_frame.data.event.name,
                                .handler_id = new_frame.data.event.handler_id,
                            } },
                        });
                    }
                },
                .region => {
                    // Pop from parent stack
                    if (parent_stack.items.len > 1) {
                        _ = parent_stack.pop();
                    }
                },
            }
        } else {
            // Sequence is new - need to create
            switch (new_frame.frame_type) {
                .element => {
                    try patches.append(allocator, .{
                        .patch_type = .create_element,
                        .target_handle = 0,
                        .parent_handle = current_parent,
                        .ref_handle = 0,
                        .data = .{ .create_element = .{
                            .tag = new_frame.data.element.tag,
                            .sequence = new_frame.sequence,
                        } },
                    });
                    // Will get handle after patch is applied
                    // For now, push a placeholder (0)
                    try parent_stack.append(allocator, 0);
                },
                .text => {
                    try patches.append(allocator, .{
                        .patch_type = .create_text,
                        .target_handle = 0,
                        .parent_handle = current_parent,
                        .ref_handle = 0,
                        .data = .{ .create_text = .{
                            .content = new_frame.data.text.content,
                            .sequence = new_frame.sequence,
                        } },
                    });
                },
                .attribute => {
                    const parent_seq = getParentSequence(new_tree.frames, new_idx);
                    const handle = if (parent_seq) |ps| handle_map.get(ps) orelse current_parent else current_parent;
                    try patches.append(allocator, .{
                        .patch_type = .set_attribute,
                        .target_handle = handle,
                        .parent_handle = 0,
                        .ref_handle = 0,
                        .data = .{ .set_attribute = .{
                            .name = new_frame.data.attribute.name,
                            .value = new_frame.data.attribute.value,
                        } },
                    });
                },
                .event => {
                    const parent_seq = getParentSequence(new_tree.frames, new_idx);
                    const handle = if (parent_seq) |ps| handle_map.get(ps) orelse current_parent else current_parent;
                    try patches.append(allocator, .{
                        .patch_type = .attach_event,
                        .target_handle = handle,
                        .parent_handle = 0,
                        .ref_handle = 0,
                        .data = .{ .attach_event = .{
                            .name = new_frame.data.event.name,
                            .handler_id = new_frame.data.event.handler_id,
                        } },
                    });
                },
                .region => {
                    if (parent_stack.items.len > 1) {
                        _ = parent_stack.pop();
                    }
                },
            }
        }

        new_idx += 1;
    }

    // Second pass: Find removed elements (in old but not in new)
    if (old_tree) |old| {
        for (old.frames) |old_frame| {
            if (!new_sequences.contains(old_frame.sequence)) {
                // This sequence was removed
                switch (old_frame.frame_type) {
                    .element, .text => {
                        const handle = handle_map.get(old_frame.sequence) orelse continue;
                        try patches.append(allocator, .{
                            .patch_type = .remove_element,
                            .target_handle = handle,
                            .parent_handle = 0,
                            .ref_handle = 0,
                            .data = .{ .remove_element = {} },
                        });
                        handle_map.remove(old_frame.sequence);
                    },
                    .attribute => {
                        // Attribute removed
                        const parent_seq = getParentSequenceFromOld(old.frames, old_frame.sequence);
                        if (parent_seq) |ps| {
                            const handle = handle_map.get(ps) orelse continue;
                            try patches.append(allocator, .{
                                .patch_type = .remove_attribute,
                                .target_handle = handle,
                                .parent_handle = 0,
                                .ref_handle = 0,
                                .data = .{ .remove_attribute = .{ .name = old_frame.data.attribute.name } },
                            });
                        }
                    },
                    .event => {
                        // Event removed
                        const parent_seq = getParentSequenceFromOld(old.frames, old_frame.sequence);
                        if (parent_seq) |ps| {
                            const handle = handle_map.get(ps) orelse continue;
                            try patches.append(allocator, .{
                                .patch_type = .detach_event,
                                .target_handle = handle,
                                .parent_handle = 0,
                                .ref_handle = 0,
                                .data = .{ .detach_event = .{
                                    .name = old_frame.data.event.name,
                                    .handler_id = old_frame.data.event.handler_id,
                                } },
                            });
                        }
                    },
                    .region => {},
                }
            }
        }
    }

    return .{
        .patches = try patches.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Find the sequence number of the parent element for a frame at given index
fn getParentSequence(frames: []const RenderFrame, idx: usize) ?u32 {
    var depth: i32 = 0;
    var i = idx;

    while (i > 0) {
        i -= 1;
        const frame = frames[i];
        switch (frame.frame_type) {
            .region => depth += 1,
            .element => {
                if (depth == 0) {
                    return frame.sequence;
                }
                depth -= 1;
            },
            else => {},
        }
    }

    return null;
}

/// Find parent sequence from old frames by searching backwards
fn getParentSequenceFromOld(frames: []const RenderFrame, target_sequence: u32) ?u32 {
    // Find the target frame first
    var target_idx: ?usize = null;
    for (frames, 0..) |frame, idx| {
        if (frame.sequence == target_sequence) {
            target_idx = idx;
            break;
        }
    }

    if (target_idx) |idx| {
        return getParentSequence(frames, idx);
    }

    return null;
}

// ============================================
// Tests
// ============================================

test "diff empty to single element" {
    const allocator = std.testing.allocator;

    var builder = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder.openElement(0, "div");
    try builder.addText(1, "Hello");
    try builder.closeElement();
    var new_tree = try builder.build();
    defer new_tree.deinit();

    var handle_map = HandleMap.init(allocator);
    defer handle_map.deinit();

    var result = try diff(allocator, null, new_tree, &handle_map, 1);
    defer result.deinit();

    // Should have create_element and create_text patches
    try std.testing.expect(result.patches.len >= 2);
    try std.testing.expectEqual(PatchType.create_element, result.patches[0].patch_type);
    try std.testing.expectEqual(PatchType.create_text, result.patches[1].patch_type);

    builder.deinit();
}

test "diff same trees no patches" {
    const allocator = std.testing.allocator;

    var builder1 = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder1.openElement(0, "div");
    try builder1.addText(1, "Hello");
    try builder1.closeElement();
    var tree1 = try builder1.build();
    defer tree1.deinit();

    var builder2 = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder2.openElement(0, "div");
    try builder2.addText(1, "Hello");
    try builder2.closeElement();
    var tree2 = try builder2.build();
    defer tree2.deinit();

    var handle_map = HandleMap.init(allocator);
    defer handle_map.deinit();
    try handle_map.put(0, 10);
    try handle_map.put(1, 11);

    var result = try diff(allocator, tree1, tree2, &handle_map, 1);
    defer result.deinit();

    // Same content, no patches needed
    try std.testing.expectEqual(@as(usize, 0), result.patches.len);

    builder1.deinit();
    builder2.deinit();
}

test "diff text content change" {
    const allocator = std.testing.allocator;

    var builder1 = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder1.openElement(0, "div");
    try builder1.addText(1, "Hello");
    try builder1.closeElement();
    var tree1 = try builder1.build();
    defer tree1.deinit();

    var builder2 = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder2.openElement(0, "div");
    try builder2.addText(1, "World");
    try builder2.closeElement();
    var tree2 = try builder2.build();
    defer tree2.deinit();

    var handle_map = HandleMap.init(allocator);
    defer handle_map.deinit();
    try handle_map.put(0, 10);
    try handle_map.put(1, 11);

    var result = try diff(allocator, tree1, tree2, &handle_map, 1);
    defer result.deinit();

    // Should have update_text patch
    try std.testing.expectEqual(@as(usize, 1), result.patches.len);
    try std.testing.expectEqual(PatchType.update_text, result.patches[0].patch_type);

    builder1.deinit();
    builder2.deinit();
}

test "diff element removed" {
    const allocator = std.testing.allocator;

    var builder1 = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder1.openElement(0, "div");
    try builder1.addText(1, "Hello");
    _ = try builder1.openElement(2, "span");
    try builder1.addText(3, "World");
    try builder1.closeElement();
    try builder1.closeElement();
    var tree1 = try builder1.build();
    defer tree1.deinit();

    var builder2 = render_tree.RenderTreeBuilder.init(allocator);
    _ = try builder2.openElement(0, "div");
    try builder2.addText(1, "Hello");
    try builder2.closeElement();
    var tree2 = try builder2.build();
    defer tree2.deinit();

    var handle_map = HandleMap.init(allocator);
    defer handle_map.deinit();
    try handle_map.put(0, 10);
    try handle_map.put(1, 11);
    try handle_map.put(2, 12);
    try handle_map.put(3, 13);

    var result = try diff(allocator, tree1, tree2, &handle_map, 1);
    defer result.deinit();

    // Should have remove_element patches for span and its text
    var remove_count: usize = 0;
    for (result.patches) |patch| {
        if (patch.patch_type == .remove_element) {
            remove_count += 1;
        }
    }
    try std.testing.expect(remove_count >= 2);

    builder1.deinit();
    builder2.deinit();
}
