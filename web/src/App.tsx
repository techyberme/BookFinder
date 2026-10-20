// Root view: a tab bar with one navigation stack per tab (RootView in ios/Zahori/ZahoriApp.swift).
import { useEffect, useState } from "react";
import { CalendarClock, Landmark, LibraryBig, Search } from "lucide-react";
import { launch } from "./store";
import { LibrariesScreen } from "./ui/LibrariesScreen";
import { LoansScreen } from "./ui/LoansScreen";
import { NavStack } from "./ui/nav";
import { SearchScreen } from "./ui/SearchScreen";
import { ShelfScreen } from "./ui/ShelfScreen";

const TABS = [
  { title: "Estantería", icon: LibraryBig, screen: ShelfScreen },
  { title: "Buscar", icon: Search, screen: SearchScreen },
  { title: "Préstamos", icon: CalendarClock, screen: LoansScreen },
  { title: "Bibliotecas", icon: Landmark, screen: LibrariesScreen },
];

export function App() {
  const [tab, setTab] = useState(0);
  useEffect(launch, []);

  return (
    <div className="app">
      <main className="tab-content">
        {TABS.map(({ title, screen: TabScreen }, i) => (
          <NavStack key={title} active={tab === i} rootTitle={title}>
            <TabScreen />
          </NavStack>
        ))}
      </main>
      <nav className="tabbar" role="tablist">
        {TABS.map(({ title, icon: Icon }, i) => (
          <button
            key={title}
            role="tab"
            aria-selected={tab === i}
            onClick={() => (tab === i ? window.dispatchEvent(new Event("zahori:retap")) : setTab(i))}
          >
            <Icon size={25} strokeWidth={tab === i ? 2.1 : 1.8} />
            {title}
          </button>
        ))}
      </nav>
    </div>
  );
}
