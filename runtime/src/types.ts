export interface ZigxWasmExports {
  memory: WebAssembly.Memory;
  zigx_init(): void;
  zigx_handle_event(component_id: number, handler_id: number, event_type: number, payload_ptr: number, payload_len: number): void;
  zigx_render_component(component_id: number): number;
  zigx_on_mount(component_id: number): void;
  zigx_on_update(component_id: number): void;
  zigx_on_destroy(component_id: number): void;
  zigx_get_state(component_id: number, out_ptr: number, out_len: number): number;
  zigx_alloc(size: number): number;
  zigx_free(ptr: number, size: number): void;
}

export interface ZigxHostImports {
  register_component(type_ptr: number, type_len: number): number;
  mark_dirty(component_id: number): void;
  request_render(): void;
  get_component_id(element_id: number): number;

  create_element(tag_ptr: number, tag_len: number): number;
  create_text(text_ptr: number, text_len: number): number;
  create_component_root(component_id: number): number;

  set_attribute(element_id: number, name_ptr: number, name_len: number, value_ptr: number, value_len: number): void;
  remove_attribute(element_id: number, name_ptr: number, name_len: number): void;
  set_text_content(node_id: number, text_ptr: number, text_len: number): void;
  set_property(element_id: number, name_ptr: number, name_len: number, value_ptr: number, value_len: number): void;

  append_child(parent_id: number, child_id: number): void;
  insert_before(parent_id: number, new_node_id: number, reference_id: number): void;
  remove_child(parent_id: number, child_id: number): void;
  replace_child(parent_id: number, new_child_id: number, old_child_id: number): void;
  clear_children(element_id: number): void;

  add_event_listener(element_id: number, event_type_ptr: number, event_type_len: number, handler_id: number, options: number): void;
  remove_event_listener(element_id: number, event_type_ptr: number, event_type_len: number): void;

  bind_value(element_id: number, component_id: number, field_ptr: number, field_len: number): void;
  bind_checked(element_id: number, component_id: number, field_ptr: number, field_len: number): void;

  navigate(route_ptr: number, route_len: number): void;
  get_current_route(out_ptr: number, out_len: number): number;

  get_root_id(): number;
  console_log(msg_ptr: number, msg_len: number): void;
  console_error(msg_ptr: number, msg_len: number): void;
  get_timestamp(): number;

  set_timeout(component_id: number, handler_id: number, delay_ms: number): number;
  clear_timeout(timer_id: number): void;
  set_interval(component_id: number, handler_id: number, interval_ms: number): number;
  clear_interval(timer_id: number): void;

  // DOM traversal (migrated from JS runtime)
  get_first_child(node_id: number): number;
  get_next_sibling(node_id: number): number;
  get_parent_node(node_id: number): number;
  get_tag_name(element_id: number, buf_ptr: number, buf_len: number): number;

  // Text content by ID (migrated from JS runtime)
  set_text_content_by_id(id_ptr: number, id_len: number, text_ptr: number, text_len: number): void;
  set_text_content_int(id_ptr: number, id_len: number, value: number): void;

  // innerHTML (migrated from JS runtime)
  set_inner_html(element_id: number, html_ptr: number, html_len: number): void;

  // Element operations (migrated from JS runtime)
  remove_element(element_id: number): void;
  get_element_by_id(id_ptr: number, id_len: number): number;
  query_selector(selector_ptr: number, selector_len: number): number;
}

export const EventType = {
  CLICK: 1,
  DBLCLICK: 2,
  MOUSEDOWN: 3,
  MOUSEUP: 4,
  MOUSEMOVE: 5,
  MOUSEOVER: 6,
  MOUSEOUT: 7,
  MOUSEENTER: 8,
  MOUSELEAVE: 9,
  CONTEXTMENU: 10,

  KEYDOWN: 20,
  KEYUP: 21,
  KEYPRESS: 22,

  INPUT: 30,
  CHANGE: 31,
  SUBMIT: 32,
  RESET: 33,
  FOCUS: 34,
  BLUR: 35,
  FOCUSIN: 36,
  FOCUSOUT: 37,

  TOUCHSTART: 40,
  TOUCHEND: 41,
  TOUCHMOVE: 42,
  TOUCHCANCEL: 43,

  DRAGSTART: 50,
  DRAG: 51,
  DRAGEND: 52,
  DRAGENTER: 53,
  DRAGLEAVE: 54,
  DRAGOVER: 55,
  DROP: 56,

  SCROLL: 60,
  RESIZE: 61,
  WHEEL: 62,
} as const;

export type EventTypeValue = typeof EventType[keyof typeof EventType];

export const EventNameToType: Record<string, EventTypeValue> = {
  'click': EventType.CLICK,
  'dblclick': EventType.DBLCLICK,
  'mousedown': EventType.MOUSEDOWN,
  'mouseup': EventType.MOUSEUP,
  'mousemove': EventType.MOUSEMOVE,
  'mouseover': EventType.MOUSEOVER,
  'mouseout': EventType.MOUSEOUT,
  'mouseenter': EventType.MOUSEENTER,
  'mouseleave': EventType.MOUSELEAVE,
  'contextmenu': EventType.CONTEXTMENU,

  'keydown': EventType.KEYDOWN,
  'keyup': EventType.KEYUP,
  'keypress': EventType.KEYPRESS,

  'input': EventType.INPUT,
  'change': EventType.CHANGE,
  'submit': EventType.SUBMIT,
  'reset': EventType.RESET,
  'focus': EventType.FOCUS,
  'blur': EventType.BLUR,
  'focusin': EventType.FOCUSIN,
  'focusout': EventType.FOCUSOUT,

  'touchstart': EventType.TOUCHSTART,
  'touchend': EventType.TOUCHEND,
  'touchmove': EventType.TOUCHMOVE,
  'touchcancel': EventType.TOUCHCANCEL,

  'dragstart': EventType.DRAGSTART,
  'drag': EventType.DRAG,
  'dragend': EventType.DRAGEND,
  'dragenter': EventType.DRAGENTER,
  'dragleave': EventType.DRAGLEAVE,
  'dragover': EventType.DRAGOVER,
  'drop': EventType.DROP,

  'scroll': EventType.SCROLL,
  'resize': EventType.RESIZE,
  'wheel': EventType.WHEEL,
};

export const EventTypeToName: Record<number, string> = Object.fromEntries(
  Object.entries(EventNameToType).map(([name, type]) => [type, name])
);

export const EventOptions = {
  PREVENT_DEFAULT: 1,
  STOP_PROPAGATION: 2,
  ONCE: 4,
} as const;

export interface ComponentInfo {
  id: number;
  type: string;
  rootElementId: number | null;
  parentId: number | null;
  children: number[];
  isDirty: boolean;
  isMounted: boolean;
}
