// NavigationStack, navigation bar with large titles, swipe-back, pull-to-refresh, sheet and menu:
// the SwiftUI chrome the iOS app gets for free.
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { ChevronLeft } from "lucide-react";
import { Spinner } from "./components";

const DURATION = 350;
const EASE = "cubic-bezier(.2,.9,.3,1)";

interface Layer {
  id: number;
  title: string;
  node: ReactNode;
  phase: "enter" | "shown" | "leave";
}

interface NavAPI {
  push(title: string, node: ReactNode): void;
  pop(): void;
}

interface LayerInfo {
  depth: number;
  parentTitle: string;
}

const NavContext = createContext<NavAPI>({ push() {}, pop() {} });
const LayerContext = createContext<LayerInfo>({ depth: 0, parentTitle: "" });

export const useNav = () => useContext(NavContext);

// ---- Browser history: a push adds an entry, so Safari's own back gesture (in the browser) and our
// back button both go through `popstate`. Only the active tab's stack reacts. ----

let activeStack: { popFromHistory(): void } | null = null;
let ignoredPops = 0;

window.addEventListener("popstate", () => {
  if (ignoredPops > 0) {
    ignoredPops--;
    return;
  }
  activeStack?.popFromHistory();
});

let nextID = 1;

export function NavStack({ active, rootTitle, children }: { active: boolean; rootTitle: string; children: ReactNode }) {
  const [layers, setLayers] = useState<Layer[]>([]);
  const [dragX, setDragX] = useState<number | null>(null);
  const layersRef = useRef(layers);
  layersRef.current = layers;

  const removeTop = useCallback((animated: boolean) => {
    const top = layersRef.current.filter((l) => l.phase !== "leave").at(-1);
    if (!top) return;
    if (!animated) {
      setLayers((ls) => ls.filter((l) => l.id !== top.id));
      return;
    }
    setLayers((ls) => ls.map((l) => (l.id === top.id ? { ...l, phase: "leave" } : l)));
    setTimeout(() => setLayers((ls) => ls.filter((l) => l.id !== top.id)), DURATION);
  }, []);

  const api: NavAPI = {
    push(title, node) {
      const id = nextID++;
      setLayers((ls) => [...ls, { id, title, node, phase: "enter" }]);
      requestAnimationFrame(() =>
        requestAnimationFrame(() => setLayers((ls) => ls.map((l) => (l.id === id ? { ...l, phase: "shown" } : l)))),
      );
      history.pushState({ zahori: id }, "");
    },
    pop() {
      history.back();
    },
  };

  useEffect(() => {
    if (!active) return;
    const me = { popFromHistory: () => removeTop(true) };
    activeStack = me;
    return () => {
      if (activeStack === me) activeStack = null;
    };
  }, [active, removeTop]);

  /** Re-tapping the active tab pops to the root, like UITabBarController. */
  useEffect(() => {
    if (!active) return;
    const onRetap = () => {
      const n = layersRef.current.filter((l) => l.phase !== "leave").length;
      if (n === 0) return;
      ignoredPops++;
      history.go(-n);
      setLayers([]);
    };
    window.addEventListener("zahori:retap", onRetap);
    return () => window.removeEventListener("zahori:retap", onRetap);
  }, [active]);

  const finishSwipe = (commit: boolean) => {
    if (commit) {
      // Animate the rest of the way out ourselves, then drop the history entry without a second animation.
      removeTop(true);
      ignoredPops++;
      history.back();
    }
    setDragX(null);
  };

  const visible = layers.filter((l) => l.phase !== "leave");
  const titles = [rootTitle, ...layers.map((l) => l.title)];

  return (
    <NavContext.Provider value={api}>
      <div className="stack" hidden={!active}>
        <LayerView offset={offsetFor(-1, visible.length, layers, dragX)}>
          <LayerContext.Provider value={{ depth: 0, parentTitle: "" }}>{children}</LayerContext.Provider>
        </LayerView>
        {layers.map((layer, i) => {
          const isTop = layer.id === visible.at(-1)?.id;
          return (
            <LayerView
              key={layer.id}
              pushed
              offset={offsetFor(i, visible.length, layers, dragX)}
              dragging={dragX !== null}
              onSwipe={isTop ? setDragX : undefined}
              onSwipeEnd={isTop ? finishSwipe : undefined}
            >
              <LayerContext.Provider value={{ depth: i + 1, parentTitle: titles[i] }}>{layer.node}</LayerContext.Provider>
            </LayerView>
          );
        })}
      </div>
    </NavContext.Provider>
  );
}

