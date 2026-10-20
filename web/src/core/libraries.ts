// Port of LibraryDirectory (ZahoriCore/Libraries.swift) = find_library_geo / normalize_text in Python.
// The data is the same verbatim export of MADRID_LIBRARIES_DB the iOS app bundles.
import data from "../../../ios/ZahoriKit/Sources/ZahoriCore/Resources/libraries.json";

export interface Library {
  id: string;
  name: string;
  aliases: string[];
  lat: number;
  lon: number;
  district: string;
  municipality: string;
  address: string;
}

export const libraries: Library[] = data as Library[];

const byID = new Map(libraries.map((l) => [l.id, l]));

/** Strip accents, keep ASCII alphanumerics, lowercase, collapse spaces. */
export function normalize(text: string): string {
  if (!text) return "";
  const noMarks = text.normalize("NFKD").replace(/\p{M}/gu, "");
  return noMarks.replace(/[^a-zA-Z0-9]/g, " ").toLowerCase().split(/\s+/).filter(Boolean).join(" ");
}

const normalizedAliases = libraries.map((library) => ({ library, aliases: library.aliases.map(normalize) }));

const stopTokens = new Set(["bp", "biblioteca", "publica", "municipal", "de", "la", "el", "los", "las", "y", "del", "en", "dña", "don"]);

const tokens = (s: string) => new Set(s.split(" ").filter((t) => t && !stopTokens.has(t)));

export const libraryById = (id: string) => byID.get(id);

/** Exact alias, then substring containment, then >= 2 shared tokens. */
export function findLibrary(rawName: string): Library | undefined {
  if (!rawName) return undefined;
  const norm = normalize(rawName);
  for (const e of normalizedAliases) if (e.aliases.includes(norm)) return e.library;
  for (const e of normalizedAliases)
    for (const alias of e.aliases) if (alias.includes(norm) || norm.includes(alias)) return e.library;

  const normTokens = tokens(norm);
  let best: Library | undefined;
  let maxOverlap = 0;
  for (const e of normalizedAliases)
    for (const alias of e.aliases) {
      let overlap = 0;
      for (const t of tokens(alias)) if (normTokens.has(t)) overlap++;
      if (overlap > maxOverlap && overlap >= 2) {
        maxOverlap = overlap;
        best = e.library;
      }
    }
  return best;
}

/** Sorted by (municipality, district, name), like `get_all_libraries_list`. */
export const sortedLibraries: Library[] = [...libraries].sort((a, b) => {
  const ka = [a.municipality, a.district, a.name];
  const kb = [b.municipality, b.district, b.name];
  for (let i = 0; i < 3; i++) if (ka[i] !== kb[i]) return ka[i] < kb[i] ? -1 : 1;
  return 0;
});
