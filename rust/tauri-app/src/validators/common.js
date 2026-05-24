/* eslint-disable prefer-promise-reject-errors */

export const greater_than_zero = (input) => {
  return input > 0
}

export const greater_equal_to_ten_thousand = (input) => {
  return input >= 10000
}

export const register_service_node = (input) => {
  const tokens = input.split(" ")
  if (tokens.length !== 7) { return false }
  if (tokens[0] !== "register_service_node") { return false }
  if (!(/^[0-9A-Za-z]+$/.test(tokens[2]))) { return false }
  return true
}

export const payment_id = (input) => {
  return !input || input.length === 0 || (/^[0-9A-Fa-f]+$/.test(input) && (input.length === 16 || input.length === 64))
}

export const privkey = (input) => {
  return input.length === 0 || (/^[0-9A-Fa-f]+$/.test(input) && input.length === 64)
}

export const service_node_key = (input) => {
  return input.length === 64 && /^[0-9A-Za-z]+$/.test(input)
}

export const trimmedRequired = (value) => !!value && value.trim().length > 0

export const address = (input, gateway) => {
  if (!(/^[0-9A-Za-z]+$/.test(input))) return false

  // Validate the address
  return new Promise((resolve, reject) => {
    gateway.once("validate_address", (data) => {
      if (data.address && data.address !== input) {
        reject()
      } else {
        if (data.valid) {
          resolve()
        } else {
          reject()
        }
      }
    })
    gateway.send("wallet", "validate_address", {
      address: input
    })
  })
}
