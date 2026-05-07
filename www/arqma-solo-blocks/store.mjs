import Database from 'better-sqlite3'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export function openDb (dbPath) {
  const db = new Database(dbPath || path.join(__dirname, 'solo_blocks.sqlite'))
  db.exec(`
    CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
    CREATE TABLE IF NOT EXISTS solo_blocks (
      hash TEXT PRIMARY KEY,
      miner_tx_hash TEXT,
      height INTEGER NOT NULL,
      difficulty INTEGER NOT NULL,
      timestamp INTEGER NOT NULL,
      reward TEXT,
      depth INTEGER DEFAULT 0,
      status INTEGER DEFAULT 0,
      scanned_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_solo_blocks_height ON solo_blocks(height DESC);
    CREATE TABLE IF NOT EXISTS poll_samples (
      ts_sec INTEGER PRIMARY KEY,
      network_hr INTEGER NOT NULL DEFAULT 0,
      chain_height INTEGER NOT NULL DEFAULT 0
    );
  `)
  return db
}

export function loadScanCursor (db) {
  const row = db.prepare('SELECT v FROM meta WHERE k = ?').get('last_scanned_height')
  if (!row?.v && row?.v !== 0) return -1
  const n = parseInt(String(row.v), 10)
  return Number.isFinite(n) ? n : -1
}

/** Next height to scan + % toward tip (same convention as the former wallet solo scan). */
export function computeChainScanProgress (db, chainTip, cfgStartHeight) {
  let next = loadScanCursor(db)
  if (!Number.isFinite(next) || next < 0) next = cfgStartHeight
  const tip = Math.max(0, Number(chainTip) || 0)
  const denom = tip + 1
  let progressPct = 0
  if (denom > 0) {
    progressPct = Math.min(100, (Math.min(next, denom) / denom) * 100)
  }
  const scannedThrough = next > 0 ? next - 1 : 0
  return {
    next_scan_height: next,
    chain_tip: tip,
    progress_pct: progressPct,
    scanned_through: scannedThrough,
    caught_up: next > tip,
  }
}

export function aggregateSoloFingerprintBlocks (db) {
  const row = db.prepare(`
    SELECT COUNT(*) AS c,
           COALESCE(SUM(CAST(difficulty AS REAL)), 0) AS s,
           MIN(height) AS hmin,
           MAX(height) AS hmax
    FROM solo_blocks
  `).get()
  return {
    fingerprint_blocks: Number(row.c) || 0,
    sum_difficulty: Number(row.s) || 0,
    min_height: row.hmin != null ? Number(row.hmin) : null,
    max_height: row.hmax != null ? Number(row.hmax) : null,
  }
}

export function saveScanCursor (db, height) {
  db.prepare(
    'INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v = excluded.v',
  ).run('last_scanned_height', String(height))
}

export function upsertBlock (db, row) {
  db.prepare(`
    INSERT INTO solo_blocks(hash, miner_tx_hash, height, difficulty, timestamp, reward, depth, status, scanned_at)
    VALUES(@hash,@miner_tx_hash,@height,@difficulty,@timestamp,@reward,@depth,@status,@scanned_at)
    ON CONFLICT(hash) DO UPDATE SET
      depth=@depth,
      status=@status,
      scanned_at=@scanned_at
  `).run(row)
}

export function listBlocks (db, limit = 500) {
  return db.prepare('SELECT * FROM solo_blocks ORDER BY height DESC LIMIT ?').all(limit)
}

/** Append one network snapshot per daemon poll (for charts). */
export function insertPollSample (db, tsSec, networkHr, chainHeight) {
  db.prepare(
    `INSERT OR REPLACE INTO poll_samples(ts_sec, network_hr, chain_height)
     VALUES (?,?,?)`,
  ).run(tsSec | 0, networkHr | 0, chainHeight | 0)
}

/** Points for network hashrate chart: [{ t: ms, hr }] since unix sec. */
export function getNetworkPollSeries (db, sinceTsSec) {
  const rows = db
    .prepare(
      `SELECT ts_sec, network_hr FROM poll_samples
       WHERE ts_sec >= ? ORDER BY ts_sec ASC`,
    )
    .all(sinceTsSec | 0)
  return rows.map((r) => ({
    t: r.ts_sec * 1000,
    hr: r.network_hr | 0,
  }))
}

/** Solo “activity” per UTC day: Σ(difficulty)/86400 as a scalar comparable to H/s order-of-magnitude. */
export function getSoloDifficultyDailySeries (db, sinceTsSec) {
  const rows = db
    .prepare(
      `SELECT difficulty, timestamp FROM solo_blocks WHERE timestamp >= ? ORDER BY timestamp ASC`,
    )
    .all(sinceTsSec | 0)
  const daySum = new Map()
  for (const r of rows) {
    const ts = Number(r.timestamp) || 0
    const dayStart = Math.floor(ts / 86400) * 86400
    daySum.set(dayStart, (daySum.get(dayStart) || 0) + (Number(r.difficulty) || 0))
  }
  return [...daySum.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([daySec, sumD]) => ({
      t: daySec * 1000,
      hr: Math.round(sumD / 86400),
    }))
}
