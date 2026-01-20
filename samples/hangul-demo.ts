/**
 * hangul-wasm Bun/TypeScript Demo
 * 
 * Run with: bun samples/hangul-demo.ts
 */

// Load WASM module
const wasmBuffer = await Bun.file('./hangul.wasm').arrayBuffer();
const { instance } = await WebAssembly.instantiate(wasmBuffer);

// Type definitions for WASM exports
interface HangulWasm {
  memory: WebAssembly.Memory;
  wasm_alloc(size: number): number;
  wasm_free(ptr: number, size: number): void;
  wasm_isHangulSyllable(codepoint: number): boolean;
  wasm_decompose(syllable: number, outputPtr: number): boolean;
  wasm_compose(initial: number, medial: number, final: number): number;
  wasm_hasFinal(syllable: number): boolean;
  wasm_getInitial(syllable: number): number;
  wasm_getMedial(syllable: number): number;
  wasm_getFinal(syllable: number): number;
}

const hangul = instance.exports as unknown as HangulWasm;

// Helper function to decompose a syllable
function decompose(char: string): { initial: string; medial: string; final: string } | null {
  const codepoint = char.codePointAt(0);
  if (!codepoint || !hangul.wasm_isHangulSyllable(codepoint)) {
    return null;
  }

  const bufPtr = hangul.wasm_alloc(12); // 3 x u32
  if (bufPtr === 0) {
    throw new Error('WASM allocation failed');
  }

  try {
    if (!hangul.wasm_decompose(codepoint, bufPtr)) {
      return null;
    }

    const memory = new Uint32Array(hangul.memory.buffer);
    const offset = bufPtr / 4;

    return {
      initial: String.fromCodePoint(memory[offset]),
      medial: String.fromCodePoint(memory[offset + 1]),
      final: memory[offset + 2] !== 0 ? String.fromCodePoint(memory[offset + 2]) : '',
    };
  } finally {
    hangul.wasm_free(bufPtr, 12);
  }
}

// Helper function to compose jamo into syllable
function compose(initial: string, medial: string, final?: string): string | null {
  const initialCode = initial.codePointAt(0) ?? 0;
  const medialCode = medial.codePointAt(0) ?? 0;
  const finalCode = final?.codePointAt(0) ?? 0;

  const result = hangul.wasm_compose(initialCode, medialCode, finalCode);
  return result !== 0 ? String.fromCodePoint(result) : null;
}

// ============================================================================
// Demo
// ============================================================================

console.log('='.repeat(50));
console.log('hangul-wasm Bun/TypeScript Demo');
console.log('='.repeat(50));
console.log();

// Test 1: Check Hangul syllables
console.log('1. Hangul Syllable Detection');
console.log('-'.repeat(30));
const testChars = ['한', '글', 'A', '1', '가', '힣'];
for (const char of testChars) {
  const code = char.codePointAt(0)!;
  const isHangul = hangul.wasm_isHangulSyllable(code);
  console.log(`   '${char}' (U+${code.toString(16).toUpperCase().padStart(4, '0')}): ${isHangul ? 'Yes' : 'No'}`);
}
console.log();

// Test 2: Decompose syllables
console.log('2. Syllable Decomposition');
console.log('-'.repeat(30));
const syllables = ['한', '글', '을', '입', '력', '할'];
for (const syllable of syllables) {
  const jamo = decompose(syllable);
  if (jamo) {
    const finalDisplay = jamo.final || '(none)';
    console.log(`   '${syllable}' → 초성: ${jamo.initial}, 중성: ${jamo.medial}, 종성: ${finalDisplay}`);
  }
}
console.log();

// Test 3: Compose syllables
console.log('3. Syllable Composition');
console.log('-'.repeat(30));
const compositions: [string, string, string?][] = [
  ['ㄱ', 'ㅏ'],           // 가
  ['ㅎ', 'ㅏ', 'ㄴ'],      // 한
  ['ㄱ', 'ㅡ', 'ㄹ'],      // 글
  ['ㅇ', 'ㅣ', 'ㅂ'],      // 입
];
for (const [initial, medial, final] of compositions) {
  const result = compose(initial, medial, final);
  const finalDisplay = final || '(none)';
  console.log(`   ${initial} + ${medial} + ${finalDisplay} → '${result}'`);
}
console.log();

// Test 4: Check final consonants
console.log('4. Final Consonant (받침) Detection');
console.log('-'.repeat(30));
const finalTestChars = ['가', '간', '하', '한', '을'];
for (const char of finalTestChars) {
  const code = char.codePointAt(0)!;
  const hasFinal = hangul.wasm_hasFinal(code);
  console.log(`   '${char}': ${hasFinal ? 'Has 받침' : 'No 받침'}`);
}
console.log();

// Test 5: Full string decomposition
console.log('5. String Decomposition');
console.log('-'.repeat(30));
const testString = '한글을 입력할';
console.log(`   Input: "${testString}"`);
let decomposed = '';
for (const char of testString) {
  const jamo = decompose(char);
  if (jamo) {
    decomposed += jamo.initial + jamo.medial + jamo.final;
  } else {
    decomposed += char; // Keep non-Hangul as-is (e.g., space)
  }
}
console.log(`   Output: "${decomposed}"`);
console.log();

console.log('='.repeat(50));
console.log('Demo complete!');
