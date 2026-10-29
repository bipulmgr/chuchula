import * as fs from 'node:fs';
import * as path from 'node:path';

/** JSON with sorted object keys (same as canonical() in the Dart test). */
export function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (v !== null && typeof v === 'object') {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).sort().map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`).join(',')}}`;
  }
  return JSON.stringify(v);
}

/** 32-bit FNV-1a over UTF-16 code units (same as fnv() in Dart). */
export function fnv(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

export function loadFixtures(): any {
  const file = path.join(__dirname, '..', '..', 'test-fixtures', 'parity.json');
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
