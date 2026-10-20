// App state and actions. Port of ios/Zahori/AppModel.swift + LoansModel.swift + LocationProvider.swift.
import { useSyncExternalStore } from "react";
import * as api from "./core/api";
import { summarize, type Availability } from "./core/availability";
import { userIDFrom, userNameFrom } from "./core/goodreads";
import type { Book, Loan, SearchResult, Settings } from "./core/models";
import { MADRID_CENTER, type Coordinate, type Proximity, type ReferencePoint } from "./core/proximity";
import * as storage from "./core/storage";

export interface BookCheck {
  phase: "pending" | "checking" | "checked";
  result?: SearchResult;
  /** Set when `result` comes from the cache because the catalog could not be reached. */
  cachedAt?: string | null;
}

export interface State {
  settings: Settings;
  // Shelf
  books: Book[];
  checks: Record<string, BookCheck>;
  isLoadingShelf: boolean;
  shelfError: string | null;
  shelfCachedAt: string | null;
  // Batch
  isCheckingBatch: boolean;
  batchCompleted: number;
  batchTotal: number;
  // Recomendaciones
  recommendationIDs: string[];
  isFindingRecommendations: boolean;
  recommendationsSearched: boolean;
  // Direct search
  searchResult: SearchResult | null;
  isSearching: boolean;
  // Location (iOS LocationProvider)
  coordinate: Coordinate | null;
  locationDenied: boolean;
  // Loans (iOS LoansModel)
  loans: Loan[];
  loansFetchedAt: string | null;
  loansLoading: boolean;
  loansShowingCache: boolean;
  loansError: string | null;
  hasCredentials: boolean;
}

const cachedLoans = storage.loadLoans();

let state: State = {
  settings: storage.loadSettings(),
  books: [],
  checks: {},
  isLoadingShelf: false,
  shelfError: null,
  shelfCachedAt: null,
  isCheckingBatch: false,
  batchCompleted: 0,
  batchTotal: 0,
  recommendationIDs: [],
  isFindingRecommendations: false,
  recommendationsSearched: false,
  searchResult: null,
  isSearching: false,
  coordinate: null,
  locationDenied: false,
  loans: cachedLoans?.loans ?? [],
  loansFetchedAt: cachedLoans?.fetchedAt ?? null,
  loansLoading: false,
  loansShowingCache: false,
  loansError: null,
  hasCredentials: storage.loadCredentials() != null,
};

const listeners = new Set<() => void>();

function set(patch: Partial<State> | ((s: State) => Partial<State>)) {
  const p = typeof patch === "function" ? patch(state) : patch;
  const next = { ...state, ...p };
  if (p.settings && p.settings !== state.settings) storage.saveSettings(p.settings);
  state = next;
  listeners.forEach((l) => l());
}

export function useStore(): State {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => state,
  );
}

export const getState = () => state;

// MARK: - Derived

/** Where distances are measured from when no library is selected. */
export function origin(s: State): ReferencePoint {
  return s.coordinate
    ? { name: "tu ubicación", coordinate: s.coordinate }
    : { name: "el centro de Madrid", coordinate: MADRID_CENTER };
}

export function proximity(s: State): Proximity {
  return {
    selectedLibraries: s.settings.selectedLibraryIDs,
    radiusKm: s.settings.radiusKm,
    fallbackOrigin: s.settings.selectedLibraryIDs.length === 0 ? origin(s) : null,
  };
}

export function availability(s: State, book: Book): Availability | null {
  const r = s.checks[book.bookID]?.result;
  return r ? summarize(r, proximity(s)) : null;
}

export const availableCount = (s: State) => s.books.filter((b) => availability(s, b)?.state === "available").length;

export const recommendedBooks = (s: State) =>
  s.recommendationIDs.flatMap((id) => s.books.filter((b) => b.bookID === id));

// MARK: - Settings

export function updateSettings(patch: Partial<Settings>) {
  set((s) => ({ settings: { ...s.settings, ...patch } }));
}

export function toggleLibrary(id: string) {
  const ids = state.settings.selectedLibraryIDs;
  updateSettings({ selectedLibraryIDs: ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id] });
}

// MARK: - Location

/** iOS asks on first launch when no library is selected; Safari would ask again on every launch, so
 *  the web asks once and afterwards only reads the position when permission is already granted. */
