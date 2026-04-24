"use strict"

const crypto = require("crypto")

function generateCnonce () {
  const ha1 = crypto.createHash("MD5")
  ha1.update(crypto.randomBytes(16).toString("base64"))
  return ha1.digest("hex")
}

function generateResponseHash (method, path, challenge, username, password, nc, cnonce) {
  if (!challenge.realm || !challenge.nonce) {
    throw new Error("Missing required digest challenge fields (realm or nonce)")
  }

  const ha1 = crypto.createHash("MD5")
  ha1.update([username, challenge.realm, password].join(":"))
  const ha1Hex = ha1.digest("hex")

  const ha2 = crypto.createHash("MD5")
  ha2.update([method, path].join(":"))
  const ha2Hex = ha2.digest("hex")

  // If qop is present, use RFC 2617 format; otherwise, use legacy format
  if (challenge.qop) {
    // Use the first qop value if multiple are provided (e.g., "auth,auth-int")
    const qop = challenge.qop.split(",")[0].trim()
    if (!nc || !cnonce) {
      throw new Error("Missing nc or cnonce for qop-protected digest authentication")
    }
    const res = crypto.createHash("MD5")
    const joined = [ha1Hex, challenge.nonce, nc, cnonce, qop, ha2Hex].join(":")
    res.update(joined)
    return res.digest("hex")
  } else {
    // Legacy RFC 2069 format (no qop)
    const res = crypto.createHash("MD5")
    const joined = [ha1Hex, challenge.nonce, ha2Hex].join(":")
    res.update(joined)
    return res.digest("hex")
  }
}

function parseChallenge (header) {
  const prefix = "Digest"
  if (typeof header !== "string") return {}
  const prefixIndex = header.indexOf(prefix)
  if (prefixIndex === -1) return {}
  const challenge = header.slice(prefixIndex + prefix.length)
  const parts = challenge.split(",")
  const params = {}
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i].match(/^\s*?([a-zA-Z0-9]+)="(.*)"\s*?$/)
    if (part && part.length > 2) {
      params[part[1]] = part[2]
    }
  }
  return params
}

function renderDigest (params) {
  const parts = []
  for (const i in params) {
    if (i === "nc" || i === "algorithm") {
      parts.push(i + "=" + params[i])
    } else {
      parts.push(i + "=\"" + params[i] + "\"")
    }
  }
  return "Digest " + parts.join(",")
}

const digest = {}

digest.createHttpDigest = function (opts) {
  if (typeof opts.username === "undefined" || typeof opts.password === "undefined") {
    throw new Error("Missing user and/or password!")
  }
  const username = opts.username
  const password = opts.password
  let nc = opts.nc || "00000001"
  let cnonce = opts.cnonce || generateCnonce()
  return {
    handleResponse: function (method, path, authHeaders) {
      const challenge = parseChallenge(authHeaders)
      const requestParams = {
        username,
        realm: challenge.realm,
        nonce: challenge.nonce,
        uri: path,
        cnonce,
        nc,
        algorithm: "MD5",
        response: generateResponseHash(method, path, challenge, username, password, nc, cnonce),
        qop: challenge.qop
      }
      return renderDigest(requestParams)
    },
    incNonce: function () {
      if (nc === "ffffffff") {
        nc = "00000001"
      } else {
        const s = "00000000" + (parseInt(nc, 16) + 1).toString(16)
        nc = s.substr(s.length - 8)
      }
      return nc
    },
    resetNonces: function () {
      nc = "00000001"
      cnonce = generateCnonce()
      return true
    }
  }
}

exports = module.exports = digest
