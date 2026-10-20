// Calls to the FastAPI backend (backend/main.py). The browser cannot reach the OPAC or Goodreads
// directly (no CORS, cookie-based sessions), so the server does the same requests the iOS app does.
import type { Book, Copy, Edition, Loan, SearchResult } from "./models";

type Json = any;

class HTTPError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

async function request(path: string, init: RequestInit = {}, timeoutMs = 60_000): Promise<Json> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  let res: Response;
  try {
    res = await fetch(path, { ...init, signal: ctrl.signal });
  } catch (e) {
    throw new Error(
      (e as Error).name === "AbortError" ? "tiempo de espera agotado" : "sin conexión con el servidor de Zahorí",
    );
  } finally {
    clearTimeout(timer);
  }
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const detail = typeof body?.detail === "string" ? body.detail : `error ${res.status}`;
    throw new HTTPError(res.status, detail);
  }
  return body;
}

// --- Goodreads ---

export interface ShelfResult {
  userID: string;
  userName: string | null;
  shelf: string;
  books: Book[];
}

export async function fetchShelf(userInput: string, shelf: string): Promise<ShelfResult> {
  const q = new URLSearchParams({ user_id: userInput, shelf });
  const data = await request(`/api/goodreads/shelf?${q}`, {}, 30_000);
  return {
    userID: data.user_id,
    userName: data.user_name ?? null,
    shelf: data.shelf,
    books: data.books.map(
      (b: Json): Book => ({
        bookID: b.book_id,
        title: b.title,
        cleanTitle: b.clean_title,
        author: b.author ?? "",
        isbn: b.isbn,
        coverImageURL: b.cover_image_url,
        link: b.link,
      }),
    ),
  };
}

// --- Catalog ---

const copyFrom = (h: Json): Copy => ({
  library: h.library,
  location: h.location ?? "General",
  shelfmark: h.shelfmark ?? "N/A",
  barcode: h.barcode,
  itemType: h.item_type ?? "Prestable",
  support: h.support ?? "Libro",
  statusRaw: h.status_raw,
  isAvailable: h.is_available,
  dueDate: h.due_date,
  lat: h.lat,
  lon: h.lon,
  district: h.district,
  municipality: h.municipality,
});

const editionFrom = (b: Json): Edition => ({
  title: b.title,
  author: b.author,
  publication: b.publication,
  year: b.year,
  edition: b.edition,
  isbn: b.isbn,
  description: b.description,
  detailURL: b.detail_url,
  copies: (b.holdings ?? []).map(copyFrom),
});

function searchResultFrom(data: Json, title: string, author: string): SearchResult {
  const base = { queryTitle: title, queryAuthor: author };
  switch (data.outcome) {
    case "no_results":
      return { ...base, outcome: { kind: "noResults" } };
    case "invalid_query":
      return { ...base, outcome: { kind: "invalidQuery" } };
    case "catalog_unavailable":
      return { ...base, outcome: { kind: "catalogUnavailable", reason: data.error ?? "" } };
    default:
      if (!data.success) return { ...base, outcome: { kind: "catalogUnavailable", reason: data.error ?? "" } };
      if (!data.results?.length) return { ...base, outcome: { kind: "noResults" } };
      return {
        ...base,
        outcome: {
          kind: "found",
          editions: data.results.map(editionFrom),
          totalEditions: data.total_editions,
          isPartial: !!data.is_partial,
        },
      };
  }
}

async function catalog(path: string, title: string, author: string): Promise<SearchResult> {
  try {
    return searchResultFrom(await request(path, {}, 90_000), title, author);
  } catch (e) {
    if (e instanceof HTTPError && e.status === 400) return { queryTitle: title, queryAuthor: author, outcome: { kind: "invalidQuery" } };
    const reason = `No se pudo conectar con el catálogo de bibliotecas: ${(e as Error).message}`;
    return { queryTitle: title, queryAuthor: author, outcome: { kind: "catalogUnavailable", reason } };
  }
}

/** One shelf book (title cleaned again on the server, like the iOS batch check). */
export function checkBook(book: Book, limitPerBook: number): Promise<SearchResult> {
  const q = new URLSearchParams({ title: book.cleanTitle, author: book.author, limit: String(limitPerBook) });
  return catalog(`/api/check?${q}`, book.cleanTitle, book.author);
}

/** Direct search, 5 editions (iOS `OPACClient().search(maxItems: 5)`). */
export function searchCatalog(title: string, author: string): Promise<SearchResult> {
  const q = new URLSearchParams({ limit: "5" });
  if (title) q.set("title", title);
  if (author) q.set("author", author);
  return catalog(`/api/search?${q}`, title, author);
}

// --- Reader area ---

export type LoansResponse =
  | { kind: "ok"; loans: Loan[] }
  | { kind: "invalidCredentials" }
  | { kind: "catalogUnavailable"; reason: string };

const loanFrom = (l: Json): Loan => ({
  barcode: l.barcode,
  title: l.title,
  branch: l.branch,
  branchAddress: l.branch_address,
  dueDateTime: l.due_date_time,
  loanDateTime: l.loan_date_time,
  shelfmark: l.shelfmark,
  renewalsUsed: l.renewals_used,
  renewalsMax: l.renewals_max,
  renewalWindowDays: l.renewal_window_days,
  reservations: l.reservations,
  recordURL: l.record_url,
});

export async function fetchLoans(card: string, password: string): Promise<LoansResponse> {
  try {
    const data = await request(
      "/api/reader/loans",
      { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ card, password }) },
      90_000,
    );
    return { kind: "ok", loans: data.loans.map(loanFrom) };
  } catch (e) {
    if (e instanceof HTTPError && e.status === 401) return { kind: "invalidCredentials" };
    return { kind: "catalogUnavailable", reason: (e as Error).message };
  }
}

/** Opens the .ics with due-date alerts. A real form POST, so iOS shows its "add to Calendar" sheet. */
export function openLoansCalendar(loans: Loan[], daysBefore: number) {
  const payload = {
    days_before: daysBefore,
    loans: loans.map((l) => ({
      barcode: l.barcode,
      title: l.title,
      branch: l.branch,
      branch_address: l.branchAddress,
      due_date_time: l.dueDateTime,
      shelfmark: l.shelfmark,
    })),
  };
  const form = document.createElement("form");
  form.method = "POST";
  form.action = "/api/reader/calendar.ics";
  form.target = "_blank";
  const input = document.createElement("input");
  input.type = "hidden";
  input.name = "payload";
  input.value = JSON.stringify(payload);
  form.appendChild(input);
  document.body.appendChild(form);
  form.submit();
  form.remove();
}
