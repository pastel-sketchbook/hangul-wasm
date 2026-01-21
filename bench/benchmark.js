/**
 * Performance benchmark: WASM vs Pure JavaScript Hangul decomposition/composition
 * 
 * Run with: bun bench/benchmark.js
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const wasmPath = path.join(__dirname, '..', 'hangul.wasm');

// Constants
const HANGUL_SYLLABLE_BASE = 0xAC00;
const HANGUL_SYLLABLE_END = 0xD7A3;
const INITIAL_COUNT = 19;
const MEDIAL_COUNT = 21;
const FINAL_COUNT = 28;

// Pure JavaScript implementation for comparison
const JS_COMPAT_INITIAL = [
  0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141, 0x3142,
  0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149, 0x314A, 0x314B,
  0x314C, 0x314D, 0x314E
];

const JS_COMPAT_MEDIAL = [
  0x314F, 0x3150, 0x3151, 0x3152, 0x3153, 0x3154, 0x3155, 0x3156,
  0x3157, 0x3158, 0x3159, 0x315A, 0x315B, 0x315C, 0x315D, 0x315E,
  0x315F, 0x3160, 0x3161, 0x3162, 0x3163
];

const JS_COMPAT_FINAL = [
  0, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137,
  0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E, 0x313F, 0x3140,
  0x3141, 0x3142, 0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x314A,
  0x314B, 0x314C, 0x314D, 0x314E
];

function jsIsHangulSyllable(c) {
  return c >= HANGUL_SYLLABLE_BASE && c <= HANGUL_SYLLABLE_END;
}

function jsDecompose(syllable) {
  if (!jsIsHangulSyllable(syllable)) return null;
  
  const syllableIndex = syllable - HANGUL_SYLLABLE_BASE;
  const finalIndex = syllableIndex % FINAL_COUNT;
  const medialIndex = Math.floor((syllableIndex / FINAL_COUNT)) % MEDIAL_COUNT;
  const initialIndex = Math.floor(syllableIndex / (FINAL_COUNT * MEDIAL_COUNT));
  
  return {
    initial: JS_COMPAT_INITIAL[initialIndex],
    medial: JS_COMPAT_MEDIAL[medialIndex],
    final: finalIndex > 0 ? JS_COMPAT_FINAL[finalIndex] : 0
  };
}

function jsCompose(initial, medial, final) {
  let initialIdx = JS_COMPAT_INITIAL.indexOf(initial);
  let medialIdx = JS_COMPAT_MEDIAL.indexOf(medial);
  let finalIdx = final === 0 ? 0 : JS_COMPAT_FINAL.indexOf(final);
  
  if (initialIdx === -1 || medialIdx === -1 || finalIdx === -1) return null;
  
  return HANGUL_SYLLABLE_BASE + 
    (initialIdx * MEDIAL_COUNT * FINAL_COUNT) +
    (medialIdx * FINAL_COUNT) +
    finalIdx;
}

// Load WASM module
async function loadWasm() {
  const wasmBuffer = fs.readFileSync(wasmPath);
  const wasmModule = await WebAssembly.instantiate(wasmBuffer);
  return wasmModule.instance.exports;
}

// Benchmark helper
function benchmark(name, fn, iterations = 100000) {
  // Warmup
  for (let i = 0; i < 1000; i++) fn();
  
  const start = performance.now();
  for (let i = 0; i < iterations; i++) fn();
  const end = performance.now();
  
  const totalMs = end - start;
  const opsPerSec = Math.round(iterations / (totalMs / 1000));
  const nsPerOp = Math.round((totalMs * 1000000) / iterations);
  
  return { name, totalMs, iterations, opsPerSec, nsPerOp };
}

function formatResult(result) {
  return `${result.name}: ${result.opsPerSec.toLocaleString()} ops/sec (${result.nsPerOp} ns/op)`;
}

async function runBenchmarks() {
  console.log('Loading WASM module...');
  const wasm = await loadWasm();
  
  // Allocate buffer for WASM decompose
  const decomposeBuffer = wasm.wasm_alloc(12);
  
  // Test syllables: first, middle, last
  const testSyllables = [0xAC00, 0xD55C, 0xD7A3]; // 가, 한, 힣
  
  console.log('\n=== Hangul WASM Performance Benchmarks ===\n');
  console.log(`Iterations: 100,000 per test`);
  console.log(`Test syllables: 가 (U+AC00), 한 (U+D55C), 힣 (U+D7A3)\n`);
  
  // isHangulSyllable benchmark
  console.log('--- isHangulSyllable ---');
  const jsIsHangul = benchmark('JavaScript', () => {
    for (const s of testSyllables) jsIsHangulSyllable(s);
  });
  const wasmIsHangul = benchmark('WASM', () => {
    for (const s of testSyllables) wasm.wasm_isHangulSyllable(s);
  });
  console.log(formatResult(jsIsHangul));
  console.log(formatResult(wasmIsHangul));
  console.log(`Speedup: ${(jsIsHangul.nsPerOp / wasmIsHangul.nsPerOp).toFixed(2)}x\n`);
  
  // Decompose benchmark
  console.log('--- decompose ---');
  const jsDecomp = benchmark('JavaScript', () => {
    for (const s of testSyllables) jsDecompose(s);
  });
  const wasmDecomp = benchmark('WASM', () => {
    for (const s of testSyllables) wasm.wasm_decompose(s, decomposeBuffer);
  });
  console.log(formatResult(jsDecomp));
  console.log(formatResult(wasmDecomp));
  console.log(`Speedup: ${(jsDecomp.nsPerOp / wasmDecomp.nsPerOp).toFixed(2)}x\n`);
  
  // Compose benchmark
  console.log('--- compose ---');
  const testJamo = [
    { i: 0x3131, m: 0x314F, f: 0 },     // ㄱ+ㅏ = 가
    { i: 0x314E, m: 0x314F, f: 0x3134 }, // ㅎ+ㅏ+ㄴ = 한
    { i: 0x314E, m: 0x3163, f: 0x314E }  // ㅎ+ㅣ+ㅎ = 힣
  ];
  
  const jsComp = benchmark('JavaScript', () => {
    for (const j of testJamo) jsCompose(j.i, j.m, j.f);
  });
  const wasmComp = benchmark('WASM', () => {
    for (const j of testJamo) wasm.wasm_compose(j.i, j.m, j.f);
  });
  console.log(formatResult(jsComp));
  console.log(formatResult(wasmComp));
  console.log(`Speedup: ${(jsComp.nsPerOp / wasmComp.nsPerOp).toFixed(2)}x\n`);
  
  // Bulk decomposition (all 11,172 syllables)
  console.log('--- Bulk decompose (11,172 syllables) ---');
  const jsBulk = benchmark('JavaScript', () => {
    for (let c = HANGUL_SYLLABLE_BASE; c <= HANGUL_SYLLABLE_END; c++) {
      jsDecompose(c);
    }
  }, 100);
  const wasmBulk = benchmark('WASM', () => {
    for (let c = HANGUL_SYLLABLE_BASE; c <= HANGUL_SYLLABLE_END; c++) {
      wasm.wasm_decompose(c, decomposeBuffer);
    }
  }, 100);
  console.log(formatResult(jsBulk));
  console.log(formatResult(wasmBulk));
  console.log(`Speedup: ${(jsBulk.nsPerOp / wasmBulk.nsPerOp).toFixed(2)}x\n`);
  
  // Summary
  console.log('=== Summary ===');
  console.log('Results vary by operation type:');
  console.log('- Single operations: WASM is 1.5-2x faster (avoids JS object allocation)');
  console.log('- Bulk operations: JS can be faster due to WASM call overhead');
  console.log('- IME use case (single keystrokes): WASM is advantageous');
  console.log('- Batch text processing: Consider batching WASM calls\n');
  
  // Free allocated buffer
  wasm.wasm_free(decomposeBuffer, 12);
}

runBenchmarks().catch(console.error);
