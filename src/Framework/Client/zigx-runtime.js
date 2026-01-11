const ZigxRuntime = {
    memory: null,
    exports: null,

    nextHandle: 1,
    handleToElement: new Map(),
    elementToHandle: new Map(),

    rootSelector: '#zigx-root',

    getHandle(element) {
        if (!element) return 0;

        if (this.elementToHandle.has(element)) {
            return this.elementToHandle.get(element);
        }

        const handle = this.nextHandle++;
        this.handleToElement.set(handle, element);
        this.elementToHandle.set(element, handle);
        return handle;
    },

    getElement(handle) {
        if (handle === 0) return null;
        return this.handleToElement.get(handle) || null;
    },

    removeHandle(handle) {
        const element = this.handleToElement.get(handle);
        if (element) {
            this.elementToHandle.delete(element);
            this.handleToElement.delete(handle);
            if (element._zigxListeners) {
                delete element._zigxListeners;
            }
        }
    },

    async load(wasmPath, rootSelector = '#zigx-root') {
        this.rootSelector = rootSelector;

        const imports = {
            env: {
                js_setTextContent: (idPtr, idLen, textPtr, textLen) => {
                    const id = this.readString(idPtr, idLen);
                    const text = this.readString(textPtr, textLen);
                    const element = document.getElementById(id);
                    if (element) {
                        element.textContent = text;
                    } else {
                        console.warn(`[Zigx] Element not found: ${id}`);
                    }
                },

                js_setTextContentInt: (idPtr, idLen, value) => {
                    const id = this.readString(idPtr, idLen);
                    const element = document.getElementById(id);
                    if (element) {
                        element.textContent = String(value);
                    } else {
                        console.warn(`[Zigx] Element not found: ${id}`);
                    }
                },

                js_log: (ptr, len) => {
                    console.log('[Zigx]', this.readString(ptr, len));
                },

                js_createElement: (tagPtr, tagLen) => {
                    const tag = this.readString(tagPtr, tagLen);
                    const element = document.createElement(tag);
                    return this.getHandle(element);
                },

                js_createTextNode: (textPtr, textLen) => {
                    const text = this.readString(textPtr, textLen);
                    const node = document.createTextNode(text);
                    return this.getHandle(node);
                },

                js_removeElement: (handle) => {
                    const element = this.getElement(handle);
                    if (element && element.parentNode) {
                        element.parentNode.removeChild(element);
                    }
                    this.removeHandle(handle);
                },

                js_insertBefore: (parentHandle, childHandle, refHandle) => {
                    const parent = this.getElement(parentHandle);
                    const child = this.getElement(childHandle);
                    const ref = refHandle ? this.getElement(refHandle) : null;

                    if (parent && child) {
                        parent.insertBefore(child, ref);
                    }
                },

                js_appendChild: (parentHandle, childHandle) => {
                    const parent = this.getElement(parentHandle);
                    const child = this.getElement(childHandle);

                    if (parent && child) {
                        parent.appendChild(child);
                    }
                },

                js_setAttribute: (handle, namePtr, nameLen, valuePtr, valueLen) => {
                    const element = this.getElement(handle);
                    const name = this.readString(namePtr, nameLen);
                    const value = this.readString(valuePtr, valueLen);

                    if (element) {
                        element.setAttribute(name, value);
                    }
                },

                js_removeAttribute: (handle, namePtr, nameLen) => {
                    const element = this.getElement(handle);
                    const name = this.readString(namePtr, nameLen);

                    if (element) {
                        element.removeAttribute(name);
                    }
                },

                js_setTextContentByHandle: (handle, textPtr, textLen) => {
                    const element = this.getElement(handle);
                    const text = this.readString(textPtr, textLen);

                    if (element) {
                        element.textContent = text;
                    }
                },

                js_updateTextNode: (handle, textPtr, textLen) => {
                    const node = this.getElement(handle);
                    const text = this.readString(textPtr, textLen);

                    if (node) {
                        node.textContent = text;
                    }
                },

                js_attachEvent: (handle, eventPtr, eventLen, handlerId) => {
                    const element = this.getElement(handle);
                    const eventName = this.readString(eventPtr, eventLen);

                    if (element) {
                        const listener = (e) => {
                            e.preventDefault();
                            const exportName = `_zigx_handler_${handlerId}`;
                            if (this.exports[exportName]) {
                                this.exports[exportName]();
                            }
                        };

                        element.addEventListener(eventName, listener);

                        if (!element._zigxListeners) {
                            element._zigxListeners = {};
                        }
                        element._zigxListeners[`${eventName}_${handlerId}`] = listener;
                    }
                },

                js_detachEvent: (handle, eventPtr, eventLen, handlerId) => {
                    const element = this.getElement(handle);
                    const eventName = this.readString(eventPtr, eventLen);

                    if (element && element._zigxListeners) {
                        const key = `${eventName}_${handlerId}`;
                        const listener = element._zigxListeners[key];

                        if (listener) {
                            element.removeEventListener(eventName, listener);
                            delete element._zigxListeners[key];
                        }
                    }
                },

                js_getRootHandle: () => {
                    const root = document.querySelector(this.rootSelector);
                    if (!root) {
                        return this.getHandle(document.body);
                    }
                    return this.getHandle(root);
                },

                js_getFirstChild: (handle) => {
                    const element = this.getElement(handle);
                    if (element && element.firstChild) {
                        return this.getHandle(element.firstChild);
                    }
                    return 0;
                },

                js_getNextSibling: (handle) => {
                    const element = this.getElement(handle);
                    if (element && element.nextSibling) {
                        return this.getHandle(element.nextSibling);
                    }
                    return 0;
                },

                js_getTagName: (handle, bufPtr, bufLen) => {
                    const element = this.getElement(handle);
                    if (element && element.tagName) {
                        const tagName = element.tagName.toLowerCase();
                        const bytes = new TextEncoder().encode(tagName);
                        const len = Math.min(bytes.length, bufLen);

                        const view = new Uint8Array(this.memory.buffer, bufPtr, len);
                        view.set(bytes.slice(0, len));

                        return len;
                    }
                    return 0;
                },

                js_setInnerHTML: (handle, htmlPtr, htmlLen) => {
                    const element = this.getElement(handle);
                    const html = this.readString(htmlPtr, htmlLen);

                    if (element) {
                        element.innerHTML = html;
                        this.bindEvents();
                    }
                }
            }
        };

        try {
            const response = await fetch(wasmPath);
            if (!response.ok) {
                throw new Error(`Failed to fetch WASM: ${response.status}`);
            }

            const { instance } = await WebAssembly.instantiateStreaming(response, imports);
            this.memory = instance.exports.memory;
            this.exports = instance.exports;

            if (this.exports._zigx_init) {
                this.exports._zigx_init();
            }

            this.bindEvents();

        } catch (error) {
            console.error('[Zigx] Failed to load WASM:', error);
        }
    },

    bindEvents() {
        document.querySelectorAll('[data-zigx-onclick]').forEach(el => {
            const fnName = el.dataset.zigxOnclick;
            const exportName = `_zigx_${fnName}`;

            if (this.exports[exportName]) {
                el.addEventListener('click', (e) => {
                    e.preventDefault();
                    this.exports[exportName]();
                });
            }
        });

        document.querySelectorAll('[data-zigx-onchange]').forEach(el => {
            const fnName = el.dataset.zigxOnchange;
            const exportName = `_zigx_${fnName}`;

            if (this.exports[exportName]) {
                el.addEventListener('change', () => {
                    this.exports[exportName]();
                });
            }
        });

        document.querySelectorAll('[data-zigx-onsubmit]').forEach(el => {
            const fnName = el.dataset.zigxOnsubmit;
            const exportName = `_zigx_${fnName}`;

            if (this.exports[exportName]) {
                el.addEventListener('submit', (e) => {
                    e.preventDefault();
                    this.exports[exportName]();
                });
            }
        });

        document.querySelectorAll('[data-zigx-click]').forEach(el => {
            const handlerId = parseInt(el.dataset.zigxClick, 10);
            const exportName = `_zigx_handler_${handlerId}`;

            if (this.exports[exportName]) {
                el.addEventListener('click', (e) => {
                    e.preventDefault();
                    this.exports[exportName]();
                });
            }
        });

        document.querySelectorAll('[data-zigx-change]').forEach(el => {
            const handlerId = parseInt(el.dataset.zigxChange, 10);
            const exportName = `_zigx_handler_${handlerId}`;

            if (this.exports[exportName]) {
                el.addEventListener('change', () => {
                    this.exports[exportName]();
                });
            }
        });

        document.querySelectorAll('[data-zigx-submit]').forEach(el => {
            const handlerId = parseInt(el.dataset.zigxSubmit, 10);
            const exportName = `_zigx_handler_${handlerId}`;

            if (this.exports[exportName]) {
                el.addEventListener('submit', (e) => {
                    e.preventDefault();
                    this.exports[exportName]();
                });
            }
        });
    },

    readString(ptr, len) {
        if (!this.memory) {
            return '';
        }
        const bytes = new Uint8Array(this.memory.buffer, ptr, len);
        return new TextDecoder().decode(bytes);
    },

    writeString(ptr, maxLen, str) {
        if (!this.memory) {
            return 0;
        }
        const bytes = new TextEncoder().encode(str);
        const len = Math.min(bytes.length, maxLen);
        const view = new Uint8Array(this.memory.buffer, ptr, len);
        view.set(bytes.slice(0, len));
        return len;
    },

    call(fnName, ...args) {
        const exportName = `_zigx_${fnName}`;
        if (this.exports && this.exports[exportName]) {
            return this.exports[exportName](...args);
        }
        console.warn(`[Zigx] Function not found: ${exportName}`);
    },

    callHandler(handlerId, ...args) {
        const exportName = `_zigx_handler_${handlerId}`;
        if (this.exports && this.exports[exportName]) {
            return this.exports[exportName](...args);
        }
        console.warn(`[Zigx] Handler not found: ${exportName}`);
    }
};

document.addEventListener('DOMContentLoaded', () => {
    const script = document.querySelector('script[data-zigx-wasm]');
    if (script) {
        const wasmPath = script.dataset.zigxWasm;
        const rootSelector = script.dataset.zigxRoot || '#zigx-root';
        ZigxRuntime.load(wasmPath, rootSelector);
    }
});

if (typeof window !== 'undefined') {
    window.ZigxRuntime = ZigxRuntime;
}
