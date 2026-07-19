import { defineConfig } from 'vite'

export default defineConfig({
  appType: 'spa',
  server: {
    port: 4184,
    proxy: {
      '/api': 'http://127.0.0.1:8000',
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
