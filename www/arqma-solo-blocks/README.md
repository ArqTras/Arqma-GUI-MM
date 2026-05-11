# Arqma solo blocks dashboard

Scans the chain for **`miner_tx.extra`** matching the fingerprint (Ryo-family wallet convention). **Current Arqma-Wallet** with the solo pool always requests `get_block_template` with **`reserve_size: 8`** (same as public pools); this service still discovers **historical** blocks from older releases / tools that mined with **`reserve_size: 1`** and the same `extra` pattern.

## Fastify compatibility

`fastify` **5.x** requires `@fastify/static` **≥ 8.x**. The older 7.x line is for Fastify 4 only — if you see `FST_ERR_PLUGIN_VERSION_MISMATCH`, remove `node_modules` and run `npm install` again after updating `package.json`.

## Running

```bash
cd www/arqma-solo-blocks
cp config.example.json config.json
# Edit daemon_url (Arqma RPC, usually the GUI port) and optionally start_height
npm install
npm start
```

Open `http://127.0.0.1:9177` (port is configurable in `config.json`).

## Fingerprint matching

By default the checks are: **`extra.length === 36`**, **`extra[33] === 2`**, **`extra[34] === 1`** (see `solo_fixed_extra_len`, `solo_marker_*` in config).

If nothing appears after mining a test block, fetch `get_block` for that height from the daemon, inspect raw `miner_tx.extra` (hex / byte array), and — if your Arqma chain differs — adjust those three fields in `config.json`.

## Files

| File | Role |
|------|------|
| `server.mjs` | Fastify + block scan |
| `fingerprint.mjs` | `extra` buffers + marker test |
| `store.mjs` | SQLite (`solo_blocks.sqlite`) + `poll_samples` for the network chart |
| `public/index.html` | UI inspired by [ryo-wallet-solo-pool-website](https://github.com/mosu-forge/ryo-wallet-solo-pool-website) (dashboard / blocks / getting started layout), Arqma colors |

The **Network** chart comes from periodic network hashrate samples during daemon polls. The **Solo** chart is Σ(difficulty)/day (UTC) from indexed blocks — an activity approximation, not exact miner HR.

For the first scan on an existing chain, set a sensible **`start_height`** (e.g. RandomX activation height / last hard fork) so you do not read the whole history from genesis.