export async function requestLocationIfNeeded(userInitiated = false) {
  if (!("geolocation" in navigator)) return set({ locationDenied: true });
  let permission: PermissionState | null = null;
  try {
    permission = (await navigator.permissions?.query({ name: "geolocation" }))?.state ?? null;
  } catch {
    /* Permissions API unavailable: decide from the flag below */
  }
  if (permission === "denied") return set({ locationDenied: true });
  if (permission !== "granted" && !userInitiated && storage.flag.get("location-asked")) return;
  storage.flag.set("location-asked");
  navigator.geolocation.getCurrentPosition(
    (pos) => set({ coordinate: { lat: pos.coords.latitude, lon: pos.coords.longitude }, locationDenied: false }),
    (err) => {
      if (err.code === err.PERMISSION_DENIED) set({ locationDenied: true });
    },
    { enableHighAccuracy: false, maximumAge: 10 * 60_000, timeout: 15_000 },
  );
}

// MARK: - Goodreads

export async function connect(rawInput: string, rawShelf: string) {
  const input = rawInput.trim();
  const shelf = rawShelf.trim() || "to-read";
  if (!input) return set({ shelfError: "Por favor, introduzca su ID de usuario o enlace de perfil de Goodreads." });
  const userID = userIDFrom(input);
  if (!userID) return set({ shelfError: "No se pudo extraer un ID de usuario de Goodreads válido." });
  updateSettings({
    goodreadsUserID: userID,
    goodreadsUserName: userNameFrom(input) ?? state.settings.goodreadsUserName,
    shelf,
  });
  await loadShelf(input);
}

export function disconnect() {
  updateSettings({ goodreadsUserID: null, goodreadsUserName: null, shelf: "to-read" });
  set({
    books: [],
    checks: {},
    recommendationIDs: [],
    recommendationsSearched: false,
    shelfError: null,
    shelfCachedAt: null,
  });
  storage.cache.clear();
}

export async function reloadShelf() {
  const id = state.settings.goodreadsUserID;
  if (id) await loadShelf(id);
}

/** Shows the cached shelf immediately on launch, then refreshes from Goodreads. */
export async function restore() {
  const { goodreadsUserID: userID, shelf } = state.settings;
  if (!userID) return;
  const cached = storage.cache.shelf();
  if (cached && cached.userID === userID && cached.shelf === shelf) {
    set({ books: cached.books });
    applyCachedChecks();
  }
  await loadShelf(userID);
}

async function loadShelf(userInput: string) {
  set({ isLoadingShelf: true, shelfError: null });
  try {
    const result = await api.fetchShelf(userInput, state.settings.shelf);
    const name = result.userName ?? userNameFrom(userInput);
    if (name) updateSettings({ goodreadsUserName: name });
    const ids = new Set(result.books.map((b) => b.bookID));
    set((s) => ({
      shelfCachedAt: null,
      books: result.books,
      checks: Object.fromEntries(Object.entries(s.checks).filter(([id]) => ids.has(id))),
    }));
    applyCachedChecks();
    storage.cache.saveShelf({
      userID: result.userID,
      shelf: result.shelf,
      userName: state.settings.goodreadsUserName,
      books: result.books,
      fetchedAt: new Date().toISOString(),
    });
    if (result.books.length === 0) {
      set({
        shelfError: `No se encontraron libros en la estantería '${state.settings.shelf}'. Verifique que sea pública y contenga libros.`,
      });
    } else {
      // Not awaited (iOS awaits it), so the profile sheet closes as soon as the shelf is in.
      set({ isLoadingShelf: false });
      void findRecommendations();
    }
  } catch (e) {
    const cached = storage.cache.shelf();
    if (cached && cached.userID === state.settings.goodreadsUserID && cached.shelf === state.settings.shelf) {
      set({ books: cached.books, shelfCachedAt: cached.fetchedAt });
      applyCachedChecks();
    }
    set({ shelfError: (e as Error).message });
  } finally {
    set({ isLoadingShelf: false });
  }
}

/** Fills unchecked books with their last good result, labelled with its timestamp. */
function applyCachedChecks() {
  const entries = storage.cache.entries();
  set((s) => {
    const checks = { ...s.checks };
    for (const b of s.books) {
      const e = entries[b.bookID];
      if (checks[b.bookID]?.phase !== "checked" && e) checks[b.bookID] = { phase: "checked", result: e.result, cachedAt: e.checkedAt };
    }
    return { checks };
  });
}

// MARK: - Availability checks

function setCheck(bookID: string, check: BookCheck) {
  set((s) => ({ checks: { ...s.checks, [bookID]: check } }));
}

function store(result: SearchResult, book: Book) {
  const shown = storage.cache.record(result, book.bookID);
  setCheck(book.bookID, { phase: "checked", result: shown.result, cachedAt: shown.cachedAt });
}

