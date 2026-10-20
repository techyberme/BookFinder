// Estantería tab. Port of ShelfView.swift, OnboardingView.swift, RecommendationsBanner.swift, BookDetailView.swift.
import { useState } from "react";
import { ChevronRight, ChevronsUpDown, ListFilter, MapPin, RefreshCw, RotateCw } from "lucide-react";
import type { Book } from "../core/models";
import { initials } from "../core/goodreads";
import * as model from "../store";
import { useStore } from "../store";
import {
  CatalogUnavailable,
  Cover,
  EditionMeta,
  ErrorBanner,
  GroupedCopies,
  PartialNote,
  ProgressBar,
  SkeletonCard,
  Spinner,
  StatusPill,
  ToggleButton,
  UpdatedAgo,
} from "./components";
import { Screen, Sheet, useNav } from "./nav";

export function ShelfScreen() {
  const s = useStore();
  const [showProfile, setShowProfile] = useState(false);
  const hasProfile = s.settings.goodreadsUserID != null;

  return (
    <Screen
      title="Estantería"
      large
      onRefresh={hasProfile ? model.reloadShelf : undefined}
      trailing={
        hasProfile && (
          <button onClick={() => setShowProfile(true)} aria-label="Configurar perfil de Goodreads">
            <ProfileBadge />
          </button>
        )
      }
    >
      {hasProfile ? <ShelfContent /> : <Onboarding />}
      {showProfile && (
        <Sheet title="Perfil de Goodreads" onClose={() => setShowProfile(false)}>
          {(close) => (
            <div className="content" style={{ gap: 18, paddingTop: 8 }}>
              <p className="muted" style={{ fontSize: 14 }}>
                Sincroniza tu lista de lectura con las bibliotecas
              </p>
              <ProfileForm onDone={close} />
              <button
                className="btn-secondary btn-full btn-destructive"
                onClick={() => {
                  model.disconnect();
                  close();
                }}
              >
                Desconectar perfil
              </button>
            </div>
          )}
        </Sheet>
      )}
    </Screen>
  );
}

function ShelfContent() {
  const s = useStore();
  const [filter, setFilter] = useState("");
  const [onlyAvailable, setOnlyAvailable] = useState(false);
  const f = filter.trim().toLowerCase();
  const filtered = s.books.filter(
    (b) =>
      (!f || b.title.toLowerCase().includes(f) || b.author.toLowerCase().includes(f)) &&
      (!onlyAvailable || model.availability(s, b)?.state === "available"),
  );
  const count = s.books.length;
  const showProgress = s.isCheckingBatch || (s.batchTotal > 0 && s.batchCompleted < s.batchTotal);

  return (
    <div className="content">
      {s.shelfError && <ErrorBanner message={s.shelfError} cachedAt={s.shelfCachedAt} />}
      {s.isLoadingShelf && count === 0 && [0, 1, 2, 3].map((i) => <SkeletonCard key={i} />)}
      {count > 0 && (
        <>
          <RecommendationsBanner />
          <div className="stack-v" style={{ gap: 12 }}>
            <div className="row muted" style={{ gap: 6, fontSize: 12, fontWeight: 600, flexWrap: "wrap" }}>
              <span>{count === 1 ? `1 libro en '${s.settings.shelf}'` : `${count} libros en '${s.settings.shelf}'`}</span>
              <span>•</span>
              <span style={{ color: "var(--available)" }}>{model.availableCount(s)} disponibles en Madrid</span>
            </div>
            <div className="row" style={{ gap: 10 }}>
              <label className="field on-card spacer">
                <ListFilter size={18} className="icon" />
                <input
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                  placeholder="Filtrar libros..."
                  autoCapitalize="none"
                  enterKeyHint="search"
                />
              </label>
              <ToggleButton on={onlyAvailable} onChange={setOnlyAvailable}>
                Solo disponibles
              </ToggleButton>
            </div>
            <button className="btn-primary btn-full" onClick={model.checkAll} disabled={s.isCheckingBatch}>
              {s.isCheckingBatch && <Spinner size={16} />}
              {s.isCheckingBatch ? "Comprobando catálogo..." : "Comprobar todos en catálogo"}
            </button>
            {showProgress && (
              <div className="stack-v" style={{ gap: 6 }}>
                <ProgressBar value={s.batchCompleted} total={s.batchTotal} />
                <span className="mono muted" style={{ fontSize: 12, fontWeight: 600 }}>
                  {s.batchCompleted} de {s.batchTotal}
                </span>
              </div>
            )}
          </div>
          {filtered.map((book) =>
            s.checks[book.bookID]?.phase === "checking" && s.isCheckingBatch ? (
              <SkeletonCard key={book.bookID} />
            ) : (
              <BookCard key={book.bookID} book={book} />
            ),
          )}
          {filtered.length === 0 && (
            <p className="card muted" style={{ fontSize: 13, padding: 24, textAlign: "center" }}>
              No hay libros que coincidan con los filtros actuales.
            </p>
          )}
        </>
      )}
    </div>
  );
}

