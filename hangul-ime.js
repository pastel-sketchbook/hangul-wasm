/**
 * HangulIme - Korean Input Method Editor
 * Uses hangul.wasm for high-performance Korean text composition
 * 
 * Based on ohi.js by Ho-Seok Ee
 * Ported to Zig/WASM for better performance and smaller bundle size
 */

// Standard 2-Bulsik (Dubeolsik) Korean keyboard layout
// This is the authentic Korean QWERTY layout used in Korea
// Based on ohi.js standard layout mapping (with corrections for double consonants)
const LAYOUT_2BULSIK = {
    // Lowercase (unshifted)
    'a': 17, 'b': 48, 'c': 26, 'd': 23, 'e': 7,  'f': 9,  'g': 30, 'h': 39, 'i': 33,
    'j': 35, 'k': 31, 'l': 51, 'm': 49, 'n': 44, 'o': 32, 'p': 36, 'q': 18, 'r': 1,
    's': 4,  't': 21, 'u': 37, 'v': 29, 'w': 24, 'x': 28, 'y': 43, 'z': 27,
    
    // Uppercase (shifted) - CORRECTED for double consonants
    // Double consonants on standard 2-Bulsik: Shift+Q/W/E/R/T
    'A': 17, 'B': 48, 'C': 26, 'D': 23, 'E': 8,  'F': 11, 'G': 30, 'H': 39, 'I': 33,
    'J': 35, 'K': 31, 'L': 51, 'M': 49, 'N': 44, 'O': 34, 'P': 38, 'Q': 19, 'R': 2,
    'S': 6,  'T': 22, 'U': 37, 'V': 29, 'W': 25, 'X': 28, 'Y': 43, 'Z': 27
};

// IME Layout modes
const LAYOUT_MODE_2BULSIK = '2bulsik';
const LAYOUT_MODE_3BULSIK = '3bulsik';

const ACTION_NO_CHANGE = 0;
const ACTION_REPLACE = 1;
const ACTION_EMIT_AND_NEW = 2;
const ACTION_LITERAL = 3; // For 3-Bulsik punctuation

// Debug flag - set to true to enable console logging
let DEBUG = false;

export class HangulIme {
    constructor(wasmModule, options = {}) {
        this.wasm = wasmModule.instance.exports;
        this.memory = wasmModule.instance.exports.memory;
        this.handle = this.wasm.wasm_ime_create();
        this.enabled = false;
        this.hasComposition = false; // Track if there's an active composition
        this.compositionStart = -1; // Track where composition started in the text field
        this.debug = options.debug !== undefined ? options.debug : DEBUG;
        this.layoutMode = options.layout || LAYOUT_MODE_2BULSIK; // Default to 2-Bulsik
        
        // Allocate result buffer once (reusable)
        // 4 × u32 for 3-Bulsik (includes literal codepoint)
        this.resultBuffer = this.wasm.wasm_alloc(16);
        
        if (this.handle === 0 || this.resultBuffer === 0) {
            throw new Error('Failed to initialize IME (WASM allocation failed)');
        }
    }
    
    destroy() {
        if (this.resultBuffer !== 0) {
            this.wasm.wasm_free(this.resultBuffer, 16);
            this.resultBuffer = 0;
        }
        if (this.handle !== 0) {
            this.wasm.wasm_ime_destroy(this.handle);
            this.handle = 0;
        }
    }
    
    /**
     * Set the keyboard layout mode
     * @param {'2bulsik'|'3bulsik'} mode - Layout mode
     */
    setLayoutMode(mode) {
        if (mode === LAYOUT_MODE_2BULSIK || mode === LAYOUT_MODE_3BULSIK) {
            this.layoutMode = mode;
            this.reset();
            if (this.debug) {
                console.log(`[HangulIme] Layout mode set to: ${mode}`);
            }
        }
    }
    
    /**
     * Get the current keyboard layout mode
     * @returns {'2bulsik'|'3bulsik'} Current layout mode
     */
    getLayoutMode() {
        return this.layoutMode;
    }
    
    enable() {
        this.enabled = true;
        this.reset();
    }
    
    disable() {
        this.enabled = false;
        this.reset();
    }
    
    isEnabled() {
        return this.enabled;
    }
    
    setDebug(enabled) {
        this.debug = enabled;
        if (this.debug) {
            console.log('[HangulIme] Debug mode enabled');
        }
    }
    
    isDebugEnabled() {
        return this.debug;
    }
    
    reset() {
        this.wasm.wasm_ime_reset(this.handle);
        this.hasComposition = false;
        this.compositionStart = -1;
    }
    
