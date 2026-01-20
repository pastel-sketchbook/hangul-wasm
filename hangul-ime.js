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

const ACTION_NO_CHANGE = 0;
const ACTION_REPLACE = 1;
const ACTION_EMIT_AND_NEW = 2;

// Debug flag - set to true to enable console logging
let DEBUG = false;

export class HangulIme {
    constructor(wasmModule, options = {}) {
        this.wasm = wasmModule.instance.exports;
        this.memory = wasmModule.instance.exports.memory;
        this.handle = this.wasm.wasm_ime_create();
        this.enabled = false;
        this.spaceJustPressed = false; // Flag to prevent keypress after space
        this.hasComposition = false; // Track if there's an active composition
        this.keySequence = []; // Track keys pressed for current syllable
        this.debug = options.debug !== undefined ? options.debug : DEBUG;
        
        // Allocate result buffer once (reusable)
        this.resultBuffer = this.wasm.wasm_alloc(12); // 3 × u32
        
        if (this.handle === 0 || this.resultBuffer === 0) {
            throw new Error('Failed to initialize IME (WASM allocation failed)');
        }
    }
    
    destroy() {
        if (this.resultBuffer !== 0) {
            this.wasm.wasm_free(this.resultBuffer, 12);
            this.resultBuffer = 0;
        }
        if (this.handle !== 0) {
            this.wasm.wasm_ime_destroy(this.handle);
            this.handle = 0;
        }
    }
    
    enable() {
        this.enabled = true;
        this.reset();
        // this.updateOverlay(); // DISABLED
    }
    
    disable() {
        this.enabled = false;
        this.reset();
        // this.hideOverlay(); // DISABLED
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
        this.keySequence = [];
        // this.updateOverlay(); // DISABLED
    }
    
    updateOverlay() {
        const overlay = document.getElementById('compositionOverlay');
        const keysDisplay = document.getElementById('keysPressed');
        const compositionDisplay = document.getElementById('currentComposition');
        
        if (!overlay) return;
        
        if (this.enabled && this.keySequence.length > 0) {
            overlay.style.display = 'block';
            keysDisplay.textContent = this.keySequence.join(' + ');
            
            // Get current composition from WASM
            const state = this.getState();
            const composition = this.stateToString(state);
            compositionDisplay.textContent = composition || '—';
        } else if (this.enabled) {
            overlay.style.display = 'block';
            keysDisplay.textContent = '—';
            compositionDisplay.textContent = '—';
        } else {
            overlay.style.display = 'none';
        }
    }
    
    hideOverlay() {
        const overlay = document.getElementById('compositionOverlay');
        if (overlay) overlay.style.display = 'none';
    }
    
    stateToString(state) {
        // Convert state to displayable characters
        let result = '';
        if (state.initial !== 0) {
            result += String.fromCodePoint(0x3130 + state.initial);
        }
        if (state.medial !== 0) {
            result += String.fromCodePoint(0x3130 + state.medial);
        }
        if (state.final !== 0) {
            result += String.fromCodePoint(0x3130 + state.final);
        }
        return result;
    }
    
    /**
     * Handle a key press event
     * @param {KeyboardEvent} event - The keyboard event
     * @param {HTMLInputElement|HTMLTextAreaElement} field - The input field
     * @returns {boolean} - true if event was handled (and should be prevented)
     */
    handleKeyPress(event, field) {
        if (!this.enabled) return false;
        
        // Skip space keypress event if we already handled it in keydown
        if (this.spaceJustPressed && event.key === ' ') {
            this.spaceJustPressed = false;
            if (this.debug) {
                console.log('[HangulIme] Skipping space keypress handler (already handled in keydown)');
            }
            return true; // Prevent this event
        }
        
        // Clear the flag if any other key was pressed
        if (this.spaceJustPressed) {
            this.spaceJustPressed = false;
        }
        
        // Only handle printable single characters
        if (event.key.length !== 1) return false;
        
        const char = event.key;
        const jamoIndex = LAYOUT_2BULSIK[char];
        
        if (this.debug) {
            console.log(`[HangulIme] Key pressed: '${char}' → jamo index: ${jamoIndex}`);
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
        
        if (this.debug) {
            console.log(`[HangulIme]   → WASM result: action=${action}, prev=U+${prevCodepoint.toString(16).toUpperCase().padStart(4, '0')}, current=U+${currentCodepoint.toString(16).toUpperCase().padStart(4, '0')} (${String.fromCodePoint(currentCodepoint)})`);
        }        
        // Track key sequence
        if (action === ACTION_EMIT_AND_NEW) {
            // Starting new syllable, reset sequence
            this.keySequence = [char];
        } else {
            // Continuing current syllable
            this.keySequence.push(char);
        }
        
        switch (action) {
            case ACTION_REPLACE:
                // Replace the last character with the new composition
                // Only replace if we have an active composition, otherwise insert
                if (this.hasComposition) {
                    this.replaceLastChar(field, currentCodepoint);
                } else {
                    this.insertChar(field, currentCodepoint);
                }
                this.hasComposition = true;
                break;
                
            case ACTION_EMIT_AND_NEW:
                // Emit the previous syllable (replace current char with prev)
                // Then insert the new syllable
                if (prevCodepoint !== 0) {
                    // Replace the current character (엉) with the emitted one (어)
                    this.replaceLastChar(field, prevCodepoint);
                }
                // Then insert the new character (요)
                this.insertChar(field, currentCodepoint);
                this.hasComposition = true;
                break;
                
            case ACTION_NO_CHANGE:
            default:
                // Do nothing
                break;
        }
        
        // Update overlay with current composition
        // this.updateOverlay(); // DISABLED
        
        return true; // Event was handled
    }
    
    /**
     * Handle backspace key
     * @param {HTMLInputElement|HTMLTextAreaElement} field - The input field
     * @returns {boolean} - true if event was handled (and should be prevented)
     */
    handleBackspace(field) {
        if (!this.enabled) return false;
        
        const newCodepoint = this.wasm.wasm_ime_backspace(this.handle);
        
        if (newCodepoint !== 0) {
            // Replace last character with decomposed version
            this.replaceLastChar(field, newCodepoint);
            
            // Remove last key from sequence
            if (this.keySequence.length > 0) {
                this.keySequence.pop();
            }
            // this.updateOverlay(); // DISABLED
            
            return true;
        }
        
        // newCodepoint === 0: IME state is empty, let browser handle normally
        this.keySequence = [];
        // this.updateOverlay(); // DISABLED
        return false;
    }
    
    /**
     * Insert a character at the cursor position
     */
    insertChar(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const start = field.selectionStart;
        const end = field.selectionEnd;
        
        field.value = 
            field.value.slice(0, start) + 
            char + 
            field.value.slice(end);
        
        field.selectionStart = field.selectionEnd = start + char.length;
    }
    
    /**
     * Replace the last character at the cursor position
     */
    replaceLastChar(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const start = field.selectionStart;
        
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
            if (ime.isEnabled()) {
                if (ime.debug) {
                    console.log('[HangulIme] Space key detected, resetting IME and inserting space');
                }
                ime.reset();
                ime.spaceJustPressed = true; // Set flag to skip keypress handler
                // Manually insert space since we need to handle it
                const field = e.target;
                const start = field.selectionStart;
                const end = field.selectionEnd;
                field.value = field.value.slice(0, start) + ' ' + field.value.slice(end);
                field.selectionStart = field.selectionEnd = start + 1;
                e.preventDefault(); // Prevent default space handling
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
    
    return ime;
}
