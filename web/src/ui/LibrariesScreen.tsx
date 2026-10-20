// Bibliotecas tab. Port of LibrarySettingsView.swift ("Bibliotecas Preferidas & Radio").
import { useEffect, useState } from "react";
import { CircleCheck, CirclePlus, LocateFixed, LocateOff, Search } from "lucide-react";
import { libraryById, sortedLibraries, type Library } from "../core/libraries";
import { clamp, RADIUS_RANGE } from "../core/models";
import * as model from "../store";
import { useStore } from "../store";
import { Screen } from "./nav";

export function LibrariesScreen() {
  const s = useStore();
  const [query, setQuery] = useState("");
  const selectedIDs = s.settings.selectedLibraryIDs;
  const selected = selectedIDs.flatMap((id) => libraryById(id) ?? []);

  // Port of `filterAndRenderDropdown`: name / district / municipality contains, excluding selected.
  const q = query.trim().toLowerCase();
  const filtered = sortedLibraries.filter(
    (l) =>
      !selectedIDs.includes(l.id) &&
      (!q || l.name.toLowerCase().includes(q) || l.district.toLowerCase().includes(q) || l.municipality.toLowerCase().includes(q)),
  );

  return (
    <Screen
      title="Bibliotecas"
      large
      bodyTop={
        <div style={{ padding: "0 16px 12px" }}>
          <label className="search-field">
            <Search size={17} />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Buscar bibliotecas (ej: Eugenio Trías, Retiro…)"
              enterKeyHint="search"
            />
          </label>
        </div>
      }
    >
      <div className="content" style={{ gap: 24 }}>
        <section className="list-section">
          <span className="eyebrow">Radio de proximidad</span>
          <div className="list-group" style={{ padding: "6px 16px" }}>
            <RadiusControl />
          </div>
          <span className="list-footer">Recomienda sucursales alternativas dentro del radio.</span>
        </section>

        <section className="list-section">
          <span className="eyebrow">Bibliotecas de referencia</span>
          <div className="list-group">
            {selected.length === 0 && (
              <>
                <div className="list-row plain muted italic" style={{ fontSize: 13 }}>
                  Ninguna seleccionada: las distancias se miden desde {model.origin(s).name}.
                </div>
                {!s.coordinate && (
                  <button
                    className="list-row plain"
                    style={{ color: "var(--accent)", fontSize: 14, fontWeight: 600, opacity: s.locationDenied ? 0.5 : 1 }}
                    disabled={s.locationDenied}
                    onClick={() => model.requestLocationIfNeeded(true)}
                  >
                    {s.locationDenied ? <LocateOff size={18} /> : <LocateFixed size={18} />}
                    {s.locationDenied ? "Ubicación denegada: se usa el centro de Madrid" : "Usar mi ubicación"}
                  </button>
                )}
              </>
            )}
            {selected.map((lib) => (
              <LibraryRow key={lib.id} lib={lib} selected />
            ))}
          </div>
        </section>

        <section className="list-section">
          <span className="eyebrow">Red de bibliotecas</span>
          <div className="list-group">
            {filtered.map((lib) => (
              <LibraryRow key={lib.id} lib={lib} selected={false} />
            ))}
          </div>
        </section>
      </div>
    </Screen>
  );
}

/** Two-way sync: the slider writes the setting; the field writes it while typing a number and clamps on blur. */
function RadiusControl() {
  const s = useStore();
  const radius = s.settings.radiusKm;
  const [text, setText] = useState(String(radius));
  const [focused, setFocused] = useState(false);
  useEffect(() => {
    if (!focused) setText(String(radius));
  }, [radius, focused]);

  const commit = () => {
    const v = clamp(parseInt(text, 10) || 1, RADIUS_RANGE);
    model.updateSettings({ radiusKm: v });
    setText(String(v));
  };

  return (
    <div className="stack-v" style={{ gap: 10 }}>
      <div className="row">
        <input
          className="mono"
          inputMode="numeric"
          pattern="[0-9]*"
          aria-label="Radio en kilómetros"
          value={text}
          onFocus={() => setFocused(true)}
          onBlur={() => {
            setFocused(false);
            commit();
          }}
          onKeyDown={(e) => e.key === "Enter" && (e.target as HTMLInputElement).blur()}
          onChange={(e) => {
            setText(e.target.value);
            const v = parseInt(e.target.value, 10);
            if (!Number.isNaN(v)) model.updateSettings({ radiusKm: clamp(v, RADIUS_RANGE) });
          }}
          style={{
            width: 64,
            height: 44,
            textAlign: "right",
            fontSize: 20,
            fontWeight: 600,
            padding: "0 10px",
            border: 0,
            outline: 0,
            borderRadius: 10,
            background: "var(--chip)",
          }}
        />
        <span style={{ fontSize: 15, fontWeight: 600 }}>km</span>
      </div>
      <div className="row" style={{ gap: 10 }}>
        <span className="mono" style={{ fontSize: 11 }}>
          1 km
        </span>
        <input
          type="range"
          min={1}
          max={20}
          step={1}
          value={radius}
          aria-label="Radio de proximidad"
          onChange={(e) => model.updateSettings({ radiusKm: clamp(Number(e.target.value), RADIUS_RANGE) })}
        />
        <span className="mono" style={{ fontSize: 11 }}>
          20 km
        </span>
      </div>
    </div>
  );
}

function LibraryRow({ lib, selected }: { lib: Library; selected: boolean }) {
  return (
    <button className="list-row" onClick={() => model.toggleLibrary(lib.id)} aria-pressed={selected} aria-description={selected ? "Quitar" : "Añadir"}>
      {selected ? (
        <CircleCheck size={24} fill="var(--accent)" color="var(--card)" style={{ flex: "none" }} />
      ) : (
        <CirclePlus size={24} className="faint" strokeWidth={1.6} style={{ flex: "none" }} />
      )}
      <span className="stack-v" style={{ gap: 2 }}>
        <span style={{ fontSize: 14, fontWeight: 700 }}>{lib.name}</span>
        <span className="muted" style={{ fontSize: 12 }}>
          {lib.district} • {lib.municipality}
        </span>
      </span>
    </button>
  );
}
