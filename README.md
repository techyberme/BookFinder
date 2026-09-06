# 📖 Zahorí — Buscador de Libros & Goodreads (Bibliotecas de Madrid)

A functional, high-performance web tool and Progressive Web Application (PWA) to search book availability across the **Madrid Public Libraries Network** (*Red de Bibliotecas de la Comunidad de Madrid* - AbsysNet catalog) with **library proximity filtering**, **Goodreads shelf synchronization**, and **geospatial recommendations**.

---

## 🚀 Quick Start for macOS (Plug & Play)

Get Zahorí running on your Mac in **one command** with an automatic **Desktop App Icon**:

```bash
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/Zahori.git
cd Zahori

# 2. Run automatic macOS setup
./setup_mac.sh
```

✨ **That's it!** An icon named **Zahorí** will be placed directly on your macOS Desktop. Just double-click it to start the server and open the app in your browser.

---

## 🌟 Key Features

* **📚 Goodreads Shelf Synchronization**:
  * Syncs public Goodreads shelves (`to-read`, `currently-reading`, `read`, etc.) via XML/RSS.
  * Automatically extracts reader display names and sanitizes book titles (removes edition metadata, series tags, and noise to maximize catalog search precision).
  * **"Recomendaciones" Hero Banner**: Automatically scans your reading list and highlights books with **immediate physical availability** in Madrid libraries.
  * On-demand single book or batch availability check with bounded concurrency (max 3 concurrent OPAC requests).

* **📍 Geospatial Proximity & Library Filtering**:
  * Select your favorite reference libraries (e.g. *Eugenio Trías*, *José Acuña*, *Retiro*, *Chamartín*).
  * Set a proximity radius (1 to 20 km) with a two-way synchronized range slider.
  * Results are grouped into:
    1. **Bibliotecas Seleccionadas**: Live status and return due dates for your chosen branches.
    2. **Alternativas Cercanas**: Nearby branches within your selected radius that hold available copies (e.g. `📍 1.4 km de Eugenio Trías`).
    3. **Otras Bibliotecas**: Collapsible list of remaining network libraries.

* **⚡ Real-Time AbsysNet Scraper Engine**:
  * Handles dynamic session handshakes, URL path tokens, cookie jars, and multi-part form submissions (`ACC=131`, `FORM=2`) for the Madrid AbsysNet OPAC.
  * Extracts exact physical availability: branch name, room/location (*Depósito*, *Sala adultos*), signaturas / shelf marks, format, loan status (*Disponible* vs *Prestado*), and return due dates (*DD/MM/YYYY*).

* **📱 Mobile-First PWA (iOS & Android)**:
  * Full Progressive Web App with `<meta name="viewport" content="viewport-fit=cover">` and iOS safe-area insets.
  * Service Worker pre-caches static shell assets for instant startup and routes dynamic catalog requests (`/api/*`) live to the network.
  * Minimum 44x44px touch targets and responsive card layouts.

* **🎨 Editorial UI Design**:
  * High-contrast editorial interface built with Tailwind CSS and Google Fonts (*Fraunces* serif for book titles, *Plus Jakarta Sans* for UI, *JetBrains Mono* for shelfmarks/ISBNs).

---

## 💻 Manual Setup & Execution

If you prefer running via command line or on Windows/Linux:

### 1. Install Dependencies
```bash
python3 -m pip install -r requirements.txt
```

### 2. Run the Application
```bash
# Option A: Standard Server
python3 run.py

# Option B: Desktop Launcher
python3 run_app.py
```

* **Web App**: [http://127.0.0.1:8000](http://127.0.0.1:8000)
* **Interactive API Docs (Swagger)**: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
* **ReDoc**: [http://127.0.0.1:8000/redoc](http://127.0.0.1:8000/redoc)

---

## 📱 Mobile App Installation (PWA)

Zahorí can be installed on your phone without an app store:

### 📱 iPhone (Safari)
1. Open `http://YOUR_COMPUTER_IP:8000` (or your deployed URL) in Safari.
2. Tap the **Share** button (<kbd>⎋</kbd>).
3. Select **"Añadir a la pantalla de inicio"** (*Add to Home Screen*).

### 🤖 Android (Chrome)
1. Open the URL in Chrome.
2. Tap the **Menu (⋮)** in the top right.
3. Select **"Instalar aplicación"** (*Install App*).

---

## ☁️ Cloud Deployment (Docker / Render / Railway)

Zahorí is ready for cloud deployment with GZip compression and dynamic `$PORT` binding:

### Docker
```bash
docker build -t zahori .
docker run -p 8000:8000 -e PORT=8000 zahori
```

### Render / Railway / Fly.io
Simply connect your GitHub repository. The included `Dockerfile` and `Procfile` will handle deployment automatically.

---

## 📡 API Endpoints

### 1. `GET /api/goodreads/shelf`
Fetches and parses a public Goodreads shelf.
* **Params**: `user_id` (numeric ID or full profile URL), `shelf` (default: `'to-read'`).

### 2. `POST /api/check-batch-availability`
Batch verifies catalog availability for a list of books.
```json
{
  "books": [
    {"book_id": "b1", "title": "Cien años de soledad", "author": "García Márquez"},
    {"book_id": "b2", "title": "Ficciones", "author": "Borges"}
  ],
  "selected_libraries": ["eugenio_trias"],
  "radius_km": 5.0,
  "limit_per_book": 2
}
```

### 3. `POST /api/goodreads/recommendations`
Finds books from a shelf with immediate physical availability.

### 4. `GET /api/search`
Direct catalog search by title/author with geospatial library filtering.

### 5. `GET /api/libraries`
Returns master list of Madrid libraries with geographic coordinates.

---

## 🧪 Running Automated Tests

```bash
python3 -m pytest tests/ -v
```

The test suite covers:
1. **Goodreads RSS Parser & Real Name Extraction** (`tests/test_goodreads.py`)
2. **Batch Availability & PWA Endpoints** (`tests/test_api.py`)
3. **Haversine Distance & Proximity Filter** (`tests/test_geo.py`)
4. **AbsysNet OPAC Live Scraper** (`tests/test_scraper.py`)

---

## 📄 License

MIT License. Developed for the public library readers of Madrid.
