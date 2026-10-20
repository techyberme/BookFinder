// The web port checked against the same Python-generated expectations the iOS tests use
// (ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures/golden.json, written by ios/Scripts/make_golden.py),
// plus the loan-date cases of ReaderTests.swift.
import { describe, expect, it } from "vitest";
import golden from "../../../ios/ZahoriKit/Tests/ZahoriKitTests/Fixtures/golden.json";
import { summarize } from "./availability";
import { userIDFrom, userNameFrom } from "./goodreads";
import { findLibrary, normalize, sortedLibraries } from "./libraries";
import { daysUntilDue, dayString, renewableFromDay, sortLoans } from "./loans";
import type { Copy, Loan, SearchResult } from "./models";
import { group, haversineKm, MADRID_CENTER } from "./proximity";

type G = Record<string, any>;
const g = golden as G;

const copy = (h: G): Copy => ({
  library: h.library,
  location: h.location,
  shelfmark: h.shelfmark,
  barcode: h.barcode,
  itemType: h.item_type,
  support: h.support,
  statusRaw: h.status_raw,
  isAvailable: h.is_available,
  dueDate: h.due_date,
  lat: h.lat,
  lon: h.lon,
  district: h.district,
  municipality: h.municipality,
});

/** Python with nothing selected puts every holding in "other", in page order: that is the parsed detail page. */
const holdings: Copy[] = g.grouping.find((c: G) => c.selected.length === 0).other.map(copy);

describe("libraries (golden)", () => {
  it("normalize", () => {
    for (const [input, expected] of Object.entries(g.normalize)) expect(normalize(input)).toBe(expected);
  });
  it("find_library_geo", () => {
    for (const [name, id] of Object.entries(g.find_library_geo)) expect(findLibrary(name)?.id ?? null).toBe(id);
  });
  it("sorted list", () => {
    expect(sortedLibraries.map((l) => l.id)).toEqual(g.libraries_list_ids);
  });
  it("haversine", () => {
    for (const [a, b, c, d, km] of g.haversine) expect(haversineKm(a, b, c, d)).toBe(km);
  });
});

describe("goodreads (golden)", () => {
  it("user id", () => {
    for (const [input, expected] of Object.entries(g.user_id)) expect(userIDFrom(input)).toBe(expected);
  });
  it("user name from the URL slug", () => {
    for (const [input, channel, expected] of g.user_name) if (channel == null) expect(userNameFrom(input)).toBe(expected);
  });
});

describe("proximity grouping (golden)", () => {
  for (const c of g.grouping as G[]) it(`${c.selected.join(",") || "(none)"}, ${c.radius_km} km`, () => {
    const out = group(holdings, { selectedLibraries: c.selected, radiusKm: c.radius_km, fallbackOrigin: null });
    for (const key of ["direct", "nearby", "other"] as const) {
      expect(out[key].map((h) => [h.library, h.barcode, h.distanceKm ?? null, h.relativeToLibrary ?? null])).toEqual(
        c[key].map((h: G) => [h.library, h.barcode, h.distance_km, h.relative_to_library]),
      );
    }
  });

  it("no selection + fallback origin measures from that point", () => {
    const out = group(holdings, { selectedLibraries: [], radiusKm: 5, fallbackOrigin: { name: "el centro de Madrid", coordinate: MADRID_CENTER } });
    expect(out.direct).toEqual([]);
    expect(out.nearby.length).toBeGreaterThan(0);
    expect(out.nearby.every((h) => h.relativeToLibrary === "el centro de Madrid" && h.distanceKm! <= 5)).toBe(true);
  });
});

describe("availability summary (golden batch)", () => {
  const cases: G[] = g.batch.filter((c: G) => c.success); // Python reports an outage as "not found"; iOS/web: catalogUnavailable
  for (const c of cases) it(`${c.selected.join(",") || "(none)"} (${c.only_loaned ? "loaned" : "all"})`, () => {
    const copies = c.only_loaned ? holdings.filter((h) => !h.isAvailable) : holdings;
    const result: SearchResult = {
      queryTitle: "Cien años de soledad",
      queryAuthor: "García Márquez",
      outcome: { kind: "found", editions: [{ title: "x", copies }], totalEditions: 3, isPartial: false },
    };
    const a = summarize(result, { selectedLibraries: c.selected, radiusKm: c.radius_km, fallbackOrigin: null });
    const r = c.result;
    expect([a.state === "available", a.totalEditions, a.totalCopies, a.totalAvailableCopies, a.statusSummary]).toEqual([
      r.is_available,
      r.total_editions,
      r.total_copies,
      r.total_available_copies,
      r.status_summary,
    ]);
    expect([a.bestMatchLibrary, a.bestMatchDistanceKm, a.directMatchesCount, a.directMatchesAvailable]).toEqual([
      r.best_match_library,
      r.best_match_distance_km,
      r.direct_matches_count,
      r.direct_matches_available,
    ]);
  });

  it("an outage is never 'not in catalog'", () => {
    const p = { selectedLibraries: [], radiusKm: 5, fallbackOrigin: null };
    const base = { queryTitle: "t", queryAuthor: "" };
    expect(summarize({ ...base, outcome: { kind: "catalogUnavailable", reason: "x" } }, p).state).toBe("catalogUnavailable");
    expect(summarize({ ...base, outcome: { kind: "noResults" } }, p).statusSummary).toBe("No encontrado en catálogo");
  });
});

describe("loans (ReaderTests.swift)", () => {
  /** "DD/MM/YYYY HH:MM" Madrid time → Date (October/November 2026: CEST until 25/10, then CET). */
  const madrid = (s: string) => {
    const [d, m, y, hh, mm] = s.split(/[/ :]/).map(Number);
    const offset = m > 10 || (m === 10 && d >= 25) ? 1 : 2;
    return new Date(Date.UTC(y, m - 1, d, hh - offset, mm));
  };
  const loan: Loan = {
    barcode: "A",
    title: "Rayuela",
    branch: "BP Acuña",
    dueDateTime: "12/11/2026 23:59",
    renewalsUsed: 0,
    renewalsMax: 1,
    renewalWindowDays: 5,
    reservations: 0,
  };

  it("days left on the Madrid calendar", () => {
    expect(daysUntilDue(loan, madrid("19/10/2026 09:00"))).toBe(24);
    expect(daysUntilDue(loan, madrid("12/11/2026 08:00"))).toBe(0);
    expect(daysUntilDue(loan, madrid("14/11/2026 08:00"))).toBe(-2);
    // 00:30 in Madrid is still the previous day in UTC: the Madrid day must win.
    expect(daysUntilDue(loan, madrid("12/11/2026 00:30"))).toBe(0);
  });

  it("renewal window", () => {
    expect(dayString(renewableFromDay(loan)!)).toBe("07/11/2026");
    expect(renewableFromDay({ ...loan, renewalsUsed: 1 })).toBeNull();
  });

  it("sorted soonest first", () => {
    const later = { ...loan, barcode: "B", dueDateTime: "25/10/2026 23:59" };
    expect(sortLoans([loan, later]).map((l) => l.barcode)).toEqual(["B", "A"]);
  });
});