    /**
     * Commit the current composition and reset IME state
     * Use this when the user moves focus away or explicitly finalizes input
     * @param {HTMLInputElement|HTMLTextAreaElement} [field] - Optional field to update
     * @returns {string|null} - The committed character, or null if nothing to commit
     */
    commit(field = null) {
        // Call WASM to commit and get the finalized codepoint
        const codepoint = this.wasm.wasm_ime_commit(this.handle);
        
        if (codepoint === 0) {
            // Nothing to commit - just reset local state
            this.hasComposition = false;
            this.compositionStart = -1;
            return null;
        }
        
        const char = String.fromCodePoint(codepoint);
        
        if (this.debug) {
            console.log(`[HangulIme] Committed: ${char} (U+${codepoint.toString(16).toUpperCase()})`);
        }
        
        // Reset local state (WASM state already reset by wasm_ime_commit)
        this.hasComposition = false;
        this.compositionStart = -1;
        
        return char;
    }
    
    /**
     * Handle a key press event
     * @param {KeyboardEvent} event - The keyboard event
     * @param {HTMLInputElement|HTMLTextAreaElement} field - The input field
     * @returns {boolean} - true if event was handled (and should be prevented)
     */
    handleKeyPress(event, field) {
        if (!this.enabled) return false;
        
        // Only handle printable single characters (not space, enter, etc.)
        if (event.key.length !== 1) return false;
        
        // Don't intercept space - let browser handle it
        if (event.key === ' ') return false;
        
        const char = event.key;
        
        if (this.layoutMode === LAYOUT_MODE_3BULSIK) {
            return this.handleKeyPress3Bulsik(char, field);
        } else {
            return this.handleKeyPress2Bulsik(char, field);
        }
    }
    
    /**
     * Handle key press in 2-Bulsik mode
     */
    handleKeyPress2Bulsik(char, field) {
        const jamoIndex = LAYOUT_2BULSIK[char];
        
        if (this.debug) {
            console.log(`[HangulIme] 2-Bulsik key: '${char}' → jamo index: ${jamoIndex}`);
        }
        
        if (jamoIndex === undefined) return false; // Not a Korean key
        
        // Process the keystroke through WASM
        const handled = this.wasm.wasm_ime_processKey(
            this.handle,
            jamoIndex,
            this.resultBuffer
        );
        
        if (!handled) return false;
        
        // Read result from WASM memory
        const view = new Uint32Array(this.memory.buffer, this.resultBuffer, 3);
        const action = view[0];
        const prevCodepoint = view[1];
        const currentCodepoint = view[2];
        
        return this.handleResult(char, field, action, prevCodepoint, currentCodepoint);
    }
    
    /**
     * Handle key press in 3-Bulsik mode
     */
    handleKeyPress3Bulsik(char, field) {
        const ascii = char.charCodeAt(0);
        
        // 3-Bulsik handles ASCII 33-126
        if (ascii < 33 || ascii > 126) return false;
        
        if (this.debug) {
            console.log(`[HangulIme] 3-Bulsik key: '${char}' (ASCII ${ascii})`);
        }
        
        // Process the keystroke through WASM
        const handled = this.wasm.wasm_ime_processKey3(
            this.handle,
            ascii,
            this.resultBuffer
        );
        
        if (!handled) return false;
        
        // Read result from WASM memory (4 × u32 for 3-Bulsik)
        const view = new Uint32Array(this.memory.buffer, this.resultBuffer, 4);
        const action = view[0];
        const prevCodepoint = view[1];
        const currentCodepoint = view[2];
        const literalCodepoint = view[3];
        
        // Handle literal action (3-Bulsik punctuation)
        if (action === ACTION_LITERAL) {
            if (literalCodepoint !== 0) {
                this.insertChar(field, literalCodepoint);
            }
            return true;
        }
        
        // For emit_and_new with literal, insert the literal after handling
        if (action === ACTION_EMIT_AND_NEW && literalCodepoint !== 0) {
            this.handleResult(char, field, action, prevCodepoint, 0);
            this.insertChar(field, literalCodepoint);
            this.hasComposition = false;
            this.compositionStart = -1;
            return true;
        }
        
        return this.handleResult(char, field, action, prevCodepoint, currentCodepoint);
    }
    
