// localStorage mirror of what the iOS app persists: settings.json, availability-cache.json, loans.json
// and the Keychain credentials. Every access is guarded: private mode or blocked storage just means no cache.
import type { Book, Loan, SearchResult, Settings } from "./models";
import { defaultSettings } from "./models";

const PREFIX = "zahori.";

function load<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

function save(key: string, value: unknown) {
  try {
    localStorage.setItem(PREFIX + key, JSON.stringify(value));
  } catch {
    /* storage full or blocked: keep working without persistence */
  }
}

function remove(key: string) {
  try {
    localStorage.removeItem(PREFIX + key);
  } catch {
    /* ignore */
  }
}

// --- Settings (missing keys fall back to defaults, like AppSettings.init(from:)) ---

export const loadSettings = (): Settings => ({ ...defaultSettings(), ...(load<Partial<Settings>>("settings") ?? {}) });
export const saveSettings = (s: Settings) => save("settings", s);

// --- Availability cache: last good result per book + the shelf, with ISO timestamps ---

export interface CacheEntry {
  result: SearchResult;
  checkedAt: string;
}

export interface CachedShelf {
  userID: string;
  shelf: string;
  userName: string | null;
  books: Book[];
  fetchedAt: string;
}

interface Snapshot {
  entries: Record<string, CacheEntry>;
  shelf: CachedShelf | null;
}

let snapshot: Snapshot = load<Snapshot>("availability-cache") ?? { entries: {}, shelf: null };
const persist = () => save("availability-cache", snapshot);

export const cache = {
  /** A good answer (found / no results) replaces the entry; "catalog unavailable" falls back to the last good one. */
  record(result: SearchResult, bookID: string): { result: SearchResult; cachedAt: string | null } {
    const kind = result.outcome.kind;
    if (kind === "found" || kind === "noResults") {
      snapshot.entries[bookID] = { result, checkedAt: new Date().toISOString() };
      persist();
      return { result, cachedAt: null };
    }
    const cached = snapshot.entries[bookID];
    return cached ? { result: cached.result, cachedAt: cached.checkedAt } : { result, cachedAt: null };
  },
  entries: () => snapshot.entries,
  saveShelf(shelf: CachedShelf) {
    snapshot.shelf = shelf;
    persist();
  },
  shelf: () => snapshot.shelf,
  clear() {
    snapshot = { entries: {}, shelf: null };
    remove("availability-cache");
  },
};

// --- Loans ---

export interface CachedLoans {
  loans: Loan[];
  fetchedAt: string;
}

export const loadLoans = () => load<CachedLoans>("loans");
export const saveLoans = (c: CachedLoans) => save("loans", c);
export const deleteLoans = () => remove("loans");

// --- Reader credentials (iOS: Keychain). Plain localStorage on this device; saved only after a successful login. ---

export interface Credentials {
  card: string;
  password: string;
}

export const loadCredentials = () => load<Credentials>("credentials");
export const saveCredentials = (c: Credentials) => save("credentials", c);
export const deleteCredentials = () => remove("credentials");

// --- One-off flags ---

export const flag = {
  get: (name: string) => load<boolean>(`flag.${name}`) === true,
  set: (name: string) => save(`flag.${name}`, true),
};
