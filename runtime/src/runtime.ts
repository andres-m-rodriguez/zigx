import {
  ZigxWasmExports,
  EventNameToType,
  EventTypeToName,
  EventTypeValue,
  EventOptions,
  ComponentInfo
} from './types.js';

export interface ZigxConfig {
  root: HTMLElement;
  wasmUrl: string;
  debug?: boolean;
}

interface EventListenerInfo {
  listener: EventListener;
  handlerId: number;
  options: number;
}

interface BindingInfo {
  componentId: number;
  field: string;
  type: 'value' | 'checked';
}

export class ZigxRuntime {
  private root: HTMLElement;
  private memory: WebAssembly.Memory | null = null;
  private wasmExports: ZigxWasmExports | null = null;
  private debug: boolean;

  private nodes: Map<number, Node> = new Map();
  private nodeToId: Map<Node, number> = new Map();
  private nextNodeId: number = 1;

  private components: Map<number, ComponentInfo> = new Map();
  private nextComponentId: number = 1;
  private elementToComponent: Map<number, number> = new Map();

  private eventListeners: Map<number, Map<string, EventListenerInfo>> = new Map();
  private bindings: Map<number, BindingInfo> = new Map();
  private timers: Map<number, { type: 'timeout' | 'interval'; id: number }> = new Map();
  private nextTimerId: number = 1;

  private dirtyComponents: Set<number> = new Set();
  private renderScheduled: boolean = false;
  private currentRoute: string = '/';

  private encoder = new TextEncoder();
  private decoder = new TextDecoder();

  constructor(private config: ZigxConfig) {
    this.root = config.root;
    this.debug = config.debug ?? false;
    this.registerNode(this.root);
    this.currentRoute = window.location.pathname;
    window.addEventListener('popstate', () => this.handleRouteChange());
  }

  async start(): Promise<void> {
    const imports = this.createImports();
    const response = await fetch(this.config.wasmUrl);
    const bytes = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(bytes, imports);

    this.wasmExports = instance.exports as unknown as ZigxWasmExports;
    this.memory = this.wasmExports.memory;
    this.wasmExports.zigx_init();

    if (this.debug) console.log('[Zigx] Runtime started');
  }

  private log(...args: unknown[]) {
    if (this.debug) console.log('[Zigx]', ...args);
  }

  private registerNode(node: Node): number {
    const existing = this.nodeToId.get(node);
    if (existing !== undefined) return existing;

    const id = this.nextNodeId++;
    this.nodes.set(id, node);
    this.nodeToId.set(node, id);
    return id;
  }

  private getNode(id: number): Node | undefined {
    return this.nodes.get(id);
  }

  private removeNode(id: number): void {
    const node = this.nodes.get(id);
    if (node) {
      this.nodeToId.delete(node);
      this.nodes.delete(id);
    }
    this.eventListeners.delete(id);
    this.bindings.delete(id);
    this.elementToComponent.delete(id);
  }

  private readString(ptr: number, len: number): string {
    if (!this.memory) throw new Error('Memory not initialized');
    const bytes = new Uint8Array(this.memory.buffer, ptr, len);
    return this.decoder.decode(bytes);
  }

  private writeString(ptr: number, str: string): number {
    if (!this.memory) throw new Error('Memory not initialized');
    const bytes = this.encoder.encode(str);
    const view = new Uint8Array(this.memory.buffer, ptr, bytes.length);
    view.set(bytes);
    return bytes.length;
  }

  private scheduleRender(): void {
    if (this.renderScheduled) return;
    this.renderScheduled = true;

    requestAnimationFrame(() => {
      this.renderScheduled = false;
      this.processDirtyComponents();
    });
  }

  private processDirtyComponents(): void {
    if (!this.wasmExports) return;

    const sorted = Array.from(this.dirtyComponents).sort((a, b) => {
      const compA = this.components.get(a);
      const compB = this.components.get(b);
      const depthA = this.getComponentDepth(compA);
      const depthB = this.getComponentDepth(compB);
      return depthA - depthB;
    });

    this.dirtyComponents.clear();

    for (const componentId of sorted) {
      const component = this.components.get(componentId);
      if (!component) continue;

      const oldRootId = component.rootElementId;
      const newRootId = this.wasmExports.zigx_render_component(componentId);

      if (oldRootId !== null && oldRootId !== newRootId) {
        const oldNode = this.getNode(oldRootId);
        const newNode = this.getNode(newRootId);
        if (oldNode && newNode && oldNode.parentNode) {
          oldNode.parentNode.replaceChild(newNode, oldNode);
        }
      }

      component.rootElementId = newRootId;
      component.isDirty = false;

      if (component.isMounted) {
        this.wasmExports.zigx_on_update(componentId);
      } else {
        component.isMounted = true;
        this.wasmExports.zigx_on_mount(componentId);
      }
    }
  }

