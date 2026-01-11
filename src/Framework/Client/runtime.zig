extern "env" fn js_setTextContent(element_id_ptr: [*]const u8, element_id_len: usize, text_ptr: [*]const u8, text_len: usize) void;
extern "env" fn js_log(ptr: [*]const u8, len: usize) void;
extern "env" fn js_setTextContentInt(element_id_ptr: [*]const u8, element_id_len: usize, value: i32) void;

extern "env" fn js_createElement(tag_ptr: [*]const u8, tag_len: usize) u32;
extern "env" fn js_createTextNode(text_ptr: [*]const u8, text_len: usize) u32;
extern "env" fn js_removeElement(handle: u32) void;
extern "env" fn js_insertBefore(parent_handle: u32, child_handle: u32, ref_handle: u32) void;
extern "env" fn js_appendChild(parent_handle: u32, child_handle: u32) void;
extern "env" fn js_setAttribute(handle: u32, name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) void;
extern "env" fn js_removeAttribute(handle: u32, name_ptr: [*]const u8, name_len: usize) void;
extern "env" fn js_setTextContentByHandle(handle: u32, text_ptr: [*]const u8, text_len: usize) void;
extern "env" fn js_updateTextNode(handle: u32, text_ptr: [*]const u8, text_len: usize) void;
extern "env" fn js_attachEvent(handle: u32, event_ptr: [*]const u8, event_len: usize, handler_id: u32) void;
extern "env" fn js_detachEvent(handle: u32, event_ptr: [*]const u8, event_len: usize, handler_id: u32) void;
extern "env" fn js_getRootHandle() u32;
extern "env" fn js_getFirstChild(handle: u32) u32;
extern "env" fn js_getNextSibling(handle: u32) u32;
extern "env" fn js_getTagName(handle: u32, buf_ptr: [*]u8, buf_len: usize) usize;
extern "env" fn js_setInnerHTML(handle: u32, html_ptr: [*]const u8, html_len: usize) void;

pub fn setTextContent(element_id: []const u8, text: []const u8) void {
    js_setTextContent(element_id.ptr, element_id.len, text.ptr, text.len);
}

pub fn log(msg: []const u8) void {
    js_log(msg.ptr, msg.len);
}

pub fn setTextContentInt(element_id: []const u8, value: anytype) void {
    js_setTextContentInt(element_id.ptr, element_id.len, @intCast(value));
}

pub fn createElement(tag: []const u8) u32 {
    return js_createElement(tag.ptr, tag.len);
}

pub fn createTextNode(text: []const u8) u32 {
    return js_createTextNode(text.ptr, text.len);
}

pub fn removeElement(handle: u32) void {
    js_removeElement(handle);
}

pub fn insertBefore(parent_handle: u32, child_handle: u32, ref_handle: u32) void {
    js_insertBefore(parent_handle, child_handle, ref_handle);
}

pub fn appendChild(parent_handle: u32, child_handle: u32) void {
    js_appendChild(parent_handle, child_handle);
}

pub fn setAttribute(handle: u32, name: []const u8, value: []const u8) void {
    js_setAttribute(handle, name.ptr, name.len, value.ptr, value.len);
}

pub fn removeAttribute(handle: u32, name: []const u8) void {
    js_removeAttribute(handle, name.ptr, name.len);
}

pub fn setTextContentByHandle(handle: u32, text: []const u8) void {
    js_setTextContentByHandle(handle, text.ptr, text.len);
}

pub fn updateTextNode(handle: u32, text: []const u8) void {
    js_updateTextNode(handle, text.ptr, text.len);
}

pub fn attachEvent(handle: u32, event: []const u8, handler_id: u32) void {
    js_attachEvent(handle, event.ptr, event.len, handler_id);
}

pub fn detachEvent(handle: u32, event: []const u8, handler_id: u32) void {
    js_detachEvent(handle, event.ptr, event.len, handler_id);
}

pub fn getRootHandle() u32 {
    return js_getRootHandle();
}

pub fn getFirstChild(handle: u32) u32 {
    return js_getFirstChild(handle);
}

pub fn getNextSibling(handle: u32) u32 {
    return js_getNextSibling(handle);
}

pub fn getTagName(handle: u32, buf: []u8) []const u8 {
    const len = js_getTagName(handle, buf.ptr, buf.len);
    return buf[0..len];
}

pub fn setInnerHTML(handle: u32, html: []const u8) void {
    js_setInnerHTML(handle, html.ptr, html.len);
}
