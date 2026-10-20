// Buscar tab. Port of SearchView.swift ("Búsqueda Directa en Catálogo").
import { useRef, useState } from "react";
import { editionsOf, totalAvailableOf, totalCopiesOf, totalEditionsOf, type SearchResult } from "../core/models";
import * as model from "../store";
import { useStore } from "../store";
import { CatalogUnavailable, EditionMeta, GroupedCopies, PartialNote, SkeletonCard, Spinner, ToggleButton } from "./components";
import { Screen } from "./nav";

/** Same quick-fill examples as frontend/index.html. */
const SUGGESTIONS: [string, string][] = [
  ["Cien años de soledad", "Gabriel García Márquez"],
  ["El infinito en un junco", "Irene Vallejo"],
  ["Ficciones", "Jorge Luis Borges"],
];

export function SearchScreen() {
  const s = useStore();
  const [title, setTitle] = useState("");
  const [author, setAuthor] = useState("");
  const [validationError, setValidationError] = useState<string | null>(null);
  const titleRef = useRef<HTMLInputElement>(null);
  const authorRef = useRef<HTMLInputElement>(null);

  const submit = () => {
    const t = title.trim();
    const a = author.trim();
    if (!t && !a) {
      setValidationError("Por favor, introduzca al menos un título o un autor para realizar la búsqueda.");
      titleRef.current?.focus();
      return;
    }
    setValidationError(null);
    titleRef.current?.blur();
    authorRef.current?.blur();
    void model.search(t, a);
  };

  return (
    <Screen title="Buscar" large>
      <div className="content" style={{ gap: 16 }}>
        <form
          className="card stack-v"
          style={{ padding: 16, gap: 12 }}
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
        >
          <p className="muted" style={{ fontSize: 13 }}>
            Consulte la disponibilidad física en sala, sucursales y fechas estimadas de devolución en toda la red pública.
          </p>
          <label className="stack-v" style={{ gap: 6 }}>
            <span className="eyebrow">Título del libro</span>
            <span className="field">
              <input
                ref={titleRef}
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Ej: Cien años de soledad, Don Quijote…"
                enterKeyHint="next"
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    authorRef.current?.focus();
                  }
                }}
              />
            </span>
          </label>
          <label className="stack-v" style={{ gap: 6 }}>
            <span className="eyebrow">Autor / Autora</span>
            <span className="field">
              <input
                ref={authorRef}
                value={author}
                onChange={(e) => setAuthor(e.target.value)}
                placeholder="Ej: García Márquez, Irene Vallejo, J.K. Rowling…"
                enterKeyHint="search"
              />
            </span>
          </label>
          <div className="hscroll">
            {SUGGESTIONS.map(([t, a]) => (
              <button
                key={t}
                type="button"
                className="btn-secondary"
                onClick={() => {
                  setTitle(t);
                  setAuthor(a);
                }}
              >
                {t}
              </button>
            ))}
          </div>
          {validationError && <p style={{ fontSize: 12, fontWeight: 500, color: "var(--accent)" }}>{validationError}</p>}
          <div className="row" style={{ gap: 10 }}>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => {
                setTitle("");
                setAuthor("");
                setValidationError(null);
                model.clearSearch();
              }}
            >
              Limpiar
            </button>
            <button type="submit" className="btn-primary spacer" disabled={s.isSearching}>
              {s.isSearching && <Spinner size={16} />}
              Consultar catálogo
            </button>
          </div>
        </form>
        <Results onRetry={submit} />
      </div>
    </Screen>
  );
}

function Results({ onRetry }: { onRetry: () => void }) {
  const s = useStore();
  if (s.isSearching) return [0, 1].map((i) => <SkeletonCard key={i} />);
  const result = s.searchResult;
  if (!result) return null;
  switch (result.outcome.kind) {
    case "catalogUnavailable":
      return <CatalogUnavailable reason={result.outcome.reason} retry={onRetry} />;
    case "noResults":
    case "invalidQuery":
      return <EmptyState />;
    case "found":
      return editionsOf(result).length === 0 ? <EmptyState /> : <Found result={result} />;
  }
}

function EmptyState() {
  return (
    <div className="card stack-v" style={{ padding: 16, gap: 6 }}>
      <h3 className="serif" style={{ fontSize: 18 }}>
        No se encontraron ejemplares
      </h3>
      <p className="muted" style={{ fontSize: 13 }}>
        No se recuperaron resultados en el catálogo con los términos indicados. Pruebe a buscar por solo el título principal o
        por el autor.
      </p>
    </div>
  );
}

const plural = (n: number, one: string, many: string) => (n === 1 ? `1 ${one}` : `${n} ${many}`);

function Found({ result }: { result: SearchResult }) {
  const s = useStore();
  const [branchFilter, setBranchFilter] = useState("");
  const [onlyAvailable, setOnlyAvailable] = useState(false);
  const proximity = model.proximity(s);
  return (
    <div className="stack-v" style={{ gap: 14 }}>
      <div className="row muted" style={{ gap: 6, fontSize: 12, fontWeight: 600, flexWrap: "wrap" }}>
        <span>{plural(totalEditionsOf(result), "edición", "ediciones")}</span>
        <span>•</span>
        <span>{plural(totalCopiesOf(result), "ejemplar en red", "ejemplares en red")}</span>
        <span>•</span>
        <span style={{ color: "var(--available)" }}>{plural(totalAvailableOf(result), "disponible", "disponibles")}</span>
      </div>
      <div className="row" style={{ gap: 10 }}>
        <label className="field on-card spacer">
          <input value={branchFilter} onChange={(e) => setBranchFilter(e.target.value)} placeholder="Filtrar por biblioteca..." />
        </label>
        <ToggleButton on={onlyAvailable} onChange={setOnlyAvailable}>
          Solo disponibles
        </ToggleButton>
      </div>
      {editionsOf(result).map((edition, i) => {
        const avail = edition.copies.filter((c) => c.isAvailable).length;
        const total = edition.copies.length;
        return (
          <div key={i} className="card stack-v" style={{ padding: 16, gap: 12 }}>
            <div className="row" style={{ alignItems: "baseline" }}>
              <span className="eyebrow">Edición #{i + 1}</span>
              <span className="spacer" />
              <span className={`pill ${avail > 0 ? "tone-available" : ""}`}>
                {total === 1 ? `${avail} de 1 disponible` : `${avail} de ${total} disponibles`}
              </span>
            </div>
            <h3 className="serif" style={{ fontSize: 18 }}>
              {edition.title}
            </h3>
            {edition.author && (
              <span className="muted" style={{ fontSize: 13, fontWeight: 500 }}>
                {edition.author}
              </span>
            )}
            <EditionMeta edition={edition} />
            <div className="divider" />
            <GroupedCopies copies={edition.copies} proximity={proximity} branchFilter={branchFilter} onlyAvailable={onlyAvailable} />
          </div>
        );
      })}
      {result.outcome.kind === "found" && result.outcome.isPartial && <PartialNote />}
    </div>
  );
}
