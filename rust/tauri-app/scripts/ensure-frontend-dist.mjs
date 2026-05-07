#!/usr/bin/env node
/**
 * `tauri::generate_context!()` wymaga istniejącego katalogu `frontendDist` (`../dist`) przy kompilacji Rust.
 * Po `cargo clean` lub usunięciu `dist` uruchom jednorazowo `vite build`.
 */
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import { spawnSync } from 'node:child_process'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.join(__dirname, '..')
const indexHtml = path.join(root, 'dist', 'index.html')

if (fs.existsSync(indexHtml)) {
  process.exit(0)
}

console.error('[ensure-dist] Brak dist/index.html — uruchamiam vite build (wymagane przez Tauri przy cargo).')
const r = spawnSync('npm', ['run', 'build'], {
  stdio: 'inherit',
  cwd: root,
  shell: process.platform === 'win32',
})
process.exit(r.status ?? 1)
