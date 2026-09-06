/**
 * Frontend JavaScript for Madrid Public Libraries Book Availability,
 * Real User Name Display, Header Profile Integration & Clean Layout.
 */

document.addEventListener("DOMContentLoaded", () => {
  // --- TABS & NAVIGATION ---
  const tabBtnDirect = document.getElementById("tab-btn-direct");
  const tabBtnGoodreads = document.getElementById("tab-btn-goodreads");
  const viewDirectSearch = document.getElementById("view-direct-search");
  const viewGoodreadsShelf = document.getElementById("view-goodreads-shelf");

  // --- HEADER USER PROFILE CONTROLS ---
  const headerProfileBtn = document.getElementById("header-profile-btn");
  const headerConnectBtn = document.getElementById("header-connect-btn");
  const headerAvatarInitials = document.getElementById("header-avatar-initials");
  const headerUserDisplayName = document.getElementById("header-user-display-name");
  const headerShelfName = document.getElementById("header-shelf-name");

  // --- PROFILE CONFIGURATION MODAL ---
  const profileModal = document.getElementById("profile-modal");
  const profileModalCloseBtn = document.getElementById("profile-modal-close-btn");
  const profileModalCancelBtn = document.getElementById("profile-modal-cancel-btn");
  const goodreadsModalForm = document.getElementById("goodreads-modal-form");
  const inputGrUser = document.getElementById("input-gr-user");
  const inputGrShelf = document.getElementById("input-gr-shelf");
  const grSubmitBtn = document.getElementById("gr-submit-btn");
  const grSpinner = document.getElementById("gr-spinner");
  const grBtnText = document.getElementById("gr-btn-text");
  const grDemoBtn = document.getElementById("gr-demo-btn");
  const grDisconnectBtn = document.getElementById("gr-disconnect-btn");
  const grConnectPromptBtn = document.getElementById("gr-connect-prompt-btn");
  const grNoProfileState = document.getElementById("gr-no-profile-state");

  // --- GLOBAL LIBRARY & PROXIMITY SELECTOR ---
  const librarySearchInput = document.getElementById("library-search-input");
  const libraryDropdownList = document.getElementById("library-dropdown-list");
  const selectedLibraryChips = document.getElementById("selected-library-chips");
  const inputRadius = document.getElementById("input-radius");
  const inputRadiusNum = document.getElementById("input-radius-num");

  // --- VIEW 1: GOODREADS DOM ---
  const grErrorBanner = document.getElementById("gr-error-banner");
  const grErrorMessage = document.getElementById("gr-error-message");
  const grShelfDashboard = document.getElementById("gr-shelf-dashboard");
  const grRecommendationsSection = document.getElementById("gr-recommendations-section");
  const grRecsLoading = document.getElementById("gr-recs-loading");
  const grRecsGrid = document.getElementById("gr-recs-grid");
  const grRefreshRecsBtn = document.getElementById("gr-refresh-recs-btn");
  const grTotalCount = document.getElementById("gr-total-count");
  const grAvailableCount = document.getElementById("gr-available-count");
  const grFilterInput = document.getElementById("gr-filter-input");
  const grOnlyAvailableToggle = document.getElementById("gr-only-available-toggle");
  const grCheckAllBtn = document.getElementById("gr-check-all-btn");
  const grCheckAllSpinner = document.getElementById("gr-check-all-spinner");
  const grCheckAllText = document.getElementById("gr-check-all-text");
  const grProgressContainer = document.getElementById("gr-progress-container");
  const grProgressBar = document.getElementById("gr-progress-bar");
  const grProgressStats = document.getElementById("gr-progress-stats");
  const grBooksGrid = document.getElementById("gr-books-grid");

  // --- VIEW 2: DIRECT SEARCH DOM ---
  const searchForm = document.getElementById("search-form");
  const inputTitle = document.getElementById("input-title");
  const inputAuthor = document.getElementById("input-author");
  const submitBtn = document.getElementById("submit-btn");
  const btnSpinner = document.getElementById("btn-spinner");
  const btnText = document.getElementById("btn-text");
  const clearBtn = document.getElementById("clear-btn");
  const errorBanner = document.getElementById("error-banner");
  const errorMessage = document.getElementById("error-message");
  const loadingState = document.getElementById("loading-state");
  const resultsSection = document.getElementById("results-section");
  const resultsContainer = document.getElementById("results-container");
  const emptyState = document.getElementById("empty-state");
  const quickFillBtns = document.querySelectorAll(".quick-fill-btn");
  const statsTotalEditions = document.getElementById("stats-total-editions");
  const statsTotalCopies = document.getElementById("stats-total-copies");
  const statsAvailableCopies = document.getElementById("stats-available-copies");
  const branchFilterInput = document.getElementById("branch-filter-input");
  const onlyAvailableToggle = document.getElementById("only-available-toggle");

  // --- HOLDINGS DETAIL MODAL DOM ---
  const holdingsModal = document.getElementById("holdings-modal");
  const modalBookTitle = document.getElementById("modal-book-title");
  const modalBookAuthor = document.getElementById("modal-book-author");
  const modalHoldingsBody = document.getElementById("modal-holdings-body");
  const modalCloseBtn = document.getElementById("modal-close-btn");
  const modalFooterCloseBtn = document.getElementById("modal-footer-close-btn");

  // --- STATE ---
  let allLibraries = [];
  let selectedLibraries = []; // { id, name, district, municipality }
  let currentDirectResults = [];
  let isSearchingDirect = false;

  let goodreadsBooks = []; // Array of GoodreadsBook items
  let recommendedBooks = []; // Array of BatchBookAvailabilityResult
  let isCheckingBatch = false;
  let isFindingRecs = false;

  // Initialize
  loadLibrariesList();
  switchTab("goodreads"); // Default view to Goodreads
  initHeaderAndProfileState();
  registerServiceWorker();

  function registerServiceWorker() {
    if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker
          .register("/service-worker.js")
          .then((reg) => {
            console.log("[PWA] Service Worker registered with scope:", reg.scope);
          })
          .catch((err) => {
            console.warn("[PWA] Service Worker registration failed:", err);
          });
      });
    }
  }

  // --- TAB SWITCHING ---
  tabBtnGoodreads.addEventListener("click", () => switchTab("goodreads"));
  tabBtnDirect.addEventListener("click", () => switchTab("direct"));

  function switchTab(tab) {
    if (tab === "goodreads") {
      tabBtnGoodreads.classList.add("active", "text-slate-900", "border-slate-900");
      tabBtnGoodreads.classList.remove("text-slate-500", "border-transparent");
      tabBtnDirect.classList.remove("active", "text-slate-900", "border-slate-900");
      tabBtnDirect.classList.add("text-slate-500", "border-transparent");
      viewGoodreadsShelf.classList.remove("hidden");
      viewDirectSearch.classList.add("hidden");
    } else {
      tabBtnDirect.classList.add("active", "text-slate-900", "border-slate-900");
      tabBtnDirect.classList.remove("text-slate-500", "border-transparent");
      tabBtnGoodreads.classList.remove("active", "text-slate-900", "border-slate-900");
      tabBtnGoodreads.classList.add("text-slate-500", "border-transparent");
      viewDirectSearch.classList.remove("hidden");
      viewGoodreadsShelf.classList.add("hidden");
    }
  }

  // --- LOCALSTORAGE PROFILE MANAGEMENT & NAME EXTRACTION ---
  function extractGoodreadsUserId(input) {
    if (!input) return "";
    input = input.trim();
    if (/^\d+$/.test(input)) return input;
    // /user/show/12345678-user-name
    let m = input.match(/\/user\/show\/(\d+)/);
    if (m) return m[1];
    // /review/list/12345678 or /review/list_rss/12345678
    m = input.match(/\/review\/list(?:_rss)?\/(\d+)/);
    if (m) return m[1];
    // 5+ consecutive digits
    m = input.match(/\b(\d{5,12})\b/);
    if (m) return m[1];
    return input;
  }

  function extractNameFromInputSlug(input) {
    if (!input) return null;
    const m = input.match(/\/user\/show\/\d+[-_]([a-zA-Z0-9_\-]+)/);
    if (m) {
      const rawSlug = m[1].split("?")[0].split("/")[0];
      const words = rawSlug.split(/[-_]+/).filter(Boolean);
      const titleCased = words.map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(" ");
      return titleCased || null;
    }
    return null;
  }

  function getInitials(name) {
    if (!name) return "GR";
    const parts = name.trim().split(/\s+/).filter(Boolean);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    } else if (parts.length === 1 && parts[0].length >= 2 && !/^\d+$/.test(parts[0])) {
      return parts[0].slice(0, 2).toUpperCase();
    }
    return "GR";
  }

  function initHeaderAndProfileState() {
    try {
      const savedUserId = localStorage.getItem("goodreads_user_id");
      const savedUserName = localStorage.getItem("goodreads_user_name");
      const savedShelf = localStorage.getItem("goodreads_shelf") || "to-read";

      if (savedUserId) {
        setHeaderProfile(savedUserId, savedUserName, savedShelf);
        loadGoodreadsShelf(savedUserId, savedShelf, savedUserName);
      } else {
        setHeaderDisconnected();
      }
    } catch (e) {
      console.warn("LocalStorage access error:", e);
      setHeaderDisconnected();
    }
  }

  function setHeaderProfile(userId, userName, shelf) {
    const displayName = userName || userId || "Mi Perfil";
    headerUserDisplayName.textContent = displayName;
    headerAvatarInitials.textContent = getInitials(userName);
    headerShelfName.textContent = shelf;
    headerProfileBtn.classList.remove("hidden");
    headerConnectBtn.classList.add("hidden");
    grNoProfileState.classList.add("hidden");
  }

  function setHeaderDisconnected() {
    headerProfileBtn.classList.add("hidden");
    headerConnectBtn.classList.remove("hidden");
    grNoProfileState.classList.remove("hidden");
    grShelfDashboard.classList.add("hidden");
    grRecommendationsSection.classList.add("hidden");
    goodreadsBooks = [];
    recommendedBooks = [];
  }

  function openProfileModal() {
    const savedUserId = localStorage.getItem("goodreads_user_id") || "";
    const savedShelf = localStorage.getItem("goodreads_shelf") || "to-read";

    inputGrUser.value = savedUserId;
    inputGrShelf.value = savedShelf;

    if (savedUserId) {
      grDisconnectBtn.classList.remove("hidden");
    } else {
      grDisconnectBtn.classList.add("hidden");
    }

    profileModal.classList.remove("hidden");
    inputGrUser.focus();
  }

  function closeProfileModal() {
    profileModal.classList.add("hidden");
  }

  headerProfileBtn.addEventListener("click", openProfileModal);
  headerConnectBtn.addEventListener("click", openProfileModal);
  if (grConnectPromptBtn) grConnectPromptBtn.addEventListener("click", openProfileModal);

  profileModalCloseBtn.addEventListener("click", closeProfileModal);
  profileModalCancelBtn.addEventListener("click", closeProfileModal);
  profileModal.addEventListener("click", (e) => {
    if (e.target === profileModal) closeProfileModal();
  });

  grDemoBtn.addEventListener("click", () => {
    inputGrUser.value = "177587843";
    inputGrShelf.value = "to-read";
    goodreadsModalForm.dispatchEvent(new Event("submit"));
  });

  grDisconnectBtn.addEventListener("click", () => {
    try {
      localStorage.removeItem("goodreads_user_id");
      localStorage.removeItem("goodreads_user_name");
      localStorage.removeItem("goodreads_shelf");
    } catch (e) {
      console.warn("LocalStorage clear error:", e);
    }
    closeProfileModal();
    setHeaderDisconnected();
  });

  goodreadsModalForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const rawInput = inputGrUser.value.trim();
    const shelf = inputGrShelf.value.trim() || "to-read";

    if (!rawInput) {
      showGrError("Por favor, introduzca su ID de usuario o enlace de perfil de Goodreads.");
      inputGrUser.focus();
      return;
    }

    const cleanUserId = extractGoodreadsUserId(rawInput);
    if (!cleanUserId) {
      showGrError("No se pudo extraer un ID de usuario de Goodreads válido.");
      return;
    }

    // Try extracting real name from URL slug first
    let extractedName = extractNameFromInputSlug(rawInput);

    try {
      localStorage.setItem("goodreads_user_id", cleanUserId);
      if (extractedName) {
        localStorage.setItem("goodreads_user_name", extractedName);
      }
      localStorage.setItem("goodreads_shelf", shelf);
    } catch (err) {
      console.warn("LocalStorage save error:", err);
    }

    setHeaderProfile(cleanUserId, extractedName, shelf);
    closeProfileModal();
    loadGoodreadsShelf(rawInput, shelf, extractedName);
  });

  // --- TWO-WAY PROXIMITY SLIDER & NUMERIC INPUT SYNCHRONIZATION (Scale: 1 - 20 km) ---
  inputRadius.addEventListener("input", (e) => {
    const val = parseInt(e.target.value, 10) || 5;
    inputRadiusNum.value = val;
    onProximitySettingsChanged();
  });

  inputRadiusNum.addEventListener("input", (e) => {
    let val = parseInt(e.target.value, 10);
    if (isNaN(val)) return;
    val = Math.min(Math.max(val, 1), 20);
    inputRadius.value = val;
    onProximitySettingsChanged();
  });

  inputRadiusNum.addEventListener("blur", (e) => {
    let val = parseInt(e.target.value, 10);
    if (isNaN(val) || val < 1) val = 1;
    if (val > 20) val = 20;
    inputRadiusNum.value = val;
    inputRadius.value = val;
    onProximitySettingsChanged();
  });

  function getActiveRadiusKm() {
    const val = parseInt(inputRadiusNum.value, 10) || parseInt(inputRadius.value, 10) || 5;
    return Math.min(Math.max(val, 1), 20);
  }

  function onProximitySettingsChanged() {
    if (currentDirectResults.length > 0) {
      renderDirectResults();
    }
    if (goodreadsBooks.length > 0) {
      renderGoodreadsGrid();
    }
  }

  // --- LIBRARY MULTI-SELECT DROPDOWN LOGIC ---
  librarySearchInput.addEventListener("focus", () => {
    filterAndRenderDropdown(librarySearchInput.value);
    libraryDropdownList.classList.remove("hidden");
  });

  librarySearchInput.addEventListener("input", (e) => {
    filterAndRenderDropdown(e.target.value);
    libraryDropdownList.classList.remove("hidden");
  });

  document.addEventListener("click", (e) => {
    if (!librarySearchInput.contains(e.target) && !libraryDropdownList.contains(e.target)) {
      libraryDropdownList.classList.add("hidden");
    }
  });

  async function loadLibrariesList() {
    try {
      const res = await fetch("/api/libraries");
      if (res.ok) {
        const data = await res.json();
        allLibraries = data.libraries || [];
      }
    } catch (e) {
      console.warn("Could not load libraries database:", e);
    }
  }

  function filterAndRenderDropdown(query) {
    const q = (query || "").toLowerCase().trim();
    const selectedIds = new Set(selectedLibraries.map((l) => l.id));

    const matches = allLibraries.filter((lib) => {
      if (selectedIds.has(lib.id)) return false;
      if (!q) return true;
      return (
        lib.name.toLowerCase().includes(q) ||
        (lib.district && lib.district.toLowerCase().includes(q)) ||
        (lib.municipality && lib.municipality.toLowerCase().includes(q))
      );
    });

    libraryDropdownList.innerHTML = "";

    if (matches.length === 0) {
      libraryDropdownList.innerHTML = `
        <div class="px-3 py-2 text-slate-400 text-xs italic font-sans">
          No se encontraron bibliotecas con "${escapeHtml(query)}"
        </div>
      `;
      return;
    }

    matches.slice(0, 15).forEach((lib) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "w-full text-left px-3 py-2 hover:bg-slate-100 flex flex-col transition-colors font-sans";
      item.innerHTML = `
        <span class="font-bold text-slate-800 text-xs">${escapeHtml(lib.name)}</span>
        <span class="text-[11px] text-slate-500 font-medium">${escapeHtml(lib.district || "")} &bull; ${escapeHtml(lib.municipality || "Madrid")}</span>
      `;
      item.addEventListener("click", () => {
        addSelectedLibrary(lib);
        librarySearchInput.value = "";
        libraryDropdownList.classList.add("hidden");
        librarySearchInput.focus();
      });
      libraryDropdownList.appendChild(item);
    });
  }

  function addSelectedLibrary(lib) {
    if (!selectedLibraries.some((l) => l.id === lib.id)) {
      selectedLibraries.push(lib);
      renderSelectedChips();
      onProximitySettingsChanged();
    }
  }

  function removeSelectedLibrary(libId) {
    selectedLibraries = selectedLibraries.filter((l) => l.id !== libId);
    renderSelectedChips();
    onProximitySettingsChanged();
  }

  function renderSelectedChips() {
    selectedLibraryChips.innerHTML = "";
    if (selectedLibraries.length === 0) {
      selectedLibraryChips.innerHTML = `
        <span class="text-[11px] text-slate-400 italic font-sans">Ninguna seleccionada (se mostrarán todas las bibliotecas de la red)</span>
      `;
      return;
    }

    selectedLibraries.forEach((lib) => {
      const chip = document.createElement("span");
      chip.className = "inline-flex items-center px-2.5 py-1 rounded bg-slate-900 text-white text-xs font-semibold gap-1.5 shadow-xs font-sans";
      chip.innerHTML = `
        <span>${escapeHtml(lib.name)}</span>
        <button type="button" class="text-slate-300 hover:text-white transition-colors focus:outline-none" title="Quitar">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      `;
      chip.querySelector("button").addEventListener("click", (e) => {
        e.stopPropagation();
        removeSelectedLibrary(lib.id);
      });
      selectedLibraryChips.appendChild(chip);
    });
  }


  // --- VIEW 1: GOODREADS IMPLEMENTATION ---
  grFilterInput.addEventListener("input", renderGoodreadsGrid);
  grOnlyAvailableToggle.addEventListener("change", renderGoodreadsGrid);
  grCheckAllBtn.addEventListener("click", handleCheckAllGoodreads);
  grRefreshRecsBtn.addEventListener("click", () => findAvailableRecommendations(true));

  async function loadGoodreadsShelf(userIdOrUrl, shelf, initialUserName = null) {
    setGrLoading(true);
    hideGrError();
    grNoProfileState.classList.add("hidden");
    grShelfDashboard.classList.add("hidden");
    grRecommendationsSection.classList.add("hidden");

    try {
      const res = await fetch(`/api/goodreads/shelf?user_id=${encodeURIComponent(userIdOrUrl)}&shelf=${encodeURIComponent(shelf)}`);
      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.detail || data.error || `Error ${res.status}: Error al obtener datos de Goodreads.`);
      }

      // If backend parsed a real user name from RSS or slug, persist and update header
      const finalName = data.user_name || initialUserName || extractNameFromInputSlug(userIdOrUrl);
      if (finalName) {
        try {
          localStorage.setItem("goodreads_user_name", finalName);
        } catch (e) {}
        setHeaderProfile(data.user_id, finalName, shelf);
      }

      goodreadsBooks = (data.books || []).map((b) => ({
        ...b,
        status: "pending", // "pending", "checking", "checked"
        availability: null, // BatchBookAvailabilityResult
      }));

      if (goodreadsBooks.length === 0) {
        showGrError(`No se encontraron libros en la estantería '${shelf}'. Verifique que sea pública y contenga libros.`);
      } else {
        grTotalCount.textContent = `${goodreadsBooks.length} libro${goodreadsBooks.length !== 1 ? "s" : ""} en '${shelf}'`;
        updateGrAvailableCount();
        renderGoodreadsGrid();
        grShelfDashboard.classList.remove("hidden");

        // Automatically search and render 2 available recommendations
        findAvailableRecommendations();
      }
    } catch (err) {
      console.error("Goodreads error:", err);
      showGrError(err.message || "Error al conectar con Goodreads.");
    } finally {
      setGrLoading(false);
    }
  }

  // --- "RECOMENDACIONES" HERO SECTION LOGIC & BUBBLE CARDS ---
  async function findAvailableRecommendations(forceRefresh = false) {
    if (isFindingRecs || goodreadsBooks.length === 0) return;

    isFindingRecs = true;
    grRecommendationsSection.classList.remove("hidden");
    grRecsLoading.classList.remove("hidden");
    grRecsGrid.innerHTML = "";

    try {
      const radius = getActiveRadiusKm();
      const selectedLibIds = selectedLibraries.map((l) => l.id);

      const payload = {
        books: goodreadsBooks.map((b) => ({
          book_id: b.book_id,
          title: b.clean_title || b.title,
          author: b.author,
          isbn: b.isbn,
          cover_image_url: b.cover_image_url,
        })),
        selected_libraries: selectedLibIds,
        radius_km: radius,
        target_count: 2,
      };

      const res = await fetch("/api/goodreads/recommendations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      recommendedBooks = data.recommendations || [];

      // Update matching status in goodreadsBooks list if found
      recommendedBooks.forEach((rec) => {
        const match = goodreadsBooks.find((b) => b.book_id === rec.book_id);
        if (match) {
          match.availability = rec;
          match.status = "checked";
        }
      });
      updateGrAvailableCount();
      renderGoodreadsGrid();

      renderRecommendations();
    } catch (err) {
      console.warn("Recommendations fetch error:", err);
      grRecommendationsSection.classList.add("hidden");
    } finally {
      isFindingRecs = false;
      grRecsLoading.classList.add("hidden");
    }
  }

  function renderRecommendations() {
    grRecsGrid.innerHTML = "";

    if (!recommendedBooks || recommendedBooks.length === 0) {
      grRecsGrid.innerHTML = `
        <div class="md:col-span-2 p-5 bg-white/70 backdrop-blur-sm border border-red-100 rounded-2xl text-xs text-slate-600 italic text-center font-sans">
          No se encontraron recomendaciones con ejemplares disponibles inmediatamente entre las muestras analizadas. Pruebe a pulsar "Nuevas sugerencias".
        </div>
      `;
      return;
    }

    recommendedBooks.forEach((rec) => {
      const card = document.createElement("div");
      card.className = "bg-white/90 backdrop-blur-sm rounded-2xl border border-red-100/90 p-5 flex flex-col sm:flex-row items-center sm:items-stretch gap-5 shadow-sm hover:shadow-md transition-all duration-200 overflow-hidden";

      // Enlarged Book Cover Image
      const coverHtml = rec.cover_image_url
        ? `<img src="${rec.cover_image_url}" alt="${escapeHtml(rec.title)}" class="w-32 h-44 sm:w-36 sm:h-48 min-w-[120px] object-cover rounded-xl shadow-md border border-white/80 flex-shrink-0" />`
        : `<div class="w-32 h-44 sm:w-36 sm:h-48 min-w-[120px] bg-slate-100 rounded-xl border border-slate-200 flex items-center justify-center text-slate-400 text-xs text-center p-2 flex-shrink-0 font-medium font-sans">Sin portada</div>`;

      card.innerHTML = `
        ${coverHtml}
        <div class="flex-1 min-w-0 flex flex-col justify-between w-full font-sans">
          <div>
            <!-- Status Badge Header -->
            <div class="flex items-center gap-2 mb-2">
              <span class="inline-flex items-center px-2.5 py-1 rounded-full text-[11px] font-bold bg-emerald-100 text-emerald-800 uppercase tracking-wider shadow-2xs font-sans">
                <span class="w-2 h-2 rounded-full bg-emerald-600 mr-1.5 animate-pulse"></span>
                Disponible Ahora
              </span>
            </div>

            <!-- Title & Author -->
            <h4 class="font-serif text-lg sm:text-xl font-bold text-slate-900 leading-snug line-clamp-2" title="${escapeHtml(rec.title)}">
              ${escapeHtml(rec.title)}
            </h4>
            <p class="text-xs sm:text-sm text-slate-600 font-medium mt-1 truncate font-sans">${escapeHtml(rec.author || "Autor no especificado")}</p>
          </div>

          <!-- Divider -->
          <div class="border-t border-red-100/80 my-3"></div>

          <!-- Bottom Bar: Library location + Action button -->
          <div class="flex items-center justify-between gap-3 mt-auto pt-1">
            <div class="text-xs font-semibold text-slate-800 flex items-center gap-1.5 truncate min-w-0 font-sans" title="${escapeHtml(rec.best_match_library || '')}">
              <span class="text-red-500 flex-shrink-0">📍</span>
              <span class="truncate">${escapeHtml(rec.best_match_library || "Biblioteca de la red")}</span>
              ${rec.best_match_distance_km ? `<span class="text-slate-500 font-normal font-mono text-[11px] flex-shrink-0">(${rec.best_match_distance_km.toFixed(1)} km)</span>` : ""}
            </div>
            ${
              rec.full_result
                ? `<button type="button" class="rec-view-btn px-3.5 py-1.5 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-semibold flex-shrink-0 whitespace-nowrap transition-colors shadow-2xs focus:outline-none font-sans">
                    Ver ejemplares
                  </button>`
                : ""
            }
          </div>
        </div>
      `;

      const viewBtn = card.querySelector(".rec-view-btn");
      if (viewBtn) {
        viewBtn.addEventListener("click", () => {
          const dummyBook = {
            title: rec.title,
            author: rec.author,
            availability: rec,
          };
          openHoldingsModal(dummyBook);
        });
      }

      grRecsGrid.appendChild(card);
    });
  }

  // --- REFACTORED STANDARD BOOK CARDS GRID ---
  function renderGoodreadsGrid() {
    grBooksGrid.innerHTML = "";

    const filterText = grFilterInput.value.toLowerCase().trim();
    const onlyAvail = grOnlyAvailableToggle.checked;

    const filtered = goodreadsBooks.filter((book) => {
      const matchesText =
        !filterText ||
        book.title.toLowerCase().includes(filterText) ||
        book.author.toLowerCase().includes(filterText);

      const matchesAvail = !onlyAvail || (book.availability && book.availability.is_available);

      return matchesText && matchesAvail;
    });

    if (filtered.length === 0) {
      grBooksGrid.innerHTML = `
        <div class="col-span-full bg-white rounded-lg border border-slate-200 p-8 text-center text-slate-500 text-xs font-sans">
          No hay libros que coincidan con los filtros actuales.
        </div>
      `;
      return;
    }

    filtered.forEach((book) => {
      const card = document.createElement("div");
      card.className = "bg-white rounded-lg border border-slate-200 p-3.5 flex flex-col justify-between shadow-xs hover:shadow-md transition-all overflow-hidden font-sans";

      // Status pill HTML with max-width truncation
      let statusHtml = "";
      if (book.status === "pending") {
        statusHtml = `<span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-slate-100 text-slate-600 border border-slate-200 whitespace-nowrap font-sans">
          Sin comprobar
        </span>`;
      } else if (book.status === "checking") {
        statusHtml = `<span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-sky-50 text-sky-700 border border-sky-200 animate-pulse whitespace-nowrap font-sans">
          <svg class="animate-spin -ml-0.5 mr-1 h-3 w-3 text-sky-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>
          Comprobando...
        </span>`;
      } else if (book.status === "checked" && book.availability) {
        const a = book.availability;
        if (a.is_available) {
          statusHtml = `<span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200 max-w-[140px] sm:max-w-[180px] truncate font-sans" title="${escapeHtml(a.status_summary || 'Disponible')}">
            <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 mr-1.5 flex-shrink-0"></span>
            <span class="truncate">${escapeHtml(a.status_summary || "Disponible")}</span>
          </span>`;
        } else if (a.total_copies > 0) {
          statusHtml = `<span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-amber-50 text-amber-800 border border-amber-200 max-w-[140px] sm:max-w-[180px] truncate font-sans" title="${escapeHtml(a.status_summary || 'Prestado')}">
            <span class="w-1.5 h-1.5 rounded-full bg-amber-500 mr-1.5 flex-shrink-0"></span>
            <span class="truncate">${escapeHtml(a.status_summary || "Prestado")}</span>
          </span>`;
        } else {
          statusHtml = `<span class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-slate-100 text-slate-500 border border-slate-200 whitespace-nowrap font-sans">
            No en catálogo
          </span>`;
        }
      }

      // Cover image with fixed ratio
      const coverHtml = book.cover_image_url
        ? `<img src="${book.cover_image_url}" alt="${escapeHtml(book.title)}" class="w-20 h-28 object-cover rounded-md flex-shrink-0 border border-slate-200 shadow-2xs" />`
        : `<div class="w-20 h-28 bg-slate-100 rounded-md border border-slate-200 flex items-center justify-center text-slate-400 text-[10px] text-center p-1.5 flex-shrink-0 font-medium font-sans">Sin portada</div>`;

      card.innerHTML = `
        <div class="flex items-start gap-3.5 mb-3 overflow-hidden">
          ${coverHtml}
          <div class="space-y-1 min-w-0 flex-1">
            <h4 class="font-serif text-sm font-bold text-slate-900 leading-snug line-clamp-2" title="${escapeHtml(book.title)}">
              ${escapeHtml(book.title)}
            </h4>
            <p class="text-[11px] text-slate-600 font-medium truncate font-sans">${escapeHtml(book.author || "Autor no especificado")}</p>
            ${
              book.isbn
                ? `<span class="inline-block font-mono text-[10px] px-1.5 py-0.5 bg-slate-100 rounded text-slate-600 border border-slate-200 max-w-full truncate">ISBN: ${escapeHtml(book.isbn)}</span>`
                : ""
            }
          </div>
        </div>

        <!-- Footer / Action bar: Zero horizontal clipping -->
        <div class="flex items-center justify-between mt-auto pt-3 border-t border-slate-100 gap-2 w-full min-w-0 overflow-hidden">
          <div class="min-w-0 flex-1 flex items-center">
            ${statusHtml}
          </div>

          <div class="flex items-center gap-1.5 flex-shrink-0 font-sans">
            ${
              book.availability && book.availability.full_result && book.availability.full_result.holdings.length > 0
                ? `<button
                    type="button"
                    class="view-holdings-btn px-2 py-1 rounded text-slate-600 hover:text-slate-900 text-xs font-semibold hover:bg-slate-100 transition-colors inline-flex items-center flex-shrink-0 whitespace-nowrap"
                    data-id="${escapeHtml(book.book_id)}"
                    title="Ver ejemplares en bibliotecas"
                  >
                    Ejemplares (${book.availability.total_copies})
                  </button>`
                : ""
            }
            <button
              type="button"
              class="check-single-btn px-2.5 py-1 rounded bg-slate-900 hover:bg-slate-800 text-white text-xs font-semibold transition-colors shadow-2xs flex-shrink-0 whitespace-nowrap"
              data-id="${escapeHtml(book.book_id)}"
            >
              ${book.status === "checked" ? "Recomprobar" : "Comprobar"}
            </button>
          </div>
        </div>
      `;

      card.querySelector(".check-single-btn").addEventListener("click", () => {
        checkSingleGoodreadsBook(book);
      });

      const viewHoldingsBtn = card.querySelector(".view-holdings-btn");
      if (viewHoldingsBtn) {
        viewHoldingsBtn.addEventListener("click", () => {
          openHoldingsModal(book);
        });
      }

      grBooksGrid.appendChild(card);
    });
  }

  async function checkSingleGoodreadsBook(book) {
    book.status = "checking";
    renderGoodreadsGrid();

    try {
      const radius = getActiveRadiusKm();
      const selectedLibIds = selectedLibraries.map((l) => l.id);

      const payload = {
        books: [
          {
            book_id: book.book_id,
            title: book.clean_title || book.title,
            author: book.author,
            isbn: book.isbn,
            cover_image_url: book.cover_image_url,
          },
        ],
        selected_libraries: selectedLibIds,
        radius_km: radius,
        limit_per_book: 2,
      };

      const res = await fetch("/api/check-batch-availability", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (data.results && data.results.length > 0) {
        book.availability = data.results[0];
      }
      book.status = "checked";
    } catch (e) {
      console.error("Error checking single book:", e);
      book.status = "checked";
    } finally {
      updateGrAvailableCount();
      renderGoodreadsGrid();
    }
  }

  async function handleCheckAllGoodreads() {
    if (isCheckingBatch || goodreadsBooks.length === 0) return;

    isCheckingBatch = true;
    grCheckAllBtn.disabled = true;
    grCheckAllSpinner.classList.remove("hidden");
    grCheckAllText.textContent = "Comprobando catálogo...";
    grProgressContainer.classList.remove("hidden");

    const total = goodreadsBooks.length;
    let completed = 0;

    const radius = getActiveRadiusKm();
    const selectedLibIds = selectedLibraries.map((l) => l.id);

    const chunkSize = 4;
    for (let i = 0; i < goodreadsBooks.length; i += chunkSize) {
      const chunk = goodreadsBooks.slice(i, i + chunkSize);

      chunk.forEach((b) => {
        b.status = "checking";
      });
      renderGoodreadsGrid();

      const payload = {
        books: chunk.map((b) => ({
          book_id: b.book_id,
          title: b.clean_title || b.title,
          author: b.author,
          isbn: b.isbn,
          cover_image_url: b.cover_image_url,
        })),
        selected_libraries: selectedLibIds,
        radius_km: radius,
        limit_per_book: 2,
      };

      try {
        const res = await fetch("/api/check-batch-availability", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });

        const data = await res.json();
        if (data.results) {
          data.results.forEach((r) => {
            const targetBook = goodreadsBooks.find((b) => b.book_id === r.book_id);
            if (targetBook) {
              targetBook.availability = r;
              targetBook.status = "checked";
            }
          });
        }
      } catch (err) {
        console.error("Batch chunk error:", err);
        chunk.forEach((b) => {
          b.status = "checked";
        });
      }

      completed = Math.min(i + chunkSize, total);
      const percent = Math.round((completed / total) * 100);
      grProgressBar.style.width = `${percent}%`;
      grProgressStats.textContent = `${completed} / ${total}`;

      updateGrAvailableCount();
      renderGoodreadsGrid();
    }

    isCheckingBatch = false;
    grCheckAllBtn.disabled = false;
    grCheckAllSpinner.classList.add("hidden");
    grCheckAllText.textContent = "Comprobar Todos en Catálogo";
    setTimeout(() => {
      grProgressContainer.classList.add("hidden");
    }, 2500);
  }

  function updateGrAvailableCount() {
    const availCount = goodreadsBooks.filter((b) => b.availability && b.availability.is_available).length;
    grAvailableCount.textContent = `${availCount} disponibles en Madrid`;
  }

  function setGrLoading(loading) {
    grSubmitBtn.disabled = loading;
    if (loading) {
      grSpinner.classList.remove("hidden");
      grBtnText.textContent = "Sincronizando...";
    } else {
      grSpinner.classList.add("hidden");
      grBtnText.textContent = "Sincronizar";
    }
  }

  function showGrError(msg) {
    grErrorMessage.textContent = msg;
    grErrorBanner.classList.remove("hidden");
  }

  function hideGrError() {
    grErrorBanner.classList.add("hidden");
    grErrorMessage.textContent = "";
  }


  // --- VIEW 2: DIRECT SEARCH IMPLEMENTATION ---
  searchForm.addEventListener("submit", handleDirectSearch);
  clearBtn.addEventListener("click", handleDirectClear);
  branchFilterInput.addEventListener("input", renderDirectResults);
  onlyAvailableToggle.addEventListener("change", renderDirectResults);

  quickFillBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      inputTitle.value = btn.getAttribute("data-title") || "";
      inputAuthor.value = btn.getAttribute("data-author") || "";
      triggerDirectSearch();
    });
  });

  function handleDirectClear() {
    inputTitle.value = "";
    inputAuthor.value = "";
    currentDirectResults = [];
    hideError();
    resultsSection.classList.add("hidden");
    emptyState.classList.add("hidden");
    branchFilterInput.value = "";
    onlyAvailableToggle.checked = false;
    inputTitle.focus();
  }

  function triggerDirectSearch() {
    searchForm.dispatchEvent(new Event("submit", { cancelable: true }));
  }

  async function handleDirectSearch(e) {
    e.preventDefault();
    if (isSearchingDirect) return;

    const title = inputTitle.value.trim();
    const author = inputAuthor.value.trim();

    if (!title && !author) {
      showError("Por favor, introduzca al menos un título o un autor para realizar la búsqueda.");
      inputTitle.focus();
      return;
    }

    setDirectLoading(true);
    hideError();
    resultsSection.classList.add("hidden");
    emptyState.classList.add("hidden");

    try {
      const params = new URLSearchParams();
      if (title) params.append("title", title);
      if (author) params.append("author", author);
      params.append("limit", "5");

      const radius = getActiveRadiusKm();
      params.append("radius_km", radius.toString());

      if (selectedLibraries.length > 0) {
        selectedLibraries.forEach((lib) => {
          params.append("selected_libraries", lib.id);
        });
      }

      const response = await fetch(`/api/search?${params.toString()}`);
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.detail || data.error || `Error ${response.status}: Error al conectar con el servidor.`);
      }

      if (!data.success) {
        throw new Error(data.error || "Ocurrió un error inesperado al procesar los resultados.");
      }

      currentDirectResults = data.results || [];

      if (currentDirectResults.length === 0) {
        emptyState.classList.remove("hidden");
      } else {
        updateDirectStats(data);
        renderDirectResults();
        resultsSection.classList.remove("hidden");
      }
    } catch (err) {
      console.error("Direct search error:", err);
      showError(err.message || "Error al conectar con el catálogo de la Comunidad de Madrid.");
    } finally {
      setDirectLoading(false);
    }
  }

  function updateDirectStats(data) {
    const totalEditions = data.total_editions || currentDirectResults.length;
    const totalCopies = data.total_copies || 0;
    const totalAvailable = data.total_available_copies || 0;

    statsTotalEditions.textContent = `${totalEditions} edición${totalEditions !== 1 ? "es" : ""}`;
    statsTotalCopies.textContent = `${totalCopies} ejemplar${totalCopies !== 1 ? "es" : ""} en red`;
    statsAvailableCopies.textContent = `${totalAvailable} disponible${totalAvailable !== 1 ? "s" : ""}`;
  }

  function renderDirectResults() {
    resultsContainer.innerHTML = "";

    const branchFilter = branchFilterInput.value.toLowerCase().trim();
    const onlyAvailable = onlyAvailableToggle.checked;
    const hasSelectedLibs = selectedLibraries.length > 0;

    let visibleEditionsCount = 0;

    currentDirectResults.forEach((book, bookIdx) => {
      visibleEditionsCount++;

      const card = document.createElement("article");
      card.className = "bg-white rounded-lg border border-slate-200 overflow-hidden shadow-xs hover:shadow-sm transition-all font-sans";

      const header = document.createElement("div");
      header.className = "p-5 border-b border-slate-200 bg-white";

      const availCount = (book.holdings || []).filter((h) => h.is_available).length;
      const totalHoldings = (book.holdings || []).length;

      const availBadgeClass =
        availCount > 0
          ? "bg-emerald-50 text-emerald-700 border-emerald-200"
          : "bg-slate-100 text-slate-600 border-slate-200";

      header.innerHTML = `
        <div class="flex flex-col sm:flex-row sm:items-start justify-between gap-3 font-sans">
          <div class="space-y-1 max-w-3xl">
            <span class="text-[11px] font-bold text-slate-400 uppercase tracking-wider font-sans">Edición #${bookIdx + 1}</span>
            <h3 class="font-serif text-base sm:text-lg font-bold text-slate-900 leading-snug">
              ${escapeHtml(book.title)}
            </h3>
            ${
              book.author
                ? `<p class="text-sm font-medium text-slate-700 font-sans">${escapeHtml(book.author)}</p>`
                : ""
            }
            <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-slate-500 pt-1 font-sans">
              ${book.year ? `<span><strong>Año:</strong> <span class="font-mono text-slate-700">${escapeHtml(book.year)}</span></span>` : ""}
              ${book.publication ? `<span><strong>Publicación:</strong> ${escapeHtml(book.publication)}</span>` : ""}
              ${book.edition ? `<span><strong>Edición:</strong> ${escapeHtml(book.edition)}</span>` : ""}
              ${book.isbn ? `<span class="font-mono text-[10px] px-1.5 py-0.5 bg-slate-100 rounded text-slate-600 border border-slate-200">ISBN: ${escapeHtml(book.isbn)}</span>` : ""}
            </div>
          </div>
          <div class="sm:text-right flex sm:flex-col items-center sm:items-end justify-between gap-2 flex-shrink-0 font-sans">
            <span class="inline-flex items-center px-2.5 py-1 rounded-md text-xs font-semibold border ${availBadgeClass}">
              <span class="w-1.5 h-1.5 rounded-full ${availCount > 0 ? "bg-emerald-500" : "bg-slate-400"} mr-1.5"></span>
              ${availCount} de ${totalHoldings} disponible${totalHoldings !== 1 ? "s" : ""}
            </span>
            ${
              book.detail_url
                ? `<a href="${book.detail_url}" target="_blank" rel="noopener noreferrer" class="text-xs text-brand-600 hover:text-brand-700 hover:underline inline-flex items-center font-semibold">
                    Ver ficha en OPAC
                    <svg class="w-3 h-3 ml-1" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                  </a>`
                : ""
            }
          </div>
        </div>
      `;
      card.appendChild(header);

      const bodyContainer = document.createElement("div");
      bodyContainer.className = "p-0 divide-y divide-slate-100 font-sans";

      const filterHolding = (h) => {
        const matchesBranch = !branchFilter || h.library.toLowerCase().includes(branchFilter) || (h.location && h.location.toLowerCase().includes(branchFilter));
        const matchesAvail = !onlyAvailable || h.is_available;
        return matchesBranch && matchesAvail;
      };

      if (hasSelectedLibs) {
        const directList = (book.direct_matches || []).filter(filterHolding);
        const nearbyList = (book.nearby_matches || []).filter(filterHolding);
        const otherList = (book.other_holdings || []).filter(filterHolding);

        // 1. Direct Matches
        const directSec = document.createElement("div");
        directSec.className = "p-4 sm:p-5 bg-slate-50/50";
        directSec.innerHTML = `
          <div class="flex items-center justify-between mb-3">
            <h4 class="text-xs font-bold uppercase tracking-wider text-slate-800 flex items-center font-sans">
              <span class="w-2 h-2 rounded-full bg-brand-500 mr-2"></span>
              Bibliotecas Seleccionadas (${directList.length})
            </h4>
          </div>
        `;

        if (directList.length === 0) {
          directSec.innerHTML += `
            <div class="p-3.5 bg-amber-50/80 border border-amber-200 rounded text-xs text-amber-900 font-sans">
              No hay ejemplares registrados en las bibliotecas específicamente seleccionadas. Consulte las alternativas cercanas a continuación.
            </div>
          `;
        } else {
          directSec.appendChild(renderHoldingsTable(directList, false));
        }
        bodyContainer.appendChild(directSec);

        // 2. Nearby Alternatives
        const nearbySec = document.createElement("div");
        nearbySec.className = "p-4 sm:p-5 bg-emerald-50/20";
        nearbySec.innerHTML = `
          <div class="flex items-center justify-between mb-3">
            <h4 class="text-xs font-bold uppercase tracking-wider text-emerald-900 flex items-center font-sans">
              <span class="w-2 h-2 rounded-full bg-emerald-500 mr-2"></span>
              Alternativas Cercanas Recomendadas (en radio de proximidad) (${nearbyList.length})
            </h4>
          </div>
        `;

        if (nearbyList.length === 0) {
          nearbySec.innerHTML += `
            <div class="p-3.5 bg-white border border-slate-200 rounded text-xs text-slate-500 italic font-sans">
              No se encontraron sucursales adicionales con copias dentro del radio de búsqueda establecido.
            </div>
          `;
        } else {
          nearbySec.appendChild(renderHoldingsTable(nearbyList, true));
        }
        bodyContainer.appendChild(nearbySec);

        // 3. Other Branches
        if (otherList.length > 0) {
          const otherSec = document.createElement("div");
          otherSec.className = "p-4 bg-white";
          const detailsEl = document.createElement("details");
          detailsEl.className = "group font-sans";
          detailsEl.innerHTML = `
            <summary class="text-xs font-semibold text-slate-600 hover:text-slate-900 cursor-pointer flex items-center justify-between list-none py-1 font-sans">
              <span>Ver otras bibliotecas de la red (${otherList.length})</span>
              <span class="text-slate-400 group-open:rotate-180 transition-transform text-xs">▼</span>
            </summary>
            <div class="mt-3 pt-3 border-t border-slate-100">
              ${renderHoldingsTable(otherList, false).outerHTML}
            </div>
          `;
          otherSec.appendChild(detailsEl);
          bodyContainer.appendChild(otherSec);
        }
      } else {
        const allList = (book.holdings || []).filter(filterHolding);
        const unifiedSec = document.createElement("div");
        unifiedSec.className = "p-0 font-sans";

        if (allList.length === 0) {
          unifiedSec.innerHTML = `
            <div class="p-6 text-center text-xs text-slate-500 bg-slate-50 font-sans">
              ${
                totalHoldings === 0
                  ? "No hay copias físicas registradas para esta edición."
                  : "No hay ejemplares que coincidan con los filtros seleccionados."
              }
            </div>
          `;
        } else {
          unifiedSec.appendChild(renderHoldingsTable(allList, false));
        }
        bodyContainer.appendChild(unifiedSec);
      }

      card.appendChild(bodyContainer);
      resultsContainer.appendChild(card);
    });

    if (visibleEditionsCount === 0 && currentDirectResults.length > 0) {
      resultsContainer.innerHTML = `
        <div class="bg-white rounded-lg border border-slate-200 p-8 text-center text-slate-500 text-sm font-sans">
          No se encontraron ejemplares con los filtros actuales ("${escapeHtml(branchFilter)}"${onlyAvailable ? ", solo disponibles" : ""}).
        </div>
      `;
    }
  }

  function renderHoldingsTable(holdings, showDistance) {
    const tableWrap = document.createElement("div");
    tableWrap.className = "overflow-x-auto rounded border border-slate-200 bg-white font-sans";

    const rowsHtml = holdings
      .map((h) => {
        const statusBadge = h.is_available
          ? `<span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200 whitespace-nowrap font-sans">
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 mr-1.5"></span>
              Disponible
            </span>`
          : `<span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-amber-50 text-amber-800 border border-amber-200 whitespace-nowrap font-sans">
              <span class="w-1.5 h-1.5 rounded-full bg-amber-500 mr-1.5"></span>
              ${escapeHtml(h.status_raw)}
            </span>`;

        let distanceTag = "";
        if (h.distance_km !== null && h.distance_km !== undefined) {
          distanceTag = `
            <span class="inline-flex items-center text-[10px] font-mono font-medium text-slate-600 bg-slate-100 px-1.5 py-0.5 rounded ml-1 border border-slate-200 whitespace-nowrap" title="Distancia respecto a ${escapeHtml(h.relative_to_library || 'biblioteca seleccionada')}">
              📍 ${h.distance_km.toFixed(1)} km ${h.relative_to_library ? `de ${escapeHtml(h.relative_to_library)}` : ""}
            </span>
          `;
        }

        return `
          <tr class="border-b border-slate-100 hover:bg-slate-50/80">
            <td class="px-4 py-3 text-xs font-medium text-slate-900 font-sans">
              <div class="flex items-center flex-wrap gap-1">
                <span class="font-bold text-slate-800">${escapeHtml(h.library)}</span>
                ${distanceTag}
              </div>
              <div class="text-[11px] text-slate-500">${escapeHtml(h.location || "General")} &bull; ${escapeHtml(h.support || "Libro")}</div>
            </td>
            <td class="px-4 py-3 text-xs">
              <span class="font-mono inline-block px-2 py-1 bg-slate-100 text-slate-800 rounded text-[11px] font-semibold border border-slate-200">
                ${escapeHtml(h.shelfmark || "—")}
              </span>
            </td>
            <td class="px-4 py-3 text-xs text-slate-600 font-sans">
              ${escapeHtml(h.item_type || "Prestable")}
            </td>
            <td class="px-4 py-3 text-xs text-right whitespace-nowrap">
              ${statusBadge}
            </td>
          </tr>
        `;
      })
      .join("");

    tableWrap.innerHTML = `
      <table class="min-w-full divide-y divide-slate-200 text-left text-xs font-sans">
        <thead class="bg-slate-50 text-slate-600 uppercase font-bold text-[10px] tracking-wider font-sans">
          <tr>
            <th scope="col" class="px-4 py-2.5">Biblioteca / Sucursal</th>
            <th scope="col" class="px-4 py-2.5">Signatura</th>
            <th scope="col" class="px-4 py-2.5">Tipo</th>
            <th scope="col" class="px-4 py-2.5 text-right">Estado</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-slate-100">
          ${rowsHtml}
        </tbody>
      </table>
    `;

    return tableWrap;
  }

  function setDirectLoading(loading) {
    isSearchingDirect = loading;
    submitBtn.disabled = loading;
    if (loading) {
      btnSpinner.classList.remove("hidden");
      btnText.textContent = "Buscando...";
      loadingState.classList.remove("hidden");
    } else {
      btnSpinner.classList.add("hidden");
      btnText.textContent = "Consultar Catálogo";
      loadingState.classList.add("hidden");
    }
  }

  function showError(msg) {
    errorMessage.textContent = msg;
    errorBanner.classList.remove("hidden");
  }

  function hideError() {
    errorBanner.classList.add("hidden");
    errorMessage.textContent = "";
  }


  // --- MODAL FOR GOODREADS HOLDINGS BREAKDOWN ---
  function openHoldingsModal(book) {
    if (!book.availability || !book.availability.full_result) return;

    const res = book.availability.full_result;
    modalBookTitle.textContent = res.title || book.title;
    modalBookAuthor.textContent = res.author || book.author || "";

    modalHoldingsBody.innerHTML = "";

    const hasSelectedLibs = selectedLibraries.length > 0;

    if (hasSelectedLibs) {
      // Direct matches
      if (res.direct_matches && res.direct_matches.length > 0) {
        const sec = document.createElement("div");
        sec.innerHTML = `
          <h5 class="font-bold text-slate-800 uppercase tracking-wider text-[11px] mb-2 flex items-center font-sans">
            <span class="w-2 h-2 rounded-full bg-brand-500 mr-1.5"></span>
            Bibliotecas Seleccionadas (${res.direct_matches.length})
          </h5>
        `;
        sec.appendChild(renderHoldingsTable(res.direct_matches, false));
        modalHoldingsBody.appendChild(sec);
      }

      // Nearby alternatives
      if (res.nearby_matches && res.nearby_matches.length > 0) {
        const sec = document.createElement("div");
        sec.innerHTML = `
          <h5 class="font-bold text-emerald-900 uppercase tracking-wider text-[11px] mb-2 flex items-center font-sans">
            <span class="w-2 h-2 rounded-full bg-emerald-500 mr-1.5"></span>
            Alternativas Cercanas (${res.nearby_matches.length})
          </h5>
        `;
        sec.appendChild(renderHoldingsTable(res.nearby_matches, true));
        modalHoldingsBody.appendChild(sec);
      }

      // Other holdings
      if (res.other_holdings && res.other_holdings.length > 0) {
        const sec = document.createElement("div");
        sec.innerHTML = `
          <h5 class="font-bold text-slate-600 uppercase tracking-wider text-[11px] mb-2 font-sans">
            Otras Bibliotecas (${res.other_holdings.length})
          </h5>
        `;
        sec.appendChild(renderHoldingsTable(res.other_holdings, false));
        modalHoldingsBody.appendChild(sec);
      }
    } else {
      modalHoldingsBody.appendChild(renderHoldingsTable(res.holdings, false));
    }

    holdingsModal.classList.remove("hidden");
  }

  modalCloseBtn.addEventListener("click", closeModal);
  modalFooterCloseBtn.addEventListener("click", closeModal);
  holdingsModal.addEventListener("click", (e) => {
    if (e.target === holdingsModal) closeModal();
  });

  function closeModal() {
    holdingsModal.classList.add("hidden");
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }
});
