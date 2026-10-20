// Ports of the pure helpers in ZahoriCore/GoodreadsText.swift (= backend/goodreads_service.py).
// Title cleaning for search stays on the server (/api/check), where the Python reference runs it.

/** `extract_goodreads_user_id` */
export function userIDFrom(input: string): string {
  const s = input.trim();
  if (!s) return "";
  if (/^\d+$/.test(s)) return s;
  return (
    /\/user\/show\/(\d+)/.exec(s)?.[1] ??
    /\/review\/list(?:_rss)?\/(\d+)/.exec(s)?.[1] ??
    /\b(\d{5,12})\b/.exec(s)?.[1] ??
    s
  );
}

/** `extract_goodreads_user_name`, URL-slug branch ("155193797-javier-bermejo" → "Javier Bermejo"). */
export function userNameFrom(input: string): string | null {
  const m = /\/user\/show\/\d+[-_]([a-zA-Z0-9_-]+)/.exec(input.trim());
  if (!m) return null;
  const slug = m[1].split("?")[0].split("/")[0];
  const name = slug
    .split(/[-_]+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase() + w.slice(1).toLowerCase())
    .join(" ");
  return name || null;
}

/** `getInitials` in frontend/app.js (ProfileBadge on iOS). */
export function initials(name: string | null): string {
  const n = name?.trim();
  if (!n) return "GR";
  const parts = n.split(/\s+/);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  if (parts[0].length >= 2 && !/^\d+$/.test(parts[0])) return parts[0].slice(0, 2).toUpperCase();
  return "GR";
}
