#!/usr/bin/env node
/**
 * Deep-merge missing keys from en-US.json into every other *.json in the same folder.
 * Existing translations are preserved; gaps are filled with English (same value as en-US).
 *
 * Usage (from repo root):
 *   node flutter/arqma_wallet_gui/tool/sync_locale_json.mjs flutter/arqma_wallet_gui/assets/locales
 *   node flutter/arqma_wallet_gui/tool/sync_locale_json.mjs rust/tauri-app/src/locales
 *   node flutter/arqma_wallet_gui/tool/sync_locale_json.mjs src/locales
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function deepMergeMissing(canonical, target) {
  if (canonical === null || canonical === undefined) {
    return target;
  }
  if (typeof canonical !== "object" || Array.isArray(canonical)) {
    return target !== undefined ? target : canonical;
  }
  const result =
    target && typeof target === "object" && !Array.isArray(target)
      ? JSON.parse(JSON.stringify(target))
      : {};
  for (const [k, v] of Object.entries(canonical)) {
    if (!(k in result)) {
      result[k] = JSON.parse(JSON.stringify(v));
    } else if (
      v !== null &&
      typeof v === "object" &&
      !Array.isArray(v) &&
      result[k] !== null &&
      typeof result[k] === "object" &&
      !Array.isArray(result[k])
    ) {
      result[k] = deepMergeMissing(v, result[k]);
    }
  }
  return result;
}

const localesDir = process.argv[2];
if (!localesDir) {
  console.error(
    "usage: node sync_locale_json.mjs <locales-directory-containing-en-US.json>",
  );
  process.exit(1);
}

const abs = path.resolve(localesDir);
const canonicalPath = path.join(abs, "en-US.json");
if (!fs.existsSync(canonicalPath)) {
  console.error(`missing canonical file: ${canonicalPath}`);
  process.exit(1);
}

const canonical = JSON.parse(fs.readFileSync(canonicalPath, "utf8"));
const files = fs.readdirSync(abs).filter((f) => f.endsWith(".json"));

for (const file of files) {
  if (file === "en-US.json") continue;
  const p = path.join(abs, file);
  let existing = {};
  try {
    existing = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    console.error(`skip broken JSON ${p}: ${e.message}`);
    continue;
  }
  const merged = deepMergeMissing(canonical, existing);
  fs.writeFileSync(p, JSON.stringify(merged, null, 4) + "\n", "utf8");
  console.log(`updated: ${p}`);
}

console.log(`done (${files.length - 1} files, canonical ${canonicalPath})`);