  private getComponentDepth(component: ComponentInfo | undefined): number {
    let depth = 0;
    let current = component;
    while (current?.parentId) {
      depth++;
      current = this.components.get(current.parentId);
    }
    return depth;
  }

  private handleRouteChange(): void {
    this.currentRoute = window.location.pathname;
    if (this.wasmExports) {
      this.wasmExports.zigx_init();
    }
  }

  private buildEventPayload(event: Event): string {
    if (event instanceof InputEvent || event.type === 'input' || event.type === 'change') {
      const target = event.target as HTMLInputElement;
      if (target.type === 'checkbox') {
        return target.checked ? 'true' : 'false';
      }
      return target.value || '';
    }

    if (event instanceof KeyboardEvent) {
      return JSON.stringify({
        key: event.key,
        code: event.code,
        ctrl: event.ctrlKey,
        shift: event.shiftKey,
        alt: event.altKey,
        meta: event.metaKey,
      });
    }

    if (event instanceof MouseEvent) {
      return JSON.stringify({
        x: event.clientX,
        y: event.clientY,
        button: event.button,
        ctrl: event.ctrlKey,
        shift: event.shiftKey,
        alt: event.altKey,
      });
    }

    return '';
  }

  private handleDomEvent(
    elementId: number,
    handlerId: number,
    eventType: EventTypeValue,
    event: Event,
    options: number
  ): void {
    if (!this.wasmExports || !this.memory) return;

    if (options & EventOptions.PREVENT_DEFAULT) event.preventDefault();
    if (options & EventOptions.STOP_PROPAGATION) event.stopPropagation();

    const componentId = this.elementToComponent.get(elementId) ?? 0;
    const payload = this.buildEventPayload(event);

    let payloadPtr = 0;
    let payloadLen = 0;

    if (payload.length > 0) {
      const bytes = this.encoder.encode(payload);
      payloadLen = bytes.length;
      payloadPtr = this.wasmExports.zigx_alloc(payloadLen);
      const view = new Uint8Array(this.memory.buffer, payloadPtr, payloadLen);
      view.set(bytes);
    }

    this.log(`Event: ${EventTypeToName[eventType]} on element ${elementId}, handler ${handlerId}`);
    this.wasmExports.zigx_handle_event(componentId, handlerId, eventType, payloadPtr, payloadLen);

    if (payloadPtr !== 0) {
      this.wasmExports.zigx_free(payloadPtr, payloadLen);
    }
  }

