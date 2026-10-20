// Préstamos tab. Port of LoansView.swift. The iOS local notifications become a calendar (.ics) export.
import { useState } from "react";
import { CalendarPlus, CircleEllipsis, Landmark, Minus, Plus, RefreshCw, RotateCw, ShieldCheck, UserX, Users } from "lucide-react";
import { openLoansCalendar } from "../core/api";
import { dayString, daysUntilDue, dueDateText, madridDay, renewableFromDay, sortLoans } from "../core/loans";
import { clamp, REMINDER_DAYS_RANGE, type Loan } from "../core/models";
import * as model from "../store";
import { useStore } from "../store";
import { ErrorBanner, Spinner, UpdatedAgo } from "./components";
import { Menu, Screen } from "./nav";

export function LoansScreen() {
  const s = useStore();
  const [menu, setMenu] = useState(false);
  return (
    <Screen
      title="Préstamos"
      large
      onRefresh={s.hasCredentials ? model.refreshLoans : undefined}
      trailing={
        s.hasCredentials && (
          <button className="bar-button" onClick={() => setMenu(true)} aria-label="Opciones">
            <CircleEllipsis size={24} />
          </button>
        )
      }
    >
      {s.hasCredentials ? <LoansList /> : <ReaderLoginForm />}
      {menu && (
        <Menu
          onClose={() => setMenu(false)}
          items={[
            { label: "Actualizar", icon: <RotateCw size={18} />, action: () => void model.refreshLoans() },
            { label: "Cerrar sesión y olvidar el carné", icon: <UserX size={18} />, destructive: true, action: model.disconnectReader },
          ]}
        />
      )}
    </Screen>
  );
}

function LoansList() {
  const s = useStore();
  const n = s.loans.length;
  return (
    <div className="content">
      {s.loansError && <ErrorBanner message={s.loansError} cachedAt={s.loansShowingCache ? s.loansFetchedAt : null} />}
      <div className="row">
        <span className="muted" style={{ fontSize: 13, fontWeight: 600 }}>
          {n === 1 ? "1 préstamo" : `${n} préstamos`}
        </span>
        <span className="spacer" />
        {s.loansLoading ? <Spinner /> : s.loansFetchedAt && <UpdatedAgo date={s.loansFetchedAt} />}
      </div>
      {n === 0 && !s.loansLoading && (
        <p className="card muted" style={{ fontSize: 14, padding: 24, textAlign: "center" }}>
          No tienes libros en préstamo ahora mismo.
        </p>
      )}
      {sortLoans(s.loans).map((loan) => (
        <LoanCard key={loan.barcode} loan={loan} />
      ))}
      <ReminderSettings />
    </div>
  );
}

// MARK: - Login

function ReaderLoginForm() {
  const s = useStore();
  const [card, setCard] = useState("");
  const [password, setPassword] = useState("");
  return (
    <div className="content" style={{ gap: 18 }}>
      <div className="stack-v" style={{ gap: 8 }}>
        <span className="eyebrow" style={{ color: "var(--accent)" }}>
          Mi biblioteca
        </span>
        <h2 className="serif" style={{ fontSize: 28, lineHeight: 1.15 }}>
          Tus préstamos, siempre a mano
        </h2>
        <p className="muted">
          Conéctate con tu carné de la Red de Bibliotecas para ver qué tienes en préstamo y añadir las fechas de devolución a
          tu calendario.
        </p>
      </div>
      <form
        className="card stack-v"
        style={{ padding: 16, gap: 14 }}
        onSubmit={(e) => {
          e.preventDefault();
          (document.activeElement as HTMLElement | null)?.blur();
          void model.connectReader(card, password);
        }}
      >
        <label className="stack-v" style={{ gap: 6 }}>
          <span className="eyebrow">Nº de carné</span>
          <span className="field">
            <input
              className="mono"
              value={card}
              onChange={(e) => setCard(e.target.value)}
              placeholder="0000000000"
              autoComplete="username"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              enterKeyHint="next"
            />
          </span>
        </label>
        <label className="stack-v" style={{ gap: 6 }}>
          <span className="eyebrow">Contraseña</span>
          <span className="field">
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              autoComplete="current-password"
              enterKeyHint="go"
            />
          </span>
        </label>
        {s.loansError && <p style={{ fontSize: 12, fontWeight: 500, color: "var(--accent)" }}>{s.loansError}</p>}
        <button type="submit" className="btn-primary btn-full" disabled={s.loansLoading}>
          {s.loansLoading && <Spinner size={16} />}
          Conectar
        </button>
      </form>
      <p className="row muted" style={{ alignItems: "flex-start", fontSize: 12, gap: 8 }}>
        <ShieldCheck size={16} style={{ flex: "none", marginTop: 1 }} />
        El carné y la contraseña se guardan solo en este navegador. Para consultar tus préstamos pasan por el servidor de
        Zahorí, que no los guarda, hasta el catálogo de la Comunidad de Madrid. Puedes borrarlos en cualquier momento.
      </p>
    </div>
  );
}

