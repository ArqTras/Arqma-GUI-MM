#!/usr/bin/env node
/**
 * Generuje locale_fallback_rows.json (155 x 11) — kolejność identyczna jak _missing_en_strings.json.
 * Uruchom: node generate_locale_fallback_rows.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

import { rowChunks } from "./locale_fallback_row_chunks.mjs";

const keys = JSON.parse(
  fs.readFileSync(path.join(__dirname, "_missing_en_strings.json"), "utf8"),
);

const rows = rowChunks.flat();
if (rows.length !== keys.length) {
  throw new Error(`rows ${rows.length} !== keys ${keys.length}`);
}
for (let i = 0; i < rows.length; i++) {
  if (!Array.isArray(rows[i]) || rows[i].length !== 11) {
    throw new Error(`bad row ${i}`);
  }
}

const out = path.join(__dirname, "locale_fallback_rows.json");
fs.writeFileSync(out, JSON.stringify(rows) + "\n", "utf8");
console.log("wrote", out, rows.length, "x 11");
