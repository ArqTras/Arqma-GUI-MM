"use strict"
const axios = require("axios")
const http = require("http")
const https = require("https")
const digest = require("./httpDigest")

const axiosDigest = {}

axiosDigest.createHttpClient = function (opts) {
  const instance = axios.create({
    httpAgent: new http.Agent({ keepAlive: true }),
    httpsAgent: new https.Agent({ keepAlive: true })
  })
  let httpDigest
  instance.defaults.digestHandlerEnabled = false
  if (typeof opts.username !== "undefined" && typeof opts.password !== "undefined") {
    httpDigest = digest.createHttpDigest(opts)
    instance.defaults.digestHandlerEnabled = true
  }

  instance.interceptors.response.use(function (response) {
    // No need to set Authorization header here; it's handled on retry
    return response
  }, function (error) {
    if (
      instance.defaults.digestHandlerEnabled &&
      error.response &&
      error.response.status === 401 &&
      !error.config._retry &&
      httpDigest
    ) {
      const wwwAuth = error.response.headers["www-authenticate"]
      error.config.headers = error.config.headers || {}
      error.config.headers.Authorization = httpDigest.handleResponse(
        error.request.method,
        error.request.path,
        wwwAuth
      )
      httpDigest.incNonce()
      error.config._retry = true
      return instance(error.config)
    }
    return Promise.reject(error)
  })

  instance.resetNonces = function () {
    if (httpDigest) return httpDigest.resetNonces()
  }
  return instance
}

exports = module.exports = axiosDigest