// MARK: - Loan card

function dueBadge(days: number | null): { text: string; tone: string } {
  if (days === null) return { text: "Fecha desconocida", tone: "" };
  if (days < 0) return { text: days === -1 ? "Venció ayer" : `Vencido hace ${-days} días`, tone: "tone-accent" };
  if (days === 0) return { text: "Vence hoy", tone: "tone-accent" };
  if (days === 1) return { text: "Vence mañana", tone: "tone-loan" };
  if (days <= 5) return { text: `Vence en ${days} días`, tone: "tone-loan" };
  return { text: `Quedan ${days} días`, tone: "tone-available" };
}

/** Mirrors the OPAC rule: renewable N days before the due date, if not reserved and under the limit. */
function renewalNote(loan: Loan): string | null {
  if (loan.reservations > 0) return "Reservado por otros lectores: no se podrá renovar.";
  const from = renewableFromDay(loan);
  if (from === null) return loan.renewalsMax > 0 ? "Ya no quedan renovaciones." : null;
  return from <= madridDay(new Date()) ? "Ya se puede renovar en el catálogo." : `Renovable en el catálogo desde el ${dayString(from)}.`;
}

function LoanCard({ loan }: { loan: Loan }) {
  const badge = dueBadge(daysUntilDue(loan, new Date()));
  const note = renewalNote(loan);
  return (
    <div className="card stack-v" style={{ padding: 14, gap: 10 }}>
      <div className="row" style={{ alignItems: "baseline" }}>
        <span className={`pill ${badge.tone}`} style={{ fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.6 }}>
          {badge.text}
        </span>
        <span className="spacer" />
        <span className="mono" style={{ fontSize: 13, fontWeight: 600 }} aria-label={`Devolver antes del ${dueDateText(loan)}`}>
          {dueDateText(loan)}
        </span>
      </div>
      <h3 className="serif" style={{ fontSize: 19 }}>
        {loan.title}
      </h3>
      <span className="row muted" style={{ fontSize: 13, fontWeight: 600, gap: 6 }}>
        <Landmark size={15} />
        {loan.branch}
      </span>
      <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
        {loan.shelfmark && <span className="shelfmark">{loan.shelfmark}</span>}
        <span
          className="row mono muted"
          style={{ fontSize: 12, gap: 4 }}
          aria-label={`Renovaciones: ${loan.renewalsUsed} de ${loan.renewalsMax}`}
        >
          <RefreshCw size={13} />
          {loan.renewalsUsed}/{loan.renewalsMax}
        </span>
        {loan.reservations > 0 && (
          <span className="row" style={{ fontSize: 12, fontWeight: 600, gap: 4, color: "var(--on-loan)" }}>
            <Users size={14} />
            {loan.reservations === 1 ? "1 reserva" : `${loan.reservations} reservas`}
          </span>
        )}
      </div>
      {note && (
        <p className="faint" style={{ fontSize: 12 }}>
          {note}
        </p>
      )}
    </div>
  );
}

// MARK: - Reminders → calendar

function ReminderSettings() {
  const s = useStore();
  const days = s.settings.reminderDaysBefore;
  const setDays = (d: number) => model.updateSettings({ reminderDaysBefore: clamp(d, REMINDER_DAYS_RANGE) });
  return (
    <div className="card stack-v" style={{ padding: 16, gap: 10 }}>
      <span className="eyebrow">Avisos de devolución</span>
      <div className="row" style={{ minHeight: 44 }}>
        <span className="spacer" style={{ fontSize: 14 }}>
          {days === 1 ? "1 día antes, a las 10:00" : `${days} días antes, a las 10:00`}
        </span>
        <span className="stepper">
          <button onClick={() => setDays(days - 1)} disabled={days <= REMINDER_DAYS_RANGE[0]} aria-label="Menos días">
            <Minus size={18} />
          </button>
          <button onClick={() => setDays(days + 1)} disabled={days >= REMINDER_DAYS_RANGE[1]} aria-label="Más días">
            <Plus size={18} />
          </button>
        </span>
      </div>
      <p className="muted" style={{ fontSize: 12 }}>
        Los avisos los da el Calendario de tu iPhone: también uno el mismo día de la devolución. Si renuevas un libro, vuelve a
        añadirlos.
      </p>
      <button className="btn-primary btn-full" onClick={() => openLoansCalendar(s.loans, days)} disabled={s.loans.length === 0}>
        <CalendarPlus size={18} />
        Añadir al Calendario
      </button>
    </div>
  );
}