/** Horizontal position of a layer: "100%" off-screen right, "0" shown, "-30%" covered (parallax). */
function offsetFor(index: number, visibleCount: number, layers: Layer[], dragX: number | null): string {
  const layer = index >= 0 ? layers[index] : null;
  if (layer && layer.phase !== "shown") return "100%";
  const visibleIndex = index + 1; // root = 0
  if (visibleIndex === visibleCount) return dragX !== null ? `${dragX}px` : "0px";
  if (visibleIndex === visibleCount - 1) {
    const above = layers[index + 1];
    if (above && above.phase !== "shown") return "0px";
    return dragX !== null ? `calc(-30% + ${dragX * 0.3}px)` : "-30%";
  }
  return "-30%";
}

function LayerView({
  children,
  offset,
  pushed = false,
  dragging = false,
  onSwipe,
  onSwipeEnd,
}: {
  children: ReactNode;
  offset: string;
  pushed?: boolean;
  dragging?: boolean;
  onSwipe?: (x: number) => void;
  onSwipeEnd?: (commit: boolean) => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const handlers = useRef({ onSwipe, onSwipeEnd });
  handlers.current = { onSwipe, onSwipeEnd };

  // Edge swipe-back. Native listeners: React's touchmove is passive, and we must stop vertical scrolling.
  useEffect(() => {
    const el = ref.current;
    if (!el || !pushed) return;
    let start: { x: number; y: number; t: number } | null = null;
    let dx = 0;
    let decided: "h" | "v" | null = null;
    const down = (e: TouchEvent) => {
      const t = e.touches[0];
      if (!handlers.current.onSwipe || t.clientX > 24) return;
      start = { x: t.clientX, y: t.clientY, t: e.timeStamp };
      dx = 0;
      decided = null;
    };
    const move = (e: TouchEvent) => {
      if (!start) return;
      const t = e.touches[0];
      const mx = t.clientX - start.x;
      const my = t.clientY - start.y;
      if (!decided && Math.hypot(mx, my) > 8) decided = Math.abs(mx) > Math.abs(my) ? "h" : "v";
      if (decided === "v") return (start = null);
      if (decided === "h") {
        e.preventDefault();
        dx = Math.max(0, mx);
        handlers.current.onSwipe?.(dx);
      }
    };
    const up = (e: TouchEvent) => {
      if (!start) return;
      const velocity = dx / Math.max(1, e.timeStamp - start.t);
      start = null;
      if (decided === "h") handlers.current.onSwipeEnd?.(dx > el.clientWidth * 0.35 || velocity > 0.5);
    };
    el.addEventListener("touchstart", down, { passive: true });
    el.addEventListener("touchmove", move, { passive: false });
    el.addEventListener("touchend", up);
    el.addEventListener("touchcancel", up);
    return () => {
      el.removeEventListener("touchstart", down);
      el.removeEventListener("touchmove", move);
      el.removeEventListener("touchend", up);
      el.removeEventListener("touchcancel", up);
    };
  }, [pushed]);

  const covered = offset.startsWith("-") || offset.startsWith("calc(-");
  return (
    <div
      ref={ref}
      className={`screen${pushed ? " pushed" : ""}`}
      style={{
        transform: `translateX(${offset})`,
        transition: dragging ? "none" : `transform ${DURATION}ms ${EASE}`,
      }}
      aria-hidden={covered || undefined}
    >
      {children}
      {covered && <div className="screen-dim" style={{ opacity: 0.35 }} />}
    </div>
  );
}

// ---- Screen: navigation bar + scroll view (+ optional large title and pull-to-refresh) ----

export function Screen({
  title,
  large = false,
  leading,
  trailing,
  onRefresh,
  children,
  bodyTop,
}: {
  title: string;
  large?: boolean;
  leading?: ReactNode;
  trailing?: ReactNode;
  onRefresh?: () => Promise<void>;
  children: ReactNode;
  /** Rendered between the large title and the content (e.g. the search field of `.searchable`). */
  bodyTop?: ReactNode;
}) {
  const { depth, parentTitle } = useContext(LayerContext);
  const nav = useNav();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [scrolled, setScrolled] = useState(false);
  const [pull, setPull] = useState(0);
  const [refreshing, setRefreshing] = useState(false);

  const onScroll = () => {
    const y = scrollRef.current?.scrollTop ?? 0;
    setScrolled(y > (large ? 40 : 2));
  };

  // Pull to refresh (`.refreshable`): works with iOS rubber-banding and with plain touch deltas.
  const refreshRef = useRef(onRefresh);
  refreshRef.current = onRefresh;
  useEffect(() => {
    const el = scrollRef.current;
    if (!el || !onRefresh) return;
    let y0: number | null = null;
    let distance = 0;
    const down = (e: TouchEvent) => {
      y0 = el.scrollTop <= 0 ? e.touches[0].clientY : null;
      distance = 0;
    };
    const move = (e: TouchEvent) => {
      if (y0 === null) return;
      distance = Math.max(0, e.touches[0].clientY - y0);
      setPull(distance);
    };
    const up = () => {
      if (y0 === null) return;
      y0 = null;
      setPull(0);
      if (distance > 80 && refreshRef.current) {
        setRefreshing(true);
        refreshRef.current().finally(() => setRefreshing(false));
      }
    };
    el.addEventListener("touchstart", down, { passive: true });
    el.addEventListener("touchmove", move, { passive: true });
    el.addEventListener("touchend", up);
    return () => {
      el.removeEventListener("touchstart", down);
      el.removeEventListener("touchmove", move);
      el.removeEventListener("touchend", up);
    };
  }, [!onRefresh]);

  const back =
    depth > 0 ? (
      <button className="bar-button back-button" onClick={nav.pop} aria-label={`Volver a ${parentTitle}`}>
        <ChevronLeft size={28} strokeWidth={2.2} />
        <span style={{ maxWidth: 110, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{parentTitle}</span>
      </button>
    ) : (
      leading
    );

  return (
    <>
      <header className={`navbar${scrolled ? " solid" : ""}`}>
        <div className="leading">{back}</div>
        <div className="inline-title" style={{ opacity: !large || scrolled ? 1 : 0 }} aria-hidden={large && !scrolled}>
          {title}
        </div>
        <div className="trailing">{trailing}</div>
      </header>
      <div className="scroll" ref={scrollRef} onScroll={onScroll}>
        {onRefresh && (
          <div className="ptr" style={{ height: refreshing ? 44 : Math.min(pull * 0.5, 60), opacity: refreshing ? 1 : Math.min(pull / 80, 1) }}>
            <Spinner size={22} />
          </div>
        )}
        {large && <h1 className="large-title">{title}</h1>}
        {bodyTop}
        {children}
      </div>
    </>
  );
}

// ---- Sheet (`.sheet`): slides up, swipe down on the bar to dismiss ----

export function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: (close: () => void) => ReactNode }) {
  const [closing, setClosing] = useState(false);
  const [drag, setDrag] = useState(0);
  const [dragging, setDragging] = useState(false);
  const start = useRef(0);

  const close = useCallback(() => {
    setClosing(true);
    setTimeout(onClose, 250);
  }, [onClose]);

  useLayoutEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    return () => prev?.focus?.();
  }, []);

  return createPortal(
    <>
      <div className="sheet-backdrop" style={{ opacity: closing ? 0 : 1, transition: "opacity .25s" }} />
      <div
        className="sheet"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        style={{
          transform: closing ? "translateY(100%)" : `translateY(${drag}px)`,
          transition: dragging ? "none" : "transform .25s ease-in",
        }}
      >
        <div
          onTouchStart={(e) => {
            start.current = e.touches[0].clientY;
            setDragging(true);
          }}
          onTouchMove={(e) => setDrag(Math.max(0, e.touches[0].clientY - start.current))}
          onTouchEnd={() => {
            setDragging(false);
            if (drag > 120) close();
            else setDrag(0);
          }}
        >
          <div className="grabber" />
          <header className="navbar">
            <div className="leading">
              <button className="bar-button" onClick={close}>
                Cancelar
              </button>
            </div>
            <div className="inline-title">{title}</div>
            <div className="trailing" />
          </header>
        </div>
        <div className="scroll">{children(close)}</div>
      </div>
    </>,
    document.body,
  );
}

// ---- Menu (iOS `Menu` from a toolbar button) ----

export function Menu({ items, onClose }: { items: { label: string; icon: ReactNode; destructive?: boolean; action: () => void }[]; onClose: () => void }) {
  return createPortal(
    <>
      <div className="menu-backdrop" onClick={onClose} />
      <div className="menu" role="menu">
        {items.map((it) => (
          <button
            key={it.label}
            role="menuitem"
            className={it.destructive ? "btn-destructive" : undefined}
            onClick={() => {
              onClose();
              it.action();
            }}
          >
            {it.label}
            {it.icon}
          </button>
        ))}
      </div>
    </>,
    document.body,
  );
}
