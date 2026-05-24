#!/usr/bin/env node
/**
 * Zastępuje ciągi nadal identyczne z en-US (angielski fallback po sync)
 * wartościami z locale_fallback_rows.json (wiersze wg kolejności _missing_en_strings.json).
 *
 * Użycie (repo root lub ten katalog):
 *   node flutter/arqma_wallet_gui/tool/apply_locale_fallback_translations.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const LOCALE_CODES = [
  "ar-SA",
  "cn-CN",
  "de-DE",
  "es-ES",
  "fr-FR",
  "jp-JP",
  "ms-MY",
  "pl-PL",
  "pt-BR",
  "ru-RU",
  "ua-UA",
];

function loadJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function deepApply(en, loc, localeCode, table) {
  if (typeof en === "string" && typeof loc === "string") {
    if (en === loc) {
      const row = table.get(en);
      if (row && Object.prototype.hasOwnProperty.call(row, localeCode)) {
        const t = row[localeCode];
        if (t !== undefined) return t;
      }
    }
    return loc;
  }
  if (
    en &&
    typeof en === "object" &&
    !Array.isArray(en) &&
    loc &&
    typeof loc === "object" &&
    !Array.isArray(loc)
  ) {
    const result = { ...loc };
    for (const k of Object.keys(en)) {
      if (k in loc) {
        result[k] = deepApply(en[k], loc[k], localeCode, table);
      }
    }
    return result;
  }
  return loc;
}

function buildTable(keys, rows) {
  if (keys.length !== rows.length) {
    throw new Error(
      `locale_fallback_rows: keys ${keys.length} !== rows ${rows.length}`,
    );
  }
  const m = new Map();
  for (let i = 0; i < keys.length; i++) {
    const row = rows[i];
    if (!Array.isArray(row) || row.length !== LOCALE_CODES.length) {
      throw new Error(
        `Row ${i}: expected ${LOCALE_CODES.length} cells, got ${row?.length}`,
      );
    }
    const entry = {};
    for (let j = 0; j < LOCALE_CODES.length; j++) {
      entry[LOCALE_CODES[j]] = row[j];
    }
    m.set(keys[i], entry);
  }
  return m;
}

function main() {
  const keysPath = path.join(__dirname, "_missing_en_strings.json");
  const rowsPath = path.join(__dirname, "locale_fallback_rows.json");
  const keys = loadJson(keysPath);
  const rows = loadJson(rowsPath);
  const table = buildTable(keys, rows);

  const dirs = [
    path.join(__dirname, "../assets/locales"),
    path.join(__dirname, "../../../rust/tauri-app/src/locales"),
    path.join(__dirname, "../../../src/locales"),
  ];

  for (const dir of dirs) {
    if (!fs.existsSync(dir)) {
      console.warn("skip (missing):", dir);
      continue;
    }
    const enPath = path.join(dir, "en-US.json");
    if (!fs.existsSync(enPath)) {
      console.warn("skip (no en-US):", dir);
      continue;
    }
    const en = loadJson(enPath);
    for (const file of fs.readdirSync(dir).filter(
      (f) => f.endsWith(".json") && f !== "en-US.json",
    )) {
      const localeCode = file.replace(/\.json$/, "");
      if (!LOCALE_CODES.includes(localeCode)) {
        console.warn("skip (unknown locale):", file);
        continue;
      }
      const p = path.join(dir, file);
      const loc = loadJson(p);
      const next = deepApply(en, loc, localeCode, table);
      fs.writeFileSync(p, JSON.stringify(next, null, 4) + "\n", "utf8");
      console.log("updated", p);
    }
  }
}

main();
