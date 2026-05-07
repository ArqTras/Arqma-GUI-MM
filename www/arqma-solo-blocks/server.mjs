#!/usr/bin/env node
/**
 * Skanuje daemon Arqmy po `miner_tx.extra` i indeksuje bloki wygenerowane przy `reserve_size: 1`
 * (solo pool przy wyłączonej opcji „Mimic public pool”).
 */
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import Fastify from 'fastify'
import fastifyStatic from '@fastify/static'

import { extraToBuffer, matchesSoloFingerprint } from './fingerprint.mjs'
import {
  openDb,
  loadScanCursor,
  saveScanCursor,
  upsertBlock,
  listBlocks,
  insertPollSample,
  getNetworkPollSeries,
  getSoloDifficultyDailySeries,
  computeChainScanProgress,
  aggregateSoloFingerprintBlocks,
} from './store.mjs'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const CFG_PATH =
  process.env.ARQMA_SOLO_BLOCKS_CONFIG ||
  path.join(__dirname, 'config.json')

const THIRTY_DAYS_SEC = 30 * 86400

function loadCfg () {
  if (!fs.existsSync(CFG_PATH)) {
    console.error(`Missing ${CFG_PATH} — copy config.example.json to config.json`)
    process.exit(1)
  }
  const raw = JSON.parse(fs.readFileSync(CFG_PATH, 'utf8'))
  return {
    daemon_url: raw.daemon_url.replace(/\/+$/, ''),
    listen_host: raw.listen_host || '127.0.0.1',
    listen_port: Number(raw.listen_port) || 9177,
    start_height: parseInt(raw.start_height ?? '0', 10) || 0,
    scan_batch_heights: Math.min(
      500,
      Math.max(10, parseInt(raw.scan_batch_heights ?? '120', 10)),
    ),
    poll_interval_seconds: Math.max(
      5,
      parseInt(raw.poll_interval_seconds ?? '30', 10),
    ),
    block_target_seconds: Math.max(
      1,
      parseInt(raw.block_target_seconds ?? '120', 10),
    ),
    confirmation_depth: Math.max(1, parseInt(raw.confirmation_depth ?? '60', 10)),
    explorer_block_url_template: raw.explorer_block_url_template || '',
    solo_fixed_extra_len: Number(raw.solo_fixed_extra_len) || 36,
    solo_marker_high: Number(raw.solo_marker_high) || 2,
    solo_marker_low: Number(raw.solo_marker_low) || 1,
  }
}

async function daemonRpc (cfg, method, params = undefined) {
  const body = { jsonrpc: '2.0', id: `${Date.now()}`, method }
  if (params !== undefined) body.params = params
  const url = `${cfg.daemon_url}/json_rpc`
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`daemon HTTP ${res.status}`)
  const j = await res.json()
  if (j.error) throw new Error(j.error.message || JSON.stringify(j.error))
  return j.result
}

async function pollChainTip (cfg) {
  const info = await daemonRpc(cfg, 'get_info')
  const tip = Number(info.height ?? info.target_height ?? 0)
  return tip
}

function fpCfgFrom (cfg) {
  return {
    solo_fixed_extra_len: cfg.solo_fixed_extra_len,
    solo_marker_high: cfg.solo_marker_high,
    solo_marker_low: cfg.solo_marker_low,
  }
}

async function scanRange (cfg, db, tip) {
  const fpCfg = fpCfgFrom(cfg)

  let start = loadScanCursor(db)
  if (!Number.isFinite(start) || start < 0) start = cfg.start_height

  if (start > tip) {
    saveScanCursor(db, start)
    return
  }

  const endExclusive = Math.min(start + cfg.scan_batch_heights, tip + 1)
  const scannedAt = Date.now()

  for (let h = start; h < endExclusive; h++) {
    const blk = await daemonRpc(cfg, 'get_block', { height: h })
    const bh = blk.block_header || blk
    let inner = null
    if (blk.json && typeof blk.json === 'string') {
      try {
        inner = JSON.parse(blk.json)
      } catch {
        inner = null
      }
    }
    const minerTx =
      inner && typeof inner === 'object' ? inner.miner_tx : blk.miner_tx
    const extraBuf = minerTx ? extraToBuffer(minerTx.extra) : null

    if (matchesSoloFingerprint(extraBuf, fpCfg)) {
      const hash = String(bh.hash || '')
      const miner_tx_hash = String(blk.miner_tx_hash || '')
      let rewardAmt = ''
      if (minerTx && Array.isArray(minerTx.vout) && minerTx.vout[0]) {
        if (minerTx.vout[0].amount !== undefined)
          rewardAmt = String(minerTx.vout[0].amount)
      }
      const depth = tip - h
      const status = depth >= cfg.confirmation_depth ? 2 : 0
      const tsRaw = bh.timestamp ?? inner?.timestamp ?? 0

      upsertBlock(db, {
        hash: hash || `missing-hash-${h}`,
        miner_tx_hash: String(miner_tx_hash || ''),
        height: h,
        difficulty: Number(bh.difficulty || 0) || 0,
        timestamp: Number(tsRaw) || 0,
        reward: rewardAmt,
        depth,
        status,
        scanned_at: scannedAt,
      })
    }
    saveScanCursor(db, h + 1)
  }

  try {
    db.prepare(
      `
      UPDATE solo_blocks SET
        depth = ?1 - height,
        status = CASE WHEN (?1 - height) >= ?2 THEN 2 ELSE status END`,
    ).run(tip, cfg.confirmation_depth)
  } catch (_) {
    /**/
  }
}

/**
 * One JSON payload for the Ryo-style dashboard + blocks table.
 */
