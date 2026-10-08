import "@testing-library/jest-dom/vitest";
import { vi } from "vitest";

// Node's experimental localStorage (enabled via a --localstorage-file flag in
// the outer shell) can shadow jsdom's Storage with an object that has no
// getItem/setItem. Modules that read tokens at import time
// (src/stores/authAtom.ts) then fail to load. Restore an in-memory Storage
// when that happens; jsdom's working implementation is left untouched.
if (typeof globalThis.localStorage?.getItem !== "function") {
  const store = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => void store.set(key, String(value)),
    removeItem: (key: string) => void store.delete(key),
    clear: () => store.clear(),
    key: (index: number) => [...store.keys()][index] ?? null,
    get length() {
      return store.size;
    },
  });
}
