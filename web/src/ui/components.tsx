// Shared views. Port of ios/Zahori/Views/Components.swift (+ ErrorBanner, EditionMeta, CatalogUnavailableView).
import { useEffect, useState, type ReactNode } from "react";
import { Calendar, ChevronRight, CloudOff, ExternalLink, History, TriangleAlert } from "lucide-react";
import type { Availability } from "../core/availability";
import type { Copy, Edition } from "../core/models";
import { group, type Proximity } from "../core/proximity";
import type { BookCheck } from "../store";

/** iOS activity indicator (8 spokes). */
export function Spinner({ size = 18, color = "currentColor" }: { size?: number; color?: string }) {
  return (
    <svg className="spinner" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      {Array.from({ length: 8 }, (_, i) => (
        <rect
          key={i}
          x="11"
          y="2"
          width="2.2"
          height="6"
          rx="1.1"
          fill={color}
          opacity={0.25 + (0.75 * i) / 7}
          transform={`rotate(${i * 45} 12 12)`}
        />
      ))}
    </svg>
  );
}

// MARK: - Status pill

export function StatusPill({ check, availability }: { check?: BookCheck; availability: Availability | null }) {
  let tone = "";
  let content: ReactNode = <span className="text">Sin comprobar</span>;
  if (check?.phase === "checking") {
    content = (
      <>
        <Spinner size={12} />
        <span className="text">Comprobando…</span>
      </>
    );
  } else if (check?.phase === "checked" && availability) {
    switch (availability.state) {
      case "available":
      case "onLoan":
        tone = availability.state === "available" ? "tone-available" : "tone-loan";
        content = (
          <>
            <span className="dot" />
            <span className="text">{availability.statusSummary}</span>
          </>
        );
        break;
      case "catalogUnavailable":
        tone = "tone-accent";
        content = (
          <>
            <CloudOff size={13} />
            <span className="text">Catálogo no disponible</span>
          </>
        );
        break;
      case "notInCatalog":
        tone = "tone-faint";
        content = <span className="text">No en catálogo</span>;
    }
  }
  return <span className={`pill ${tone}`}>{content}</span>;
}

// MARK: - Cover

export function Cover({ url, width = 64 }: { url?: string | null; width?: number }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className="cover" style={{ width, height: width * 1.42 }} aria-hidden="true">
      {url && !failed ? <img src={url} alt="" loading="lazy" onError={() => setFailed(true)} /> : <span>Sin portada</span>}
    </div>
  );
}

// MARK: - Copy row

function CopyRow({ copy, showDistance }: { copy: Copy; showDistance: boolean }) {
  const km = copy.distanceKm != null ? copy.distanceKm.toFixed(1) : null;
  return (
    <div className="stack-v" style={{ gap: 6, padding: "10px 0" }}>
      <div className="row" style={{ alignItems: "baseline" }}>
        <span style={{ fontSize: 14, fontWeight: 700 }}>{copy.library}</span>
        <span className="spacer" />
        <span className={`pill ${copy.isAvailable ? "tone-available" : "tone-loan"}`} style={{ textAlign: "right", flexShrink: 0 }}>
          {copy.isAvailable ? "Disponible" : copy.statusRaw}
        </span>
      </div>
      {showDistance && km && (
        <span className="mono muted" style={{ fontSize: 11, fontWeight: 600 }}>
          {copy.relativeToLibrary ? `📍 ${km} km de ${copy.relativeToLibrary}` : `📍 ${km} km`}
        </span>
      )}
      <span className="muted" style={{ fontSize: 12 }}>
        {copy.location} • {copy.support} • {copy.itemType}
      </span>
      <div className="row" style={{ gap: 6 }}>
        <span className="shelfmark" aria-label={`Signatura ${copy.shelfmark}`}>
          {copy.shelfmark}
        </span>
        {copy.dueDate && (
          <span className="row mono" style={{ gap: 4, fontSize: 11, color: "var(--on-loan)" }} aria-label={`Devolución prevista ${copy.dueDate}`}>
            <Calendar size={12} />
            {copy.dueDate}
          </span>
        )}
      </div>
    </div>
  );
}

// MARK: - Three result sections

