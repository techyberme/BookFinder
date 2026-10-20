import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles.css";

// No pinch-zoom: iOS ignores `user-scalable=no` in the viewport meta, but honours these.
for (const type of ["gesturestart", "gesturechange"]) document.addEventListener(type, (e) => e.preventDefault());

if ("serviceWorker" in navigator && import.meta.env.PROD) {
  window.addEventListener("load", () => navigator.serviceWorker.register("/sw.js").catch(() => {}));
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
