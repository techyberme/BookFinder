// Port of ZahoriCore/Availability.swift (= summary rules of `_check_single_book_availability` in backend/main.py).
import type { Copy, Edition, SearchResult } from "./models";
import { group, type Proximity } from "./proximity";

export type AvailabilityState = "available" | "onLoan" | "notInCatalog" | "catalogUnavailable";

export interface Availability {
  state: AvailabilityState;
  totalEditions: number;
  totalCopies: number;
  totalAvailableCopies: number;
  statusSummary: string;
  bestMatchLibrary: string | null;
  bestMatchDistanceKm: number | null;
  directMatchesCount: number;
  directMatchesAvailable: number;
  /** Python's `full_result`: the first edition, used by the book detail screen. */
  firstEdition: Edition | null;
  isPartial: boolean;
}

const empty = (state: AvailabilityState, statusSummary: string): Availability => ({
  state,
  totalEditions: 0,
  totalCopies: 0,
  totalAvailableCopies: 0,
  statusSummary,
  bestMatchLibrary: null,
  bestMatchDistanceKm: null,
  directMatchesCount: 0,
  directMatchesAvailable: 0,
  firstEdition: null,
  isPartial: false,
});

export function summarize(result: SearchResult, proximity: Proximity): Availability {
  const o = result.outcome;
  if (o.kind === "invalidQuery" || o.kind === "noResults") return empty("notInCatalog", "No encontrado en catálogo");
  if (o.kind === "catalogUnavailable") return empty("catalogUnavailable", "Catálogo no disponible");
  if (o.editions.length === 0) return empty("notInCatalog", "No encontrado en catálogo");

  const all: Copy[] = [];
  const direct: Copy[] = [];
  const nearby: Copy[] = [];
  for (const e of o.editions) {
    const g = group(e.copies, proximity);
    all.push(...e.copies);
    direct.push(...g.direct);
    nearby.push(...g.nearby);
  }
  const totalAvail = all.filter((c) => c.isAvailable).length;
  const isAvailable = totalAvail > 0;
  const directAvail = direct.filter((c) => c.isAvailable);

  let bestLib: string | null = null;
  let bestDist: number | null = null;
  let summary: string;
  const nearbyAvail = nearby.find((c) => c.isAvailable);
  const anyAvail = all.find((c) => c.isAvailable);
  if (directAvail.length > 0) {
    bestLib = directAvail[0].library;
    bestDist = 0;
    summary = `Disponible en ${bestLib}`;
  } else if (direct.length > 0 && !isAvailable) {
    summary = `Prestado en ${direct[0].library}`;
  } else if (nearbyAvail) {
    bestLib = nearbyAvail.library;
    bestDist = nearbyAvail.distanceKm ?? null;
    summary = `Disponible en ${bestLib} (a ${(nearbyAvail.distanceKm ?? 0).toFixed(1)} km)`;
  } else if (anyAvail) {
    bestLib = anyAvail.library;
    summary = `Disponible en ${bestLib}`;
  } else if (all.length > 0) {
    summary = `Prestado (${all.length} ejemplares en red)`;
  } else {
    summary = "No disponible";
  }

  return {
    state: isAvailable ? "available" : "onLoan",
    totalEditions: o.totalEditions,
    totalCopies: all.length,
    totalAvailableCopies: totalAvail,
    statusSummary: summary,
    bestMatchLibrary: bestLib,
    bestMatchDistanceKm: bestDist,
    directMatchesCount: direct.length,
    directMatchesAvailable: directAvail.length,
    firstEdition: o.editions[0],
    isPartial: o.isPartial,
  };
}