/** "Bibliotecas Seleccionadas" / "Alternativas Cercanas" / "Otras Bibliotecas" for one edition. */
export function GroupedCopies({
  copies,
  proximity,
  branchFilter = "",
  onlyAvailable = false,
}: {
  copies: Copy[];
  proximity: Proximity;
  branchFilter?: string;
  onlyAvailable?: boolean;
}) {
  const [showOthers, setShowOthers] = useState(false);
  const f = branchFilter.trim().toLowerCase();
  const matches = (c: Copy) =>
    (!f || c.library.toLowerCase().includes(f) || c.location.toLowerCase().includes(f)) && (!onlyAvailable || c.isAvailable);
  const g = group(copies, proximity);
  const direct = g.direct.filter(matches);
  const nearby = g.nearby.filter(matches);
  const other = g.other.filter(matches);
  const hasSelection = proximity.selectedLibraries.length > 0;
  const usesOrigin = !hasSelection && proximity.fallbackOrigin != null;

  if (!hasSelection && !usesOrigin) {
    return (
      <Rows
        list={copies.filter(matches)}
        distance={false}
        empty={
          copies.length === 0
            ? "No hay copias físicas registradas para esta edición."
            : "No hay ejemplares que coincidan con los filtros seleccionados."
        }
      />
    );
  }
  return (
    <div className="stack-v" style={{ gap: 14 }}>
      {hasSelection && (
        <>
          <SectionTitle color="var(--accent)">Bibliotecas Seleccionadas ({direct.length})</SectionTitle>
          <Rows
            list={direct}
            distance={false}
            empty="No hay ejemplares registrados en las bibliotecas específicamente seleccionadas. Consulte las alternativas cercanas a continuación."
          />
        </>
      )}
      <SectionTitle color="var(--available)">Alternativas Cercanas ({nearby.length})</SectionTitle>
      <Rows
        list={nearby}
        distance
        empty="No se encontraron sucursales adicionales con copias dentro del radio de búsqueda establecido."
      />
      {other.length > 0 && (
        <div className={`disclosure${showOthers ? " open" : ""}`}>
          <button onClick={() => setShowOthers(!showOthers)} aria-expanded={showOthers}>
            <span className="eyebrow">Otras Bibliotecas ({other.length})</span>
            <ChevronRight className="chev" size={18} />
          </button>
          {showOthers && <Rows list={other} distance={false} empty="" />}
        </div>
      )}
    </div>
  );
}

function SectionTitle({ color, children }: { color: string; children: ReactNode }) {
  return (
    <div className="row" role="heading" aria-level={3}>
      <span className="dot" style={{ width: 7, height: 7, background: color }} />
      <span className="eyebrow" style={{ color: "var(--ink)" }}>
        {children}
      </span>
    </div>
  );
}

function Rows({ list, distance, empty }: { list: Copy[]; distance: boolean; empty: string }) {
  if (list.length === 0) {
    return (
      <p className="muted italic" style={{ fontSize: 12, padding: 12, background: "var(--chip)", borderRadius: 10 }}>
        {empty}
      </p>
    );
  }
  return (
    <div className="stack-v">
      {list.map((copy, i) => (
        <div key={i}>
          {i > 0 && <div className="divider" />}
          <CopyRow copy={copy} showDistance={distance} />
        </div>
      ))}
    </div>
  );
}

// MARK: - Skeleton

export function SkeletonCard() {
  return (
    <div className="card skeleton row" style={{ padding: 14, gap: 14, alignItems: "stretch" }} aria-label="Comprobando…">
      <div className="bone" style={{ width: 64, height: 91, borderRadius: 6 }} />
      <div className="stack-v spacer" style={{ gap: 8 }}>
        <div className="bone" style={{ height: 14 }} />
        <div className="bone" style={{ width: 120, height: 10 }} />
        <div className="spacer" />
        <div className="bone" style={{ width: 140, height: 20, borderRadius: 8 }} />
      </div>
    </div>
  );
}

// MARK: - "actualizado hace X"

const relative = new Intl.RelativeTimeFormat("es", { numeric: "auto" });

