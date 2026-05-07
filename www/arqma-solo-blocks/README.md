# Arqma solo blocks dashboard

Indeksuje bloki wygenerowane przez **wbudowany solo pool** w **Arqma-Wallet (Tauri)** wyłączeniem opcji **„Mimic public pool reservation”** (`pool.mining.uniform: false`). Wtedy daemon dostaje `get_block_template` z `reserve_size: 1`, co nadaje coinbase **`miner_tx.extra`** przewidywalny wzorzec (zgodny z konwencją z portfela Ryo / skanerem społecznościowym).

## Zgodność Fastify

`fastify` **5.x** wymaga `@fastify/static` **≥ 8.x**. Starsza seria 7.x jest tylko dla Fastify 4 — przy `FST_ERR_PLUGIN_VERSION_MISMATCH` usuń `node_modules`, zrób ponownie `npm install` po aktualizacji `package.json`.

## Uruchomienie

```bash
cd www/arqma-solo-blocks
cp config.example.json config.json
# Edytuj daemon_url (RPC Arqma, zwykle port z GUI) i ewentualnie start_height
npm install
npm start
```

Otwórz `http://127.0.0.1:9177` (port zmienny w `config.json`).

## Dopasowanie fingerprintu

Domyślnie sprawdzane jest: **`extra.length === 36`** oraz **`extra[33] === 2`**, **`extra[34] === 1`** (konfiguracja: `solo_fixed_extra_len`, `solo_marker_*`).

Jeśli po wykopaniu próbnego bloku nic się nie pojawia, pobierz `get_block` dla tej wysokości z daemona, sprawdź surowy `miner_tx.extra` (hex/tablica bajtów) i — w razie różnicy łańcucha Arqmy — dostosuj te trzy pola w `config.json`.

## Pliki

| Plik | Rola |
|------|------|
| `server.mjs` | Fastify + skan bloków |
| `fingerprint.mjs` | Bufory `extra` + test znacznika |
| `store.mjs` | SQLite (`solo_blocks.sqlite`) + próbki `poll_samples` pod wykres sieci |
| `public/index.html` | UI w stylu [ryo-wallet-solo-pool-website](https://github.com/mosu-forge/ryo-wallet-solo-pool-website) (layout dashboard / blocks / getting started), kolorystyka Arqmy |

Wykres **Network** budowany jest z okresowych zapisów hashrate sieci przy pollach daemona. Wykres **Solo** to Σ(trudność)/dzień (UTC) z indeksowanych bloków — przybliżenie aktywności, nie dokładny HR koparki.

Przy pierwszym skanowaniu na istniejącym łańcuchu ustaw sensowne **`start_height`** (np. wysokość aktywacji RandomX / ostatni hard fork), żeby nie czytać całej historii od zera.