// MARK: - Book card

function BookCard({ book }: { book: Book }) {
  const s = useStore();
  const nav = useNav();
  const check = s.checks[book.bookID];
  const a = model.availability(s, book);
  return (
    <div className="card stack-v" style={{ padding: 14, gap: 12 }}>
      <div className="row" style={{ alignItems: "flex-start", gap: 14 }}>
        <Cover url={book.coverImageURL} />
        <div className="stack-v" style={{ gap: 4, minWidth: 0 }}>
          <span className="serif clamp-3" style={{ fontSize: 17 }}>
            {book.title}
          </span>
          <span className="muted clamp-1" style={{ fontSize: 13, fontWeight: 500 }}>
            {book.author || "Autor no especificado"}
          </span>
          {book.isbn && (
            <span className="mono faint" style={{ fontSize: 11 }}>
              ISBN: {book.isbn}
            </span>
          )}
          {check?.cachedAt && <UpdatedAgo date={check.cachedAt} />}
        </div>
      </div>
      <div className="divider" />
      {/* The status wraps onto its own line rather than shrinking to "D…" next to both buttons. */}
      <div className="row" style={{ flexWrap: "wrap", rowGap: 10 }}>
        <span className="row spacer" style={{ minWidth: 140 }}>
          <StatusPill check={check} availability={a} />
        </span>
        <span className="row" style={{ marginLeft: "auto" }}>
          {a?.firstEdition && a.firstEdition.copies.length > 0 && (
            <button className="btn-secondary" onClick={() => nav.push("Ejemplares", <BookDetail book={book} />)}>
              Ejemplares ({a.totalCopies})
            </button>
          )}
          <button className="btn-primary" onClick={() => model.check(book)} disabled={check?.phase === "checking"}>
            {check?.phase === "checked" ? "Recomprobar" : "Comprobar"}
          </button>
        </span>
      </div>
    </div>
  );
}

// MARK: - Recomendaciones

function RecommendationsBanner() {
  const s = useStore();
  const books = model.recommendedBooks(s);
  return (
    <section
      className="stack-v"
      style={{
        gap: 14,
        padding: 18,
        borderRadius: 18,
        background: "linear-gradient(135deg, var(--accent-bg), var(--card))",
        border: "1px solid color-mix(in srgb, var(--accent) 25%, transparent)",
      }}
    >
      <div className="row" style={{ alignItems: "flex-start" }}>
        <div className="stack-v spacer" style={{ gap: 4 }}>
          <span className="eyebrow" style={{ color: "var(--accent)" }}>
            Recomendaciones
          </span>
          <h2 className="serif" style={{ fontSize: 24 }}>
            Disponibles hoy
          </h2>
          <p className="muted" style={{ fontSize: 13 }}>
            Libros de tu lista con disponibilidad inmediata para recoger hoy.
          </p>
        </div>
        <button
          className="bar-button"
          style={{ color: "var(--ink)" }}
          onClick={model.findRecommendations}
          disabled={s.isFindingRecommendations}
          aria-label="Nuevas sugerencias"
        >
          <RefreshCw size={20} />
        </button>
      </div>
      {s.isFindingRecommendations ? (
        <div className="row muted" style={{ gap: 10, minHeight: 44, fontSize: 12 }}>
          <Spinner />
          Buscando libros con disponibilidad inmediata en Madrid...
        </div>
      ) : books.length === 0 && s.recommendationsSearched ? (
        <p className="muted italic" style={{ fontSize: 12 }}>
          No se encontraron recomendaciones con ejemplares disponibles inmediatamente entre las muestras analizadas. Pruebe a
          pulsar "Nuevas sugerencias".
        </p>
      ) : (
        books.map((b) => <RecommendationCard key={b.bookID} book={b} />)
      )}
    </section>
  );
}