function buildStatsPayload (cfg, db, info) {
  const tip = Number(info.height ?? 0)
  const netDiff = Number(info.difficulty ?? 0) || 0
  const target =
    Number(info.target ?? cfg.block_target_seconds) || cfg.block_target_seconds
  const networkHr = netDiff && target ? Math.floor(netDiff / target) : 0

  const rawBlocks = listBlocks(db, 2000)
  const blocks = rawBlocks.map((b) => {
    const conf = tip - Number(b.height)
    const tmpl = cfg.explorer_block_url_template
    const ts = Number(b.timestamp) || 0
    return {
      hash: b.hash,
      miner_tx_hash: b.miner_tx_hash,
      height: b.height,
      difficulty: b.difficulty,
      timestamp: ts,
      reward: b.reward,
      status: Number(b.status ?? 0),
      confirmed: conf >= cfg.confirmation_depth,
      confirmations_pending: Math.max(0, cfg.confirmation_depth - conf),
      explorer_link:
        tmpl &&
        tmpl
          .replace('{height}', String(b.height))
          .replace('{hash}', b.hash || ''),
    }
  })

  const newest = blocks[0]
  const lastTsSec = newest ? Number(newest.timestamp) || 0 : 0

  /** Naive solo HR: last indexed block difficulty / target interval (like wallet effort scaling). */
  let estimatedSoloHr = 0
  if (newest && newest.difficulty) {
    estimatedSoloHr = Math.floor(Number(newest.difficulty) / target)
  }

  let blockTimeEstMs = 0
  if (estimatedSoloHr > 0 && networkHr > 0) {
    blockTimeEstMs = Math.floor(
      (1000 * target * networkHr) / estimatedSoloHr,
    )
  }

  const nowSec = Math.floor(Date.now() / 1000)
  const sinceSec = nowSec - THIRTY_DAYS_SEC

  const charts = {
    network: getNetworkPollSeries(db, sinceSec),
    solo: getSoloDifficultyDailySeries(db, sinceSec),
  }

  const scanProg = computeChainScanProgress(db, tip, cfg.start_height)
  const fpAgg = aggregateSoloFingerprintBlocks(db)
  const recentFp = listBlocks(db, 20).map((b) => ({
    height: b.height,
    difficulty: b.difficulty,
    timestamp: b.timestamp,
    hash: b.hash,
  }))

  return {
    chain_height: tip,
    network_difficulty: netDiff,
    network_hashrate_est: networkHr,
    network_target_interval_sec: target,
    confirmation_depth: cfg.confirmation_depth,
    solo_blocks_found: blocks.length,
    estimated_solo_hashrate: estimatedSoloHr,
    block_time_est_ms: blockTimeEstMs,
    last_block_timestamp_sec: lastTsSec,
    solo_fee_percent: 0,
    blocks,
    charts,
    chain_fingerprint_scan: {
      ...scanProg,
      ...fpAgg,
      start_height_config: cfg.start_height,
      scan_batch_heights: cfg.scan_batch_heights,
      poll_interval_seconds: cfg.poll_interval_seconds,
      recent_blocks: recentFp,
    },
  }
}

const once = process.argv.includes('--once')

;(async () => {
  const cfg = loadCfg()
  const dbPath = path.join(__dirname, 'solo_blocks.sqlite')
  const db = openDb(dbPath)

  async function tick () {
    const tip = await pollChainTip(cfg)
    await scanRange(cfg, db, tip)
    try {
      const info = (await daemonRpc(cfg, 'get_info')) || {}
      const netDiff = Number(info.difficulty ?? 0) || 0
      const target =
        Number(info.target ?? cfg.block_target_seconds) ||
        cfg.block_target_seconds
      const networkHr = netDiff && target ? Math.floor(netDiff / target) : 0
      insertPollSample(db, Math.floor(Date.now() / 1000), networkHr, tip)
    } catch (_) {
      /**/
    }
    return tip
  }

  if (once) {
    const tip = await tick()
    console.log(`Scanned toward tip=${tip}`)
    db.close()
    process.exit(0)
  }

  const app = Fastify({ logger: false })
  await app.register(fastifyStatic, {
    root: path.join(__dirname, 'public'),
    prefix: '/',
    index: ['index.html'],
  })

  app.get('/api/health', async () => ({ ok: true }))
  app.get('/api/config', async () => ({
    explorer_block_url_template: cfg.explorer_block_url_template,
    block_target_seconds: cfg.block_target_seconds,
    fingerprint: fpCfgFrom(cfg),
  }))
  app.get('/api/stats', async (_req, reply) => {
    try {
      let info = {}
      try {
        info = (await daemonRpc(cfg, 'get_info')) || {}
      } catch (e) {
        reply.code(503).send({ error: String(e.message || e) })
        return
      }
      reply.send(buildStatsPayload(cfg, db, info))
    } catch (e) {
      reply.code(500).send({ error: String(e.message || e) })
    }
  })

  await app.listen({ host: cfg.listen_host, port: cfg.listen_port })
  console.log(`Dashboard → http://${cfg.listen_host}:${cfg.listen_port}`)
  console.log(`Daemon    → ${cfg.daemon_url}/json_rpc`)

  for (;;) {
    try {
      const tip = await tick()
      const n = db.prepare(`SELECT COUNT(*) AS c FROM solo_blocks`).get().c
      if (process.stdout.isTTY)
        process.stdout.write(`\r[h=${tip}] solo rows=${n}   `)
    } catch (e) {
      console.warn('poll:', e.message || e)
    }
    await new Promise((r) =>
      setTimeout(r, cfg.poll_interval_seconds * 1000),
    )
  }
})()
