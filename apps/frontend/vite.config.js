import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // Local dev: proxy /api → a backend running on localhost:5678.
    // In production this proxy is done by nginx (see nginx.conf).
    proxy: {
      "/api": "http://localhost:5678",
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/setupTests.js"],
  },
});
