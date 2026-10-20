import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // The FastAPI backend (python3 run.py) serves /api on port 8000.
    proxy: { "/api": "http://127.0.0.1:8000" },
    // libraries.json is shared with the iOS app (ios/ZahoriKit/.../Resources).
    fs: { allow: [".."] },
  },
});
