/// <reference types="vitest/config" />
import { fileURLToPath, URL } from 'node:url'
import tailwindcss from '@tailwindcss/vite'
import { tanstackRouter } from '@tanstack/router-plugin/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Phoenix in development (`mix phx.server`).
const phoenix = 'http://localhost:4000'

export default defineConfig({
  plugins: [
    // Generates src/routeTree.gen.ts from src/routes/; must run before react().
    tanstackRouter({ target: 'react', autoCodeSplitting: true }),
    react(),
    tailwindcss(),
  ],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  // Same origin in development too: the dev server forwards the API and the
  // dashboard socket to Phoenix, so the SPA never needs CORS.
  server: {
    proxy: {
      '/api': phoenix,
      '/socket': { target: phoenix, ws: true },
    },
  },
  // Phoenix serves the built SPA from priv/static (see CourierWeb.SpaController).
  build: {
    outDir: '../priv/static',
    emptyOutDir: true,
  },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.test.{ts,tsx}'],
    setupFiles: ['./tests/setup.ts', './tests/support/live-setup.ts'],
  },
})
