/** @typedef {{ solo_fixed_extra_len?: number, solo_marker_high?: number, solo_marker_low?: number }} FpCfg */

/**
 * Daemon may return miner_tx.extra as hex string or byte array.
 * @param {unknown} extra
 * @returns {Buffer | null}
 */
export function extraToBuffer(extra) {
  if (extra == null) return null
  if (Buffer.isBuffer(extra)) return extra
  if (typeof extra === 'string') {
    const s = extra.trim()
    if (s.length % 2 !== 0) return null
    try {
      return Buffer.from(s, 'hex')
    } catch {
      return null
    }
  }
  if (Array.isArray(extra)) {
    try {
      return Buffer.from(extra.map((x) => Number(x) & 0xff))
    } catch {
      return null
    }
  }
  return null
}

/**
 * Matches Ryo/Arqma-Wallet convention when solo pool asks `reserve_size: 1`:
 * miner_tx.extra is 36 bytes with marker bytes at indexes 33,34 (= 2, 1).
 * @param {Buffer | null} buf
 * @param {FpCfg} [cfg]
 */
export function matchesSoloFingerprint(buf, cfg = {}) {
  if (!buf) return false
  const len = cfg.solo_fixed_extra_len ?? 36
  const hi = cfg.solo_marker_high ?? 2
  const lo = cfg.solo_marker_low ?? 1
  return buf.length === len && buf[33] === hi && buf[34] === lo
}