function RecommendationCard({ book }: { book: Book }) {
  const s = useStore();
  const nav = useNav();
  const a = model.availability(s, book);
  return (
    <button
      className="card row"
      style={{ padding: 12, gap: 14, alignItems: "flex-start", textAlign: "left", width: "100%" }}
      onClick={() => nav.push("Ejemplares", <BookDetail book={book} />)}
      aria-description="Ver ejemplares"
    >
      <Cover url={book.coverImageURL} width={76} />
      <div className="stack-v spacer" style={{ gap: 6, minWidth: 0 }}>
        <span className="row eyebrow" style={{ color: "var(--available)", gap: 6 }}>
          <span className="dot" style={{ width: 7, height: 7 }} />
          Disponible ahora
        </span>
        <span className="serif clamp-2" style={{ fontSize: 18 }}>
          {book.title}
        </span>
        <span className="muted clamp-1" style={{ fontSize: 13, fontWeight: 500 }}>
          {book.author || "Autor no especificado"}
        </span>
        <span className="row" style={{ gap: 4, fontSize: 12, fontWeight: 600, minWidth: 0 }}>
          <MapPin size={14} color="var(--accent)" style={{ flex: "none" }} />
          <span className="clamp-1">{a?.bestMatchLibrary ?? "Biblioteca de la red"}</span>
          {a?.bestMatchDistanceKm != null && a.bestMatchDistanceKm > 0 && (
            <span className="mono faint" style={{ fontSize: 11, flex: "none" }}>
              ({a.bestMatchDistanceKm.toFixed(1)} km)
            </span>
          )}
        </span>
      </div>
      <ChevronRight size={18} className="faint" style={{ marginTop: 4, flex: "none" }} />
    </button>
  );
}

// MARK: - Book detail ("Ejemplares")

function BookDetail({ book }: { book: Book }) {
  const s = useStore();
  const check = s.checks[book.bookID];
  const a = model.availability(s, book);
  const edition = a?.firstEdition;
  const outcome = check?.result?.outcome;
  return (
    <Screen
      title="Ejemplares"
      trailing={
        <button className="bar-button" onClick={() => model.check(book)} disabled={check?.phase === "checking"} aria-label="Recomprobar">
          <RotateCw size={20} />
        </button>
      }
    >
      <div className="content" style={{ gap: 18, paddingTop: 8 }}>
        <div className="row" style={{ alignItems: "flex-start", gap: 16 }}>
          <Cover url={book.coverImageURL} width={88} />
          <div className="stack-v" style={{ gap: 6, alignItems: "flex-start", minWidth: 0 }}>
            <h2 className="serif" style={{ fontSize: 22 }}>
              {edition?.title ?? book.title}
            </h2>
            <span className="muted" style={{ fontSize: 14, fontWeight: 500 }}>
              {edition?.author ?? book.author}
            </span>
            <StatusPill check={check} availability={a} />
            {check?.cachedAt && <UpdatedAgo date={check.cachedAt} />}
          </div>
        </div>
        {edition ? (
          <>
            <EditionMeta edition={edition} />
            {a?.isPartial && <PartialNote />}
            <div className="card" style={{ padding: 14 }}>
              <GroupedCopies copies={edition.copies} proximity={model.proximity(s)} />
            </div>
          </>
        ) : outcome?.kind === "catalogUnavailable" ? (
          <CatalogUnavailable reason={outcome.reason} retry={() => model.check(book)} />
        ) : check?.phase === "checking" ? (
          <SkeletonCard />
        ) : (
          <button className="btn-primary" style={{ alignSelf: "flex-start" }} onClick={() => model.check(book)}>
            Comprobar
          </button>
        )}
      </div>
    </Screen>
  );
}

