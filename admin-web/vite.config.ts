import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

const rootDir = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(
  readFileSync(new URL("./package.json", import.meta.url), "utf8")
) as { version: string };

function emitVersionJson() {
  return {
    name: "emit-version-json",
    writeBundle() {
      const out = resolve(rootDir, "dist/version.json");
      mkdirSync(dirname(out), { recursive: true });
      writeFileSync(out, JSON.stringify({ version: pkg.version }));
    },
  };
}

export default defineConfig({
  plugins: [react(), emitVersionJson()],
  define: {
    "import.meta.env.VITE_APP_VERSION": JSON.stringify(pkg.version),
  },
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: "http://localhost:3000",
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: "dist",
  },
  test: {
    environment: "node",
  },
});
