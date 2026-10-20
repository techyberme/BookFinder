# Zahorí — web (iPhone home-screen app)

A web version of the iOS app (`ios/`) that someone can install from Safari with **Add to Home Screen**, with no Apple developer account. It has the same four tabs (Estantería, Buscar, Préstamos, Bibliotecas), the same screens, colours, fonts and rules, and saves the same data on the device.

- **Frontend:** React 18 + Vite + TypeScript in `web/`. It ports the iOS logic (proximity, availability summaries, loan dates) and is tested against the same Python-generated `golden.json` as the iOS tests.
- **Backend:** the existing FastAPI app (`backend/`). A browser can't call the library catalog or Goodreads directly (no CORS, cookie sessions), so the server makes the same requests the iOS app makes from the phone. New endpoints: `/api/check`, `/api/reader/loans`, `/api/reader/calendar.ics`.

## Run locally

```bash
# 1. Backend (from the repository root) → http://127.0.0.1:8000
python3 -m pip install -r requirements.txt
python3 run.py

# 2. Frontend, in a second terminal → http://localhost:5173 (proxies /api to port 8000)
cd web
npm install
npm run dev
```

To see the iPhone layout on a Mac, open Safari → *Develop → Enter Responsive Design Mode* → iPhone 14 (390×844).

Tests: `npm test` in `web/` (25 tests), `python3 -m pytest` at the root (includes `tests/test_reader.py`).

To try it on your own iPhone before deploying, run `npm run dev -- --host` and open `http://<your-mac's-IP>:5173`. The phone must be on the same Wi-Fi. Location only works over HTTPS, so it falls back to Madrid centre.

## Deploy for free (Vercel)

Vercel's free Hobby plan hosts the static site **and** runs the Python API as a serverless function, all in one project. `vercel.json` at the repository root sets everything up. Netlify and Firebase Hosting can't run the Python backend for free, so they would need it hosted somewhere else.

1. Commit everything, including `backend/reader.py`, `api/index.py`, `vercel.json` and `web/`, and push the repository to GitHub. `htmls/` holds your personal data: don't commit it. `.vercelignore` also keeps it out of uploads.
2. Go to <https://vercel.com>, sign in with GitHub, choose **Add New → Project** and import the repository. Leave **Root Directory** as the repository root; the build settings come from `vercel.json`.
3. Click **Deploy**. You get a URL such as `https://zahori-xxxx.vercel.app`.

Alternatively, run `npx vercel` and then `npx vercel --prod` from the repository root.

The function runs in Paris (`cdg1`), close to the Madrid servers. Each request gets up to 120 s, and a book check usually takes 5–10 s.

## Add it to the home screen on iPhone

1. Open the URL in **Safari**. Other browsers on iPhone can do this on iOS 16.4+, but Safari is the reliable one.
2. Tap the **Share** button (square with an up arrow).
3. Scroll down and tap **Add to Home Screen** (*Añadir a pantalla de inicio*).
4. Keep the name **Zahorí** and tap **Add**. Open it from the icon: it runs full screen, without Safari's bars.

## Differences from the iOS app

| iOS | Web | Why |
|---|---|---|
| Talks to the catalog directly from the phone | Goes through the Zahorí server | Browsers block cross-site requests to the catalog |
| Card and password in the Keychain | In the browser's `localStorage` on that phone, saved only after a successful login; they go through the server to the catalog and are never stored or logged there | No Keychain on the web |
| Local notifications N days before and on the due date at 10:00 | **Añadir al Calendario** downloads an `.ics` with the same two alerts, which Calendar then delivers | Safari can't schedule local notifications; Web Push would need a server and scheduled jobs |
| Reminder on/off switch | Removed; the days stepper sets the calendar alerts | Nothing to switch off: the alerts live in Calendar |
| Location asked on first launch | Asked once; afterwards only from *Bibliotecas → Usar mi ubicación* | Safari would ask again on every launch |
| Profile sheet stays open until Recomendaciones finish | Closes as soon as the shelf is loaded | Shorter wait; the recommendations keep loading in the background |

Everything else matches the iOS app: the catalog unavailable vs not in catalog distinction, the offline copies with "actualizado hace…", the 3-at-a-time checks, random recommendations, proximity groups recalculated live, the 1–20 km radius, and loan badges and renewal notes on Madrid dates.