  private createImports(): WebAssembly.Imports {
    const self = this;

    return {
      zigx: {
        register_component(type_ptr: number, type_len: number): number {
          const type = self.readString(type_ptr, type_len);
          const id = self.nextComponentId++;
          const component: ComponentInfo = {
            id,
            type,
            rootElementId: null,
            parentId: null,
            children: [],
            isDirty: true,
            isMounted: false,
          };
          self.components.set(id, component);
          self.dirtyComponents.add(id);
          self.log(`register_component("${type}") -> ${id}`);
          return id;
        },

        mark_dirty(component_id: number): void {
          const component = self.components.get(component_id);
          if (component && !component.isDirty) {
            component.isDirty = true;
            self.dirtyComponents.add(component_id);
            self.log(`mark_dirty(${component_id})`);
          }
        },

        request_render(): void {
          self.scheduleRender();
        },

        get_component_id(element_id: number): number {
          return self.elementToComponent.get(element_id) ?? 0;
        },

        create_element(tag_ptr: number, tag_len: number): number {
          const tag = self.readString(tag_ptr, tag_len);
          const element = document.createElement(tag);
          const id = self.registerNode(element);
          self.log(`create_element("${tag}") -> ${id}`);
          return id;
        },

        create_text(text_ptr: number, text_len: number): number {
          const text = self.readString(text_ptr, text_len);
          const node = document.createTextNode(text);
          const id = self.registerNode(node);
          self.log(`create_text("${text.substring(0, 20)}...") -> ${id}`);
          return id;
        },

        create_component_root(component_id: number): number {
          const marker = document.createComment(`zigx-component-${component_id}`);
          const id = self.registerNode(marker);
          self.elementToComponent.set(id, component_id);
          return id;
        },

        set_attribute(element_id: number, name_ptr: number, name_len: number, value_ptr: number, value_len: number): void {
          const element = self.getNode(element_id) as HTMLElement;
          if (!element || !(element instanceof HTMLElement)) return;
          const name = self.readString(name_ptr, name_len);
          const value = self.readString(value_ptr, value_len);
          element.setAttribute(name, value);
        },

        remove_attribute(element_id: number, name_ptr: number, name_len: number): void {
          const element = self.getNode(element_id) as HTMLElement;
          if (!element || !(element instanceof HTMLElement)) return;
          const name = self.readString(name_ptr, name_len);
          element.removeAttribute(name);
        },

        set_text_content(node_id: number, text_ptr: number, text_len: number): void {
          const node = self.getNode(node_id);
          if (!node) return;
          const text = self.readString(text_ptr, text_len);
          node.textContent = text;
        },

        set_property(element_id: number, name_ptr: number, name_len: number, value_ptr: number, value_len: number): void {
          const element = self.getNode(element_id) as HTMLElement;
          if (!element) return;
          const name = self.readString(name_ptr, name_len);
          const value = self.readString(value_ptr, value_len);
          (element as any)[name] = name === 'checked' ? value === 'true' : value;
        },

        append_child(parent_id: number, child_id: number): void {
          const parent = self.getNode(parent_id);
          const child = self.getNode(child_id);
          if (!parent || !child) return;
          parent.appendChild(child);
        },

        insert_before(parent_id: number, new_node_id: number, reference_id: number): void {
          const parent = self.getNode(parent_id);
          const newNode = self.getNode(new_node_id);
          const reference = self.getNode(reference_id);
          if (!parent || !newNode) return;
          parent.insertBefore(newNode, reference || null);
        },

        remove_child(parent_id: number, child_id: number): void {
          const parent = self.getNode(parent_id);
          const child = self.getNode(child_id);
          if (!parent || !child) return;
          parent.removeChild(child);
          self.removeNode(child_id);
        },

        replace_child(parent_id: number, new_child_id: number, old_child_id: number): void {
          const parent = self.getNode(parent_id);
          const newChild = self.getNode(new_child_id);
          const oldChild = self.getNode(old_child_id);
          if (!parent || !newChild || !oldChild) return;
          parent.replaceChild(newChild, oldChild);
          self.removeNode(old_child_id);
        },

        clear_children(element_id: number): void {
          const element = self.getNode(element_id) as HTMLElement;
          if (!element) return;
          while (element.firstChild) {
            const child = element.firstChild;
            const childId = self.nodeToId.get(child);
            element.removeChild(child);
            if (childId) self.removeNode(childId);
          }
        },

        add_event_listener(
          element_id: number,
          event_type_ptr: number,
          event_type_len: number,
          handler_id: number,
          options: number
        ): void {
          const element = self.getNode(element_id);
          if (!element) return;

          const eventName = self.readString(event_type_ptr, event_type_len);
          const eventType = EventNameToType[eventName];
          if (eventType === undefined) {
            console.warn(`[Zigx] Unknown event type: ${eventName}`);
            return;
          }

          const listener: EventListener = (event: Event) => {
            self.handleDomEvent(element_id, handler_id, eventType, event, options);
          };

          const listenerOptions = {
            once: (options & EventOptions.ONCE) !== 0,
          };

          element.addEventListener(eventName, listener, listenerOptions);

          if (!self.eventListeners.has(element_id)) {
            self.eventListeners.set(element_id, new Map());
          }
          self.eventListeners.get(element_id)!.set(eventName, { listener, handlerId: handler_id, options });
        },

        remove_event_listener(element_id: number, event_type_ptr: number, event_type_len: number): void {
          const element = self.getNode(element_id);
          if (!element) return;

          const eventName = self.readString(event_type_ptr, event_type_len);
          const listeners = self.eventListeners.get(element_id);
          const info = listeners?.get(eventName);

          if (info) {
            element.removeEventListener(eventName, info.listener);
            listeners!.delete(eventName);
          }
        },

        bind_value(element_id: number, component_id: number, field_ptr: number, field_len: number): void {
          const element = self.getNode(element_id) as HTMLInputElement;
          if (!element) return;

          const field = self.readString(field_ptr, field_len);
          self.bindings.set(element_id, { componentId: component_id, field, type: 'value' });

          const listener = () => {
            const component = self.components.get(component_id);
            if (component) {
              component.isDirty = true;
              self.dirtyComponents.add(component_id);
              self.scheduleRender();
            }
          };

          element.addEventListener('input', listener);
        },

        bind_checked(element_id: number, component_id: number, field_ptr: number, field_len: number): void {
          const element = self.getNode(element_id) as HTMLInputElement;
          if (!element) return;

          const field = self.readString(field_ptr, field_len);
          self.bindings.set(element_id, { componentId: component_id, field, type: 'checked' });

          const listener = () => {
            const component = self.components.get(component_id);
            if (component) {
              component.isDirty = true;
              self.dirtyComponents.add(component_id);
              self.scheduleRender();
            }
          };

          element.addEventListener('change', listener);
        },

        navigate(route_ptr: number, route_len: number): void {
          const route = self.readString(route_ptr, route_len);
          window.history.pushState({}, '', route);
          self.handleRouteChange();
        },

        get_current_route(out_ptr: number, out_len: number): number {
          const route = self.currentRoute;
          const bytes = self.encoder.encode(route);
          if (bytes.length > out_len) return 0;
          self.writeString(out_ptr, route);
          return bytes.length;
        },

        get_root_id(): number {
          return 1;
        },

        console_log(msg_ptr: number, msg_len: number): void {
          const msg = self.readString(msg_ptr, msg_len);
          console.log(`[WASM] ${msg}`);
        },

        console_error(msg_ptr: number, msg_len: number): void {
          const msg = self.readString(msg_ptr, msg_len);
          console.error(`[WASM] ${msg}`);
        },

        get_timestamp(): number {
          return performance.now();
        },

        set_timeout(component_id: number, handler_id: number, delay_ms: number): number {
          const timerId = self.nextTimerId++;
          const id = window.setTimeout(() => {
            self.timers.delete(timerId);
            if (self.wasmExports && self.memory) {
              self.wasmExports.zigx_handle_event(component_id, handler_id, 0, 0, 0);
            }
          }, delay_ms);
          self.timers.set(timerId, { type: 'timeout', id });
          return timerId;
        },

        clear_timeout(timer_id: number): void {
          const timer = self.timers.get(timer_id);
          if (timer && timer.type === 'timeout') {
            window.clearTimeout(timer.id);
            self.timers.delete(timer_id);
          }
        },

        set_interval(component_id: number, handler_id: number, interval_ms: number): number {
          const timerId = self.nextTimerId++;
          const id = window.setInterval(() => {
            if (self.wasmExports && self.memory) {
              self.wasmExports.zigx_handle_event(component_id, handler_id, 0, 0, 0);
            }
          }, interval_ms);
          self.timers.set(timerId, { type: 'interval', id });
          return timerId;
        },

        clear_interval(timer_id: number): void {
          const timer = self.timers.get(timer_id);
          if (timer && timer.type === 'interval') {
            window.clearInterval(timer.id);
            self.timers.delete(timer_id);
          }
        },
      },
    };
  }

  destroyComponent(componentId: number): void {
    const component = this.components.get(componentId);
    if (!component) return;

    if (this.wasmExports) {
      this.wasmExports.zigx_on_destroy(componentId);
    }

    for (const childId of component.children) {
      this.destroyComponent(childId);
    }

    if (component.rootElementId !== null) {
      const node = this.getNode(component.rootElementId);
      if (node && node.parentNode) {
        node.parentNode.removeChild(node);
      }
      this.removeNode(component.rootElementId);
    }

    this.components.delete(componentId);
    this.dirtyComponents.delete(componentId);
  }

  getComponentInfo(componentId: number): ComponentInfo | undefined {
    return this.components.get(componentId);
  }
}

export async function createZigxApp(config: ZigxConfig): Promise<ZigxRuntime> {
  const runtime = new ZigxRuntime(config);
  await runtime.start();
  return runtime;
}