    /**
     * Handle the result from WASM processing
     */
    handleResult(char, field, action, prevCodepoint, currentCodepoint) {
        if (this.debug) {
            console.log(`[HangulIme]   → WASM result: action=${action}, prev=U+${prevCodepoint.toString(16).toUpperCase().padStart(4, '0')}, current=U+${currentCodepoint.toString(16).toUpperCase().padStart(4, '0')} (${currentCodepoint !== 0 ? String.fromCodePoint(currentCodepoint) : ''})`);
        }
        
        switch (action) {
            case ACTION_REPLACE:
                // Replace the last character with the new composition
                // Only replace if we have an active composition, otherwise insert
                if (this.debug) {
                    console.log(`[HangulIme] ACTION_REPLACE: hasComposition=${this.hasComposition}, compositionStart=${this.compositionStart}`);
                }
                if (this.hasComposition && this.compositionStart >= 0) {
                    this.replaceComposition(field, currentCodepoint);
                } else {
                    // Starting new composition
                    this.compositionStart = field.selectionStart;
                    this.insertChar(field, currentCodepoint);
                }
                this.hasComposition = true;
                break;
                
            case ACTION_EMIT_AND_NEW:
                // Emit the previous syllable (replace current char with prev)
                // Then insert the new syllable
                if (this.debug) {
                    console.log(`[HangulIme] ACTION_EMIT_AND_NEW: prev=${prevCodepoint !== 0 ? String.fromCodePoint(prevCodepoint) : ''}, current=${currentCodepoint !== 0 ? String.fromCodePoint(currentCodepoint) : ''}, compositionStart=${this.compositionStart}`);
                }
                if (prevCodepoint !== 0 && this.hasComposition && this.compositionStart >= 0) {
                    // Replace the current composition with the emitted syllable
                    this.replaceComposition(field, prevCodepoint);
                }
                // Start new composition at the next position
                this.compositionStart = this.compositionStart >= 0 ? this.compositionStart + 1 : field.selectionStart;
                // Insert the new character
                if (currentCodepoint !== 0) {
                    this.insertChar(field, currentCodepoint);
                    this.hasComposition = true;
                } else {
                    this.hasComposition = false;
                    this.compositionStart = -1;
                }
                break;
                
            case ACTION_NO_CHANGE:
            default:
                // Do nothing
                break;
        }
        
        return true; // Event was handled
    }
    
    /**
     * Handle backspace key
     * @param {HTMLInputElement|HTMLTextAreaElement} field - The input field
     * @returns {boolean} - true if event was handled (and should be prevented)
     */
    handleBackspace(field) {
        if (!this.enabled) return false;
        
        if (this.debug) {
            console.log(`[HangulIme] Backspace: hasComposition=${this.hasComposition}, compositionStart=${this.compositionStart}, cursor=${field.selectionStart}, value="${field.value}"`);
        }
        
        // If no active composition, let browser handle
        if (!this.hasComposition || this.compositionStart < 0) {
            if (this.debug) {
                console.log(`[HangulIme]   → No active composition, letting browser handle`);
            }
            return false;
        }
        
        const newCodepoint = this.wasm.wasm_ime_backspace(this.handle);
        
        if (this.debug) {
            console.log(`[HangulIme]   → WASM backspace returned: U+${newCodepoint.toString(16).toUpperCase().padStart(4, '0')} (${newCodepoint !== 0 ? String.fromCodePoint(newCodepoint) : 'empty'})`);
        }
        
        if (newCodepoint !== 0) {
            // Replace composition character with decomposed version
            this.replaceComposition(field, newCodepoint);
            
            if (this.debug) {
                console.log(`[HangulIme]   → After replace: cursor=${field.selectionStart}, value="${field.value}"`);
            }
            
            return true;
        }
        
        // newCodepoint === 0: IME state is empty
        // Delete the composition character and reset
        if (this.debug) {
            console.log(`[HangulIme]   → IME empty, deleting composition at ${this.compositionStart}`);
        }
        
        const pos = this.compositionStart;
        if (pos >= 0 && pos < field.value.length) {
            field.value = 
                field.value.slice(0, pos) + 
                field.value.slice(pos + 1);
            field.selectionStart = field.selectionEnd = pos;
        }
        
        this.hasComposition = false;
        this.compositionStart = -1;
        return true; // We handled it by deleting the composition
    }
    
    /**
     * Replace the composition character at the tracked position
     * Uses compositionStart to know exactly where to replace
     */
    replaceComposition(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const pos = this.compositionStart;
        
        if (this.debug) {
            console.log(`[HangulIme] replaceComposition: '${char}' at compositionStart=${pos}, value="${field.value}"`);
            if (pos >= 0 && pos < field.value.length) {
                console.log(`[HangulIme]   → Replacing char at index ${pos}: '${field.value[pos]}'`);
            }
        }
        
        if (pos < 0 || pos >= field.value.length) {
            // Invalid position, fall back to insert
            if (this.debug) {
                console.log(`[HangulIme]   → Invalid position, falling back to insert`);
            }
            this.compositionStart = field.selectionStart;
            this.insertChar(field, codepoint);
            return;
        }
        
        // Replace character at compositionStart
        field.value = 
            field.value.slice(0, pos) + 
            char + 
            field.value.slice(pos + 1);
        
        // Set cursor after the composition
        field.selectionStart = field.selectionEnd = pos + 1;
        
        if (this.debug) {
            console.log(`[HangulIme]   → After replace: cursor=${field.selectionStart}, value="${field.value}"`);
        }
    }
    
