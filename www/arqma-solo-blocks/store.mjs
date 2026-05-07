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
  `)
  return db
}

export function loadScanCursor (db) {
  const row = db.prepare('SELECT v FROM meta WHERE k = ?').get('last_scanned_height')
  if (!row?.v && row?.v !== 0) return -1
  const n = parseInt(String(row.v), 10)
  return Number.isFinite(n) ? n : -1
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