export function relativeTime(iso: string, now = Date.now()): string {
  const s = Math.round((new Date(iso).getTime() - now) / 1000);
  const abs = Math.abs(s);
  if (abs < 60) return relative.format(s, "second");
  if (abs < 3600) return relative.format(Math.round(s / 60), "minute");
  if (abs < 86400) return relative.format(Math.round(s / 3600), "hour");
  if (abs < 86400 * 30) return relative.format(Math.round(s / 86400), "day");
  return relative.format(Math.round(s / (86400 * 30)), "month");
}

export function UpdatedAgo({ date }: { date: string }) {
  const [, tick] = useState(0);
  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 30_000);
    return () => clearInterval(t);
  }, []);
  return (
    <span className="row faint" style={{ gap: 4, fontSize: 11, fontWeight: 500 }}>
      <History size={12} />
      actualizado {relativeTime(date)}
    </span>
  );
}

// MARK: - Errors

export function ErrorBanner({ message, cachedAt }: { message: string; cachedAt?: string | null }) {
  return (
    <div className="banner" role="alert">
      <span className="row" style={{ alignItems: "flex-start", fontSize: 13, fontWeight: 500, color: "var(--accent)" }}>
        <TriangleAlert size={16} style={{ flex: "none", marginTop: 1 }} />
        {message}
      </span>
      {cachedAt && (
        <>
          <span className="muted" style={{ fontSize: 12 }}>
            Mostrando la última copia guardada.
          </span>
          <UpdatedAgo date={cachedAt} />
        </>
      )}
    </div>
  );
}

export function CatalogUnavailable({ reason, retry }: { reason: string; retry: () => void }) {
  return (
    <div className="banner" style={{ padding: 16, gap: 10 }}>
      <span className="row serif" style={{ fontSize: 18, color: "var(--accent)" }}>
        <CloudOff size={20} />
        Catálogo no disponible
      </span>
      <p style={{ fontSize: 13 }}>
        No hemos podido consultar el catálogo de la Red de Bibliotecas. Esto no significa que el libro no exista.
      </p>
      <p className="mono faint" style={{ fontSize: 11 }}>
        {reason}
      </p>
      <button className="btn-primary" onClick={retry} style={{ alignSelf: "flex-start" }}>
        Reintentar
      </button>
    </div>
  );
}

export function PartialNote() {
  return (
    <span className="row" style={{ fontSize: 12, color: "var(--on-loan)" }}>
      <TriangleAlert size={14} />
      Algunas ediciones no se pudieron cargar del catálogo.
    </span>
  );
}

// MARK: - Edition metadata

export function EditionMeta({ edition }: { edition: Edition }) {
  const meta = (label: string, value: ReactNode) => (
    <div className="row" style={{ alignItems: "baseline", gap: 6 }}>
      <span style={{ fontWeight: 700, color: "var(--ink)" }}>{label}</span>
      {value}
    </div>
  );
  const url = edition.detailURL && /^https?:/.test(edition.detailURL) ? edition.detailURL : null;
  return (
    <div className="stack-v muted" style={{ gap: 4, fontSize: 12 }}>
      {edition.year && meta("Año", <span className="mono">{edition.year}</span>)}
      {edition.publication && meta("Publicación", <span>{edition.publication}</span>)}
      {edition.edition && meta("Edición", <span>{edition.edition}</span>)}
      {edition.isbn && meta("ISBN", <span className="mono">{edition.isbn}</span>)}
      {url && (
        <a href={url} target="_blank" rel="noreferrer" className="row" style={{ minHeight: 44, color: "var(--accent)", fontSize: 13, fontWeight: 600, textDecoration: "none" }}>
          Ver ficha en OPAC
          <ExternalLink size={14} />
        </a>
      )}
    </div>
  );
}

// MARK: - Controls

export function ProgressBar({ value, total }: { value: number; total: number }) {
  return (
    <div className="progress" role="progressbar" aria-valuenow={value} aria-valuemax={total}>
      <div style={{ width: `${(100 * value) / Math.max(total, 1)}%` }} />
    </div>
  );
}

export function ToggleButton({ on, onChange, children }: { on: boolean; onChange: (v: boolean) => void; children: ReactNode }) {
  return (
    <button className="toggle-btn" aria-pressed={on} onClick={() => onChange(!on)}>
      {children}
    </button>
  );
}