    /**
     * Insert a character at the cursor position
     */
    insertChar(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const start = field.selectionStart;
        const end = field.selectionEnd;
        
        if (this.debug) {
            console.log(`[HangulIme] insertChar: '${char}' at cursor=${start}, value="${field.value}"`);
        }
        
        field.value = 
            field.value.slice(0, start) + 
            char + 
            field.value.slice(end);
        
        field.selectionStart = field.selectionEnd = start + char.length;
        
        if (this.debug) {
            console.log(`[HangulIme]   → After insert: cursor=${field.selectionStart}, value="${field.value}"`);
        }
    }
    
    /**
     * Replace the last character at the cursor position
     */
    replaceLastChar(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const start = field.selectionStart;
        
        if (this.debug) {
            console.log(`[HangulIme] replaceLastChar: '${char}' at cursor=${start}, value="${field.value}"`);
            if (start > 0) {
                console.log(`[HangulIme]   → Replacing char at index ${start-1}: '${field.value[start-1]}'`);
            }
        }
        
        if (start === 0) {
            // Nothing to replace, just insert
            this.insertChar(field, codepoint);
            return;
        }
        
        field.value = 
            field.value.slice(0, start - 1) + 
            char + 
            field.value.slice(start);
        
        field.selectionStart = field.selectionEnd = start;
        
        if (this.debug) {
            console.log(`[HangulIme]   → After replace: cursor=${field.selectionStart}, value="${field.value}"`);
        }
    }
    
    /**
     * Get current IME state (for debugging)
     */
    getState() {
        const stateBuffer = this.wasm.wasm_alloc(6);
        this.wasm.wasm_ime_getState(this.handle, stateBuffer);
        
        const view = new Uint8Array(this.memory.buffer, stateBuffer, 6);
        const state = {
            initial: view[0],
            initial_flag: view[1],
            medial: view[2],
            medial_flag: view[3],
            final: view[4],
            final_flag: view[5]
        };
        
        this.wasm.wasm_free(stateBuffer, 6);
        return state;
    }
}

/**
 * Setup IME on input fields
 * @param {WebAssembly.Module} wasmModule - The loaded WASM module
 * @param {string} fieldSelector - CSS selector for input fields (default: 'input[type="text"], textarea')
 * @returns {HangulIme} - The IME instance
 */
export function setupIme(wasmModule, fieldSelector = 'input[type="text"], textarea') {
    const ime = new HangulIme(wasmModule);
    
    // Handle keyboard events on all matching fields
    document.addEventListener('keydown', (e) => {
        const field = e.target;
        if (!field.matches(fieldSelector)) return;
        
        if (e.key === 'Backspace') {
            if (ime.handleBackspace(field)) {
                e.preventDefault();
            }
        } else if (e.key === ' ') {
            // Space finalizes current composition and resets IME
            // Let the browser handle the actual space insertion naturally
            if (ime.isEnabled() && ime.hasComposition) {
                if (ime.debug) {
                    console.log('[HangulIme] Space key detected, finalizing composition');
                }
                ime.reset();
                // Don't preventDefault - let browser insert space naturally
            }
        } else if (e.key === 'ArrowLeft' || e.key === 'ArrowRight' || 
                   e.key === 'ArrowUp' || e.key === 'ArrowDown' ||
                   e.key === 'Home' || e.key === 'End') {
            // Reset IME on cursor movement
            ime.reset();
        }
    });
    
    document.addEventListener('keypress', (e) => {
        const field = e.target;
        if (!field.matches(fieldSelector)) return;
        
        if (ime.handleKeyPress(e, field)) {
            e.preventDefault();
        }
    });
    
    // Reset on mouse click (cursor position change)
    document.addEventListener('mousedown', (e) => {
        if (e.target.matches(fieldSelector)) {
            setTimeout(() => ime.reset(), 0);
        }
    });
    
    // Commit composition on blur (focus loss)
    // Use focusout with event delegation to catch all matching fields
    document.addEventListener('focusout', (e) => {
        if (e.target.matches(fieldSelector)) {
            if (ime.isEnabled() && ime.hasComposition) {
                if (ime.debug) {
                    console.log('[HangulIme] Focus lost, committing composition');
                }
                // Commit finalizes the current syllable and resets state
                ime.commit(e.target);
            }
        }
    });
    
    return ime;
}