// MARK: - Profile

function ProfileBadge() {
  const s = useStore();
  return (
    <span className="row" style={{ gap: 8, minHeight: 44, textAlign: "left" }}>
      <span className="badge-circle">{initials(s.settings.goodreadsUserName)}</span>
      <span className="stack-v">
        <span style={{ fontSize: 12, fontWeight: 700 }}>{s.settings.goodreadsUserName ?? "Mi Perfil"}</span>
        <span className="mono muted" style={{ fontSize: 10 }}>
          {s.settings.shelf}
        </span>
      </span>
    </span>
  );
}

function Onboarding() {
  return (
    <div className="content" style={{ gap: 20 }}>
      <div className="stack-v" style={{ gap: 8 }}>
        <span className="eyebrow" style={{ color: "var(--accent)" }}>
          Zahorí
        </span>
        <h2 className="serif" style={{ fontSize: 30, lineHeight: 1.15 }}>
          Conecta tu estantería de Goodreads
        </h2>
        <p className="muted">
          Comprueba automáticamente la disponibilidad de los libros de tu lista en las bibliotecas públicas de Madrid.
        </p>
      </div>
      <div className="card" style={{ padding: 16 }}>
        <ProfileForm />
      </div>
    </div>
  );
}

const SHELVES = ["to-read", "currently-reading", "read"];

/** Shared by onboarding and the profile sheet. */
function ProfileForm({ onDone }: { onDone?: () => void }) {
  const s = useStore();
  const [userInput, setUserInput] = useState(s.settings.goodreadsUserID ?? "");
  const [shelf, setShelf] = useState(s.settings.shelf);
  const hasProfile = s.settings.goodreadsUserID != null;

  const submit = async (input: string, sh: string) => {
    await model.connect(input, sh);
    if (model.getState().settings.goodreadsUserID != null) onDone?.();
  };

  return (
    <form
      className="stack-v"
      style={{ gap: 14 }}
      onSubmit={(e) => {
        e.preventDefault();
        void submit(userInput, shelf);
      }}
    >
      <label className="stack-v" style={{ gap: 6 }}>
        <span className="eyebrow">ID de usuario o enlace de perfil</span>
        <span className="field">
          <input
            value={userInput}
            onChange={(e) => setUserInput(e.target.value)}
            placeholder="155193797-javier-bermejo · goodreads.com/user/show/…"
            inputMode="url"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
          />
        </span>
      </label>
      <label className="stack-v" style={{ gap: 6 }}>
        <span className="eyebrow">Estantería (shelf)</span>
        <span className="row" style={{ gap: 8 }}>
          <span className="field spacer">
            <input
              className="mono"
              value={shelf}
              onChange={(e) => setShelf(e.target.value)}
              placeholder="to-read, currently-reading, read..."
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
            />
          </span>
          {/* iOS Menu of shelves → a native <select> picker */}
          <span className="bar-button" style={{ position: "relative" }} aria-label="Elegir estantería">
            <ChevronsUpDown size={20} />
            <select
              aria-label="Elegir estantería"
              value=""
              onChange={(e) => e.target.value && setShelf(e.target.value)}
              style={{ position: "absolute", inset: 0, opacity: 0, fontSize: 16 }}
            >
              <option value="" disabled>
                Estantería
              </option>
              {SHELVES.map((sh) => (
                <option key={sh} value={sh}>
                  {sh}
                </option>
              ))}
            </select>
          </span>
        </span>
      </label>
      {s.shelfError && !hasProfile && (
        <p style={{ fontSize: 12, fontWeight: 500, color: "var(--accent)" }}>{s.shelfError}</p>
      )}
      <button className="btn-primary btn-full" type="submit" disabled={s.isLoadingShelf}>
        {s.isLoadingShelf && <Spinner size={16} />}
        Sincronizar
      </button>
      <button
        type="button"
        className="btn-plain"
        onClick={() => {
          setUserInput("177587843");
          setShelf("to-read");
          void submit("177587843", "to-read");
        }}
      >
        Cargar cuenta demo
      </button>
    </form>
  );
}
