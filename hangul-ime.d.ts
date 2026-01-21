/**
 * hangul-wasm - High-performance Korean Hangul text processing library
 * TypeScript type definitions
 */

/**
 * IME state representing the current composition
 */
export interface ImeState {
  /** Initial consonant (초성) index */
  initial: number;
  /** Initial consonant composition flag */
  initial_flag: number;
  /** Medial vowel (중성) index */
  medial: number;
  /** Medial vowel composition flag */
  medial_flag: number;
  /** Final consonant (종성) index */
  final: number;
  /** Final consonant composition flag */
  final_flag: number;
}

/**
 * Keyboard layout mode
 */
export type LayoutMode = '2bulsik' | '3bulsik';

/**
 * Options for HangulIme constructor
 */
export interface HangulImeOptions {
  /** Enable debug logging (default: false) */
  debug?: boolean;
  /** Keyboard layout mode (default: '2bulsik') */
  layout?: LayoutMode;
}

/**
 * WebAssembly module with hangul.wasm exports
 */
export interface HangulWasmModule {
  instance: {
    exports: HangulWasmExports;
  };
}

/**
 * WASM function exports
 */
export interface HangulWasmExports {
  memory: WebAssembly.Memory;
  
  // Memory management
  wasm_alloc(size: number): number;
  wasm_free(ptr: number, size: number): void;
  
  // Core decomposition/composition
  wasm_decompose(syllable: number, output_ptr: number): boolean;
  wasm_decompose_safe(syllable: number, output_ptr: number, output_size: number): boolean;
  wasm_compose(initial: number, medial: number, final: number): number;
  wasm_hasFinal(syllable: number): boolean;
  wasm_isHangulSyllable(char: number): boolean;
  
  // Jamo classification
  /** Check if codepoint is a compatibility jamo (consonant or vowel) */
  wasm_isJamo(char: number): boolean;
  /** Check if codepoint is a consonant (초성/종성) */
  wasm_isConsonant(char: number): boolean;
  /** Check if codepoint is a vowel (중성) */
  wasm_isVowel(char: number): boolean;
  /** Check if codepoint is a double consonant (ㄲ, ㄸ, ㅃ, ㅆ, ㅉ) */
  wasm_isDoubleConsonant(char: number): boolean;
  /** Check if codepoint is a double vowel (ㅘ, ㅙ, ㅚ, ㅝ, ㅞ, ㅟ, ㅢ) */
  wasm_isDoubleVowel(char: number): boolean;
  
  // String processing
  /** Decompose UTF-8 string into jamo codepoints */
  wasm_decomposeString(input_ptr: number, input_len: number, output_ptr: number): number;
  /** Compose jamo codepoints back into Hangul syllables */
  wasm_composeString(input_ptr: number, input_len: number, output_ptr: number): number;
  
  // IME functions
  wasm_ime_create(): number;
  wasm_ime_destroy(handle: number): void;
  wasm_ime_reset(handle: number): void;
  /** Process keystroke in 2-Bulsik mode */
  wasm_ime_processKey(handle: number, jamo_index: number, result_ptr: number): boolean;
  /** Process keystroke in 3-Bulsik mode */
  wasm_ime_processKey3(handle: number, ascii: number, result_ptr: number): boolean;
  wasm_ime_backspace(handle: number): number;
  wasm_ime_getState(handle: number, state_ptr: number): void;
  /** Commit current composition and reset state. Returns finalized codepoint (0 if empty). */
  wasm_ime_commit(handle: number): number;
}

/**
 * Korean Input Method Editor using hangul.wasm
 * 
 * @example
 * ```typescript
 * const wasmModule = await WebAssembly.instantiateStreaming(fetch('./hangul.wasm'));
 * const ime = new HangulIme(wasmModule);
 * ime.enable();
 * ```
 */
export declare class HangulIme {
  /**
   * Create a new HangulIme instance
   * @param wasmModule - The loaded WebAssembly module
   * @param options - Configuration options
   * @throws Error if WASM allocation fails
   */
  constructor(wasmModule: HangulWasmModule, options?: HangulImeOptions);
  
  /**
   * Clean up WASM resources
   * Call this when done with the IME
   */
  destroy(): void;
  
  /**
   * Enable the IME for Korean input
   */
  enable(): void;
  
  /**
   * Disable the IME (pass-through to browser)
   */
  disable(): void;
  
  /**
   * Check if IME is currently enabled
   */
  isEnabled(): boolean;
  
  /**
   * Enable or disable debug logging
   */
  setDebug(enabled: boolean): void;
  
  /**
   * Check if debug mode is enabled
   */
  isDebugEnabled(): boolean;
  
  /**
   * Set the keyboard layout mode
   * @param mode - '2bulsik' or '3bulsik'
   */
  setLayoutMode(mode: LayoutMode): void;
  
  /**
   * Get the current keyboard layout mode
   */
  getLayoutMode(): LayoutMode;
  
  /**
   * Reset the IME state (clears current composition)
   */
  reset(): void;
  
  /**
   * Handle a keyboard event
   * @param event - The keyboard event
   * @param field - The input field element
   * @returns true if event was handled and should be prevented
   */
  handleKeyPress(event: KeyboardEvent, field: HTMLInputElement | HTMLTextAreaElement): boolean;
  
  /**
   * Handle backspace key
   * @param field - The input field element
   * @returns true if event was handled and should be prevented
   */
  handleBackspace(field: HTMLInputElement | HTMLTextAreaElement): boolean;
  
  /**
   * Get the current IME composition state
   */
  getState(): ImeState;
  
  /** Whether there's an active composition */
  hasComposition: boolean;
  
  /** Position where current composition started */
  compositionStart: number;
  
  /** Keys pressed in current composition */
  keySequence: string[];
}

/**
 * Setup IME on input fields with automatic event handling
 * 
 * @param wasmModule - The loaded WebAssembly module
 * @param fieldSelector - CSS selector for input fields (default: 'input[type="text"], textarea')
 * @returns The configured HangulIme instance
 * 
 * @example
 * ```typescript
 * const wasmModule = await WebAssembly.instantiateStreaming(fetch('./hangul.wasm'));
 * const ime = setupIme(wasmModule);
 * ime.enable();
 * ```
 */
export declare function setupIme(
  wasmModule: HangulWasmModule,
  fieldSelector?: string
): HangulIme;

/**
 * 2-Bulsik (Dubeolsik) keyboard layout mapping
 * Maps ASCII characters to jamo indices
 */
export declare const LAYOUT_2BULSIK: Record<string, number>;
