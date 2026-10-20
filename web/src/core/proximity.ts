// Port of ZahoriCore/Proximity.swift (= AbsysNetScraper._apply_geospatial_grouping, plus the iOS
// fallback origin: with no library selected, distances are measured from the user's location or Madrid center).
import type { Copy } from "./models";
import { findLibrary, libraryById, normalize } from "./libraries";

export interface Coordinate {
  lat: number;
  lon: number;
}

/** Puerta del Sol: origin when location is denied (same point the Python tests use). */
export const MADRID_CENTER: Coordinate = { lat: 40.4168, lon: -3.7038 };

export interface ReferencePoint {
  name: string;
  coordinate: Coordinate;
}

/** Great-circle km, rounded to 2 decimals like Python's `round(x, 2)`. */
export function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const r = 6371.0;
  const rad = Math.PI / 180;
  const dPhi = (lat2 - lat1) * rad;
  const dLambda = (lon2 - lon1) * rad;
  const a = Math.sin(dPhi / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLambda / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Number((r * c).toFixed(2));
}

export interface GroupedCopies {
  /** "Bibliotecas Seleccionadas" */
  direct: Copy[];
  /** "Alternativas Cercanas": every copy within the radius, by distance, then available first. */
  nearby: Copy[];
  /** "Otras Bibliotecas" */
  other: Copy[];
}

export interface Proximity {
  selectedLibraries: string[];
  radiusKm: number;
  fallbackOrigin: ReferencePoint | null;
}

/** Coordinates of the selected libraries (unknown ids/names are skipped, as in Python). */
export function referencePoints(p: Proximity): ReferencePoint[] {
  return p.selectedLibraries.flatMap((sel) => {
    const lib = findLibrary(sel) ?? libraryById(sel);
    return lib ? [{ name: lib.name, coordinate: { lat: lib.lat, lon: lib.lon } }] : [];
  });
}

export function group(copies: Copy[], p: Proximity): GroupedCopies {
  if (p.selectedLibraries.length === 0) {
    if (!p.fallbackOrigin) return { direct: [], nearby: [], other: copies };
    return groupByDistance(copies, p, [p.fallbackOrigin], []);
  }
  return groupByDistance(copies, p, referencePoints(p), p.selectedLibraries.map(normalize));
}

function groupByDistance(copies: Copy[], p: Proximity, refs: ReferencePoint[], normSelected: string[]): GroupedCopies {
  const result: GroupedCopies = { direct: [], nearby: [], other: [] };
  for (const original of copies) {
    const copy: Copy = { ...original };
    const hNorm = normalize(copy.library);
    let isDirect = normSelected.some((s) => s.includes(hNorm) || hNorm.includes(s));
    if (!isDirect && normSelected.length > 0) {
      const geo = findLibrary(copy.library);
      if (geo) isDirect = p.selectedLibraries.includes(geo.id) || normSelected.includes(normalize(geo.name));
    }
    if (isDirect) {
      copy.isDirectMatch = true;
      copy.distanceKm = 0;
      result.direct.push(copy);
      continue;
    }
    if (refs.length === 0 || copy.lat == null || copy.lon == null) {
      result.other.push(copy);
      continue;
    }
    let minDist = Infinity;
    let closest: string | null = null;
    for (const ref of refs) {
      const d = haversineKm(copy.lat, copy.lon, ref.coordinate.lat, ref.coordinate.lon);
      if (d < minDist) {
        minDist = d;
        closest = ref.name;
      }
    }
    copy.relativeToLibrary = closest;
    if (minDist <= p.radiusKm) {
      copy.distanceKm = minDist;
      result.nearby.push(copy);
    } else {
      copy.distanceKm = Number.isFinite(minDist) ? minDist : null;
      result.other.push(copy);
    }
  }
  // Python: sort(key=(distance or 9999, not is_available)) — Array.prototype.sort is stable.
  result.nearby.sort((a, b) => {
    const da = a.distanceKm ?? 9999;
    const db = b.distanceKm ?? 9999;
    if (da !== db) return da - db;
    return (a.isAvailable ? 0 : 1) - (b.isAvailable ? 0 : 1);
  });
  return result;
}
