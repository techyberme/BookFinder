// Port of the date logic in ZahoriCore/Loans.swift. OPAC dates are Madrid time regardless of the device,
// so days are computed on the Madrid calendar ("day numbers" = days since 1970-01-01 of a Madrid date).
import type { Loan } from "./models";

const madridDate = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Madrid",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

const dayNum = (y: number, m: number, d: number) => Date.UTC(y, m - 1, d) / 86_400_000;

/** Today's Madrid calendar day. */
export function madridDay(now: Date): number {
  const [y, m, d] = madridDate.format(now).split("-").map(Number);
  return dayNum(y, m, d);
}

/** "DD/MM/YYYY" or "DD/MM/YYYY HH:MM" → { day, minutes } (no time = end of day, 23:59). */
export function parseOPACDate(text: string): { day: number; minutes: number } | null {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?/.exec(text.trim());
  if (!m) return null;
  return { day: dayNum(+m[3], +m[2], +m[1]), minutes: m[4] ? +m[4] * 60 + +m[5] : 23 * 60 + 59 };
}

/** "DD/MM/YYYY" of a day number. */
export function dayString(day: number): string {
  const d = new Date(day * 86_400_000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
}

/** "DD/MM/YYYY" part of the due date, as shown to the user. */
export const dueDateText = (loan: Loan) => loan.dueDateTime.slice(0, 10);

/** Whole Madrid days from `now` to the due date. 0 = due today, negative = overdue. */
export function daysUntilDue(loan: Loan, now: Date): number | null {
  const due = parseOPACDate(loan.dueDateTime);
  return due ? due.day - madridDay(now) : null;
}

export const hasRenewalsLeft = (loan: Loan) => loan.renewalsUsed < loan.renewalsMax;

/** First day renewal is possible (due date − window), or null if no renewals are left. */
export function renewableFromDay(loan: Loan): number | null {
  const due = parseOPACDate(loan.dueDateTime);
  return hasRenewalsLeft(loan) && due ? due.day - loan.renewalWindowDays : null;
}

/** Soonest first; unreadable dates last. */
export function sortLoans(loans: Loan[]): Loan[] {
  const key = (l: Loan) => {
    const d = parseOPACDate(l.dueDateTime);
    return d ? d.day * 1440 + d.minutes : Infinity;
  };
  return [...loans].sort((a, b) => key(a) - key(b));
}
