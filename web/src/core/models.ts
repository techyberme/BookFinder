// Data models. Mirror ios/ZahoriKit/Sources/ZahoriCore/Models.swift and Loans.swift.

/** A book on a Goodreads shelf (`GoodreadsBook` in backend/goodreads_service.py). */
export interface Book {
  bookID: string;
  title: string;
  /** Sanitized title used for catalog search. */
  cleanTitle: string;
  author: string;
  isbn?: string | null;
  coverImageURL?: string | null;
  link?: string | null;
}

/** A physical copy in a branch (`HoldingItem`). */
export interface Copy {
  library: string;
  location: string;
  shelfmark: string;
  barcode?: string | null;
  itemType: string;
  support: string;
  /** "Disponible", "Prestado (hasta DD/MM/YYYY)" or the raw OPAC text. */
  statusRaw: string;
  isAvailable: boolean;
  /** DD/MM/YYYY, exactly as printed by the OPAC. */
  dueDate?: string | null;
  lat?: number | null;
  lon?: number | null;
  district?: string | null;
  municipality?: string | null;
  // Filled in by `group` (proximity.ts).
  distanceKm?: number | null;
  relativeToLibrary?: string | null;
  isDirectMatch?: boolean;
}

/** A bibliographic record with its copies (`BookResult`). */
export interface Edition {
  title: string;
  author?: string | null;
  publication?: string | null;
  year?: string | null;
  edition?: string | null;
  isbn?: string | null;
  description?: string | null;
  detailURL?: string | null;
  copies: Copy[];
}

/** A catalog outage is never confused with "this book is not in the catalog". */
export type SearchOutcome =
  | { kind: "found"; editions: Edition[]; totalEditions: number; isPartial: boolean }
  | { kind: "noResults" }
  | { kind: "invalidQuery" }
  | { kind: "catalogUnavailable"; reason: string };

export interface SearchResult {
  queryTitle: string;
  queryAuthor: string;
  outcome: SearchOutcome;
}

export const editionsOf = (r: SearchResult): Edition[] => (r.outcome.kind === "found" ? r.outcome.editions : []);
export const totalEditionsOf = (r: SearchResult): number => (r.outcome.kind === "found" ? r.outcome.totalEditions : 0);
export const totalCopiesOf = (r: SearchResult): number => editionsOf(r).reduce((n, e) => n + e.copies.length, 0);
export const totalAvailableOf = (r: SearchResult): number =>
  editionsOf(r).reduce((n, e) => n + e.copies.filter((c) => c.isAvailable).length, 0);

/** A book currently on loan ("Mi biblioteca → Préstamos"). */
export interface Loan {
  barcode: string;
  title: string;
  branch: string;
  branchAddress?: string | null;
  /** "DD/MM/YYYY HH:MM", Madrid local time. */
  dueDateTime: string;
  loanDateTime?: string | null;
  shelfmark?: string | null;
  renewalsUsed: number;
  renewalsMax: number;
  /** Renewal opens this many days before the due date. */
  renewalWindowDays: number;
  /** Reservations by other readers; a reserved item cannot be renewed. */
  reservations: number;
  recordURL?: string | null;
}

/** User settings (`AppSettings` in Persistence.swift). */
export interface Settings {
  selectedLibraryIDs: string[];
  radiusKm: number;
  goodreadsUserID: string | null;
  goodreadsUserName: string | null;
  shelf: string;
  /** Days before the due date for the calendar alert (iOS: local notification). */
  reminderDaysBefore: number;
}

export const RADIUS_RANGE = [1, 20] as const;
export const REMINDER_DAYS_RANGE = [1, 7] as const;

export const defaultSettings = (): Settings => ({
  selectedLibraryIDs: [],
  // Default of the web slider, which wins over the API default of 3 km.
  radiusKm: 5,
  goodreadsUserID: null,
  goodreadsUserName: null,
  shelf: "to-read",
  reminderDaysBefore: 2,
});

export const clamp = (v: number, [lo, hi]: readonly [number, number]) => Math.min(Math.max(v, lo), hi);