export async function check(book: Book) {
  setCheck(book.bookID, { ...state.checks[book.bookID], phase: "checking" });
  store(await api.checkBook(book, 2), book);
}

/** Python: `asyncio.Semaphore(3)` around each book check. */
const MAX_CONCURRENT_CHECKS = 3;

export async function checkAll() {
  const books = state.books;
  if (state.isCheckingBatch || books.length === 0) return;
  set((s) => ({
    isCheckingBatch: true,
    batchCompleted: 0,
    batchTotal: books.length,
    checks: Object.fromEntries([
      ...Object.entries(s.checks),
      ...books.map((b) => [b.bookID, { ...s.checks[b.bookID], phase: "checking" as const }]),
    ]),
  }));
  let next = 0;
  const worker = async () => {
    while (next < books.length) {
      const book = books[next++];
      store(await api.checkBook(book, 2), book);
      set((s) => ({ batchCompleted: s.batchCompleted + 1 }));
    }
  };
  await Promise.all(Array.from({ length: Math.min(MAX_CONCURRENT_CHECKS, books.length) }, worker));
  set({ isCheckingBatch: false });
}

// MARK: - Recomendaciones

/** Shuffle the shelf, check 3 at a time (`limit_per_book=1`), stop once 2 books are available right now.
 *  As in the web app, only the recommended books get their status updated. */
export async function findRecommendations() {
  if (state.isFindingRecommendations || state.books.length === 0) return;
  set({ isFindingRecommendations: true });
  const candidates = [...state.books];
  for (let i = candidates.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
  }
  const found: { book: Book; result: SearchResult }[] = [];
  const target = 2;
  for (let start = 0; start < candidates.length && found.length < target; start += 3) {
    const chunk = candidates.slice(start, start + 3);
    const results = await Promise.all(chunk.map((b) => api.checkBook(b, 1)));
    for (let i = 0; i < chunk.length; i++) {
      if (summarize(results[i], proximity(state)).state === "available") {
        found.push({ book: chunk[i], result: results[i] });
        if (found.length >= target) break;
      }
    }
  }
  for (const f of found) store(f.result, f.book);
  set({ recommendationIDs: found.map((f) => f.book.bookID), isFindingRecommendations: false, recommendationsSearched: true });
}

// MARK: - Direct search

export async function search(title: string, author: string) {
  set({ isSearching: true });
  const result = await api.searchCatalog(title, author);
  set({ searchResult: result, isSearching: false });
}

export const clearSearch = () => set({ searchResult: null });

// MARK: - Loans

/** Validates the credentials against the OPAC before saving them on this device. */
export async function connectReader(card: string, password: string) {
  const credentials = { card: card.trim(), password };
  if (!credentials.card || !credentials.password) return set({ loansError: "Introduce el número de carné y la contraseña." });
  if (await refreshLoansWith(credentials)) {
    storage.saveCredentials(credentials);
    set({ hasCredentials: true });
  }
}

export async function refreshLoans() {
  const credentials = storage.loadCredentials();
  if (!credentials) return set({ hasCredentials: false });
  await refreshLoansWith(credentials);
}

async function refreshLoansWith(credentials: storage.Credentials): Promise<boolean> {
  if (state.loansLoading) return false;
  set({ loansLoading: true });
  const r = await api.fetchLoans(credentials.card, credentials.password);
  set({ loansLoading: false });
  switch (r.kind) {
    case "ok": {
      const fetchedAt = new Date().toISOString();
      storage.saveLoans({ loans: r.loans, fetchedAt });
      set({ loans: r.loans, loansFetchedAt: fetchedAt, loansShowingCache: false, loansError: null });
      return true;
    }
    case "invalidCredentials":
      set({
        loansError:
          "El número de carné o la contraseña no son correctos. Recuerda que la contraseña del catálogo caduca a los 6 meses.",
      });
      return false;
    case "catalogUnavailable":
      set((s) => ({
        loansShowingCache: s.loansFetchedAt != null,
        loansError: `No se pudieron consultar tus préstamos: ${r.reason}`,
      }));
      return false;
  }
}

/** Forgets the card and password and the cached loans. */
export function disconnectReader() {
  storage.deleteCredentials();
  storage.deleteLoans();
  set({ hasCredentials: false, loans: [], loansFetchedAt: null, loansError: null, loansShowingCache: false });
}

// MARK: - Launch (ZahoriApp.task)

export function launch() {
  if (state.settings.selectedLibraryIDs.length === 0) void requestLocationIfNeeded();
  void restore();
  void refreshLoans();
}
