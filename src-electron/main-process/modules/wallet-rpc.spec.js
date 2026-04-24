import { describe, expect, it, beforeEach } from "@jest/globals"
import { WalletRPC } from "./wallet-rpc"
import get_address_book from "./mock-data/get_address_book"
import get_transfers from "./mock-data/get_transfers"
const crypto = require("crypto")

jest.mock("electron")
jest.mock("./logger", () => ({
  ...jest.requireActual("./logger"),
  info: jest.fn(),
  error: jest.fn()
}))

let walletRPC
const password = "123456"
const salt = "abcdefghijklmnopqrstuvwxyz"

beforeEach(() => {
  const backend = {
    config_data: {
      app: {
        promptForPassword: true
      }
    }
  }
  walletRPC = new WalletRPC(backend)
  walletRPC.wallet_state.password_hash = crypto.pbkdf2Sync(password, salt, 1000, 64, "sha512")
})

describe("isValidPasswordHash", () => {
  it("should return true when password_hash matches", () => {
    // ARRANGE
    const expected = true
    const passwordString = "123456"
    const password_hash = crypto.pbkdf2Sync(passwordString, salt, 1000, 64, "sha512")
    // ACT
    const actual = walletRPC.isValidPasswordHash(password_hash)
    // ASSERT
    expect(actual).toBe(expected)
  })

  it("should return false when password_hash does not match", () => {
    // ARRANGE
    const expected = false
    const passwordString = "1234567"
    const password_hash = crypto.pbkdf2Sync(passwordString, salt, 1000, 64, "sha512")
    // ACT
    const actual = walletRPC.isValidPasswordHash(password_hash)
    // ASSERT
    expect(actual).toBe(expected)
  })

  it("should return false when password_hash does not match", () => {
    // ARRANGE
    const expected = false
    const passwordString = "1234567"
    const password_hash = crypto.pbkdf2Sync(passwordString, salt, 1000, 64, "sha512")
    // ACT
    const actual = walletRPC.isValidPasswordHash(password_hash)
    // ASSERT
    expect(actual).toBe(expected)
  })

  it("should return false when exception occurs", () => {
    // ARRANGE
    walletRPC.wallet_state = null
    const expected = false
    const passwordString = "1234567"
    const password_hash = crypto.pbkdf2Sync(passwordString, salt, 1000, 64, "sha512")
    // ACT
    const actual = walletRPC.isValidPasswordHash(password_hash)
    // ASSERT
    expect(actual).toBe(expected)
  })
})

describe("hasPassword", () => {
  it("should invoke sendGatway `set_has_password` with false", () => {
    // ARRANGE
    walletRPC.wallet_state.password_hash = null
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    walletRPC.hasPassword()
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_has_password", false)
  })
  it("should invoke sendGatway `set_has_password` with true, when promptForPassword enabled", () => {
    // ARRANGE
    walletRPC.backend.config_data.app.promptForPassword = false
    walletRPC.wallet_state = {
      password_hash: Buffer.from("abcdefg")
    }
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    walletRPC.hasPassword()
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_has_password", true)
  })
  it("should invoke sendGatway `set_has_password` with false on exception", () => {
    // ARRANGE
    walletRPC.wallet_state = null
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    walletRPC.hasPassword()
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_has_password", false)
  })
  it("should invoke sendGatway `set_has_password` with false when password is set and hashBuffer is from empty string", () => {
    // ARRANGE
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    walletRPC.hasPassword()
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_has_password", false)
  })
})

describe("validateAddress", () => {
  it("should invoke sendGateway `set_valid_address` when address is valid", async () => {
    // ARRANGE
    const address = "Tw1AXwU3z9kjMc5z21PaZ6HfQAJXmJbpWC6rdQtW7jw3Agp4t47UokKKTVkcXUTjYo4wtfu9nY87v1uJhKEpEpJv2DdeqLpwj"
    walletRPC.sendRPC = jest.fn((value) => {
      return Promise.resolve({
        result: {
          integrated: false,
          nettype: "mainnet",
          openalias_address: "",
          subaddress: false,
          valid: true
        }
      })
    })
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    await walletRPC.validateAddress(address)
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_valid_address", { address, valid: true, nettype: "mainnet" })
  })
  it("should invoke sendGateway `set_valid_address` with invalid, when rpc returns error", async () => {
    // ARRANGE
    const address = "Tw1AXwU3z9kjMc5z21PaZ6HfQAJXmJbpWC6rdQtW7jw3Agp4t47UokKKTVkcXUTjYo4wtfu9nY87v1uJhKEpEpJv2DdeqLpwj"
    walletRPC.sendRPC = jest.fn((value) => {
      return Promise.resolve({
        error: {
          code: 500,
          message: "foo bar",
          cause: "something borked!"
        }
      })
    })
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    await walletRPC.validateAddress(address)
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_valid_address", { address, valid: false })
  })
  it("should invoke sendGateway `set_valid_address` with invalid, when exception occurs", async () => {
    // ARRANGE
    const address = "Tw1AXwU3z9kjMc5z21PaZ6HfQAJXmJbpWC6rdQtW7jw3Agp4t47UokKKTVkcXUTjYo4wtfu9nY87v1uJhKEpEpJv2DdeqLpwj"
    walletRPC.sendRPC = jest.fn((value) => {
      return Promise.resolve(null)
    })
    const spy = jest.spyOn(walletRPC, "sendGateway")
    // ACT
    await walletRPC.validateAddress(address)
    // ASSERT
    expect(spy).toHaveBeenCalledWith("set_valid_address", { address, valid: false })
  })
})

describe("createWallet", () => {
  it("should invoke finalizeWallet when create wallet rpc is successful", async () => {
    // ARRANGE
    const sendRPCSpy = jest.spyOn(walletRPC, "sendRPC").mockReturnValue(
      Promise.resolve({
        result: {}
      })
    )
    walletRPC.auth = ["", "", salt]
    const filename = "foo"
    const password = "123456"
    const language = "English"
    const sendGatewaySpy = jest.spyOn(walletRPC, "sendGateway")
    walletRPC.finalizeNewWallet = jest.fn(value => Promise.resolve())
    const finalizeNewWalletSpy = jest.spyOn(walletRPC, "finalizeNewWallet")
    // ACT
    await walletRPC.createWallet(filename, password, language)
    // ASSERT
    expect(sendGatewaySpy).toHaveBeenCalledWith("reset_wallet_error")
    expect(sendGatewaySpy).not.toHaveBeenCalledWith("set_wallet_error")
    expect(finalizeNewWalletSpy).toHaveBeenCalledWith(filename)
    expect(sendRPCSpy).toHaveBeenCalledWith("create_wallet", { filename, password, language })
  })
  it("should not invoke finalizeWallet when create wallet rpc is unsuccessful", async () => {
    // ARRANGE
    const error = {
      code: 500,
      message: "foo bar",
      cause: "something borked!"
    }
    const sendRPCSpy = jest.spyOn(walletRPC, "sendRPC").mockReturnValue(
      Promise.resolve({
        error
      })
    )
    walletRPC.auth = ["", "", salt]
    const filename = "foo"
    const password = "123456"
    const language = "English"
    const sendGatewaySpy = jest.spyOn(walletRPC, "sendGateway")
    walletRPC.finalizeNewWallet = jest.fn(value => Promise.resolve())
    const finalizeNewWalletSpy = jest.spyOn(walletRPC, "finalizeNewWallet")
    // ACT
    await walletRPC.createWallet(filename, password, language)
    // ASSERT
    expect(sendGatewaySpy).toHaveBeenCalledWith("reset_wallet_error")
    expect(sendGatewaySpy).toHaveBeenCalledWith("set_wallet_error", { status: error })
    expect(finalizeNewWalletSpy).not.toHaveBeenCalledWith(filename)
    expect(sendRPCSpy).toHaveBeenCalledWith("create_wallet", { filename, password, language })
  })
  it("should handle exceptions gracefully", async () => {
    // ARRANGE
    const sendRPCSpy = jest.spyOn(walletRPC, "sendRPC").mockImplementation(() => {
      throw new Error("something borked!")
    })
    walletRPC.auth = ["", "", salt]
    const filename = "foo"
    const password = "123456"
    const language = "English"
    const sendGatewaySpy = jest.spyOn(walletRPC, "sendGateway")
    walletRPC.finalizeNewWallet = jest.fn(value => Promise.resolve())
    const finalizeNewWalletSpy = jest.spyOn(walletRPC, "finalizeNewWallet")
    // ACT
    await walletRPC.createWallet(filename, password, language)
    // ASSERT
    expect(sendGatewaySpy).toHaveBeenNthCalledWith(1, "reset_wallet_error")
    expect(sendGatewaySpy).toHaveBeenNthCalledWith(2, "set_wallet_error", {
      status: {
        code: 500,
        message: "something borked!"
      }
    })
    expect(finalizeNewWalletSpy).not.toHaveBeenCalledWith(filename)
    expect(sendRPCSpy).toHaveBeenCalledWith("create_wallet", { filename, password, language })
  })
})

describe("restoreWallet", () => {

})

describe("restoreViewWallet", () => {

})

describe("importWallet", () => {

})

describe("finalizeNewWallet", () => {

})

describe("OpenWallet", () => {

})

describe("relayStak", () => {

})

describe("stake", () => {

})

describe("registerSnode", () => {

})

describe("unlockStake", () => {

})

describe("relaySweepAll", () => {

})

describe("cancelTransaction", () => {

})

describe("sweepAll", () => {

})

describe("relayTransfer", () => {

})

describe("transfer", () => {

})

describe("getPrivateKeys", () => {

})

describe("getAddressList", () => {

})

describe("getPools", () => {

})

describe("getStake", () => {

})

describe("getTransactions", () => {
  it("should return hydrated transactions array when invoked", async () => {
    // ARRANGE
    walletRPC.checkHeight = jest.fn(() => Promise.resolve(true))
    const height = 1000
    const expected = {
      transactions: {
        tx_list: [
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            amount: 20000,
            confirmations: 5066,
            destinations: [
              {
                address: "Tw1AXwU3z9kjMc5z21PaZ6HfQAJXmJbpWC6rdQtW7jw3Agp4t47UokKKTVkcXUTjYo4wtfu9nY87v1uJhKEpEpJv2DdeqLpwj",
                amount: 20000
              }
            ],
            double_spend_seen: false,
            fee: 60,
            height: 972850,
            locked: false,
            note: "",
            payment_id: "",
            subaddr_index: {
              major: 0,
              minor: 0
            },
            subaddr_indices: [
              {
                major: 0,
                minor: 0
              }
            ],
            suggested_confirmations_threshold: 1,
            timestamp: 1669929958,
            txid: "77124dd799b591e9575a33be59615f3b35179177dced1aca25cdc4f803f023cc",
            type: "out",
            unlock_time: 0
          },
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            amount: 0,
            confirmations: 5656,
            double_spend_seen: false,
            fee: 120,
            height: 972260,
            locked: false,
            note: "",
            payment_id: "",
            subaddr_index: {
              major: 0,
              minor: 0
            },
            subaddr_indices: [
              {
                major: 0,
                minor: 0
              }
            ],
            timestamp: 1669859685,
            txid: "62346aaeb5b800bade6d77575d7394c0d8293cb8b65a4b6d7278099d7f63a77b",
            type: "out",
            unlock_time: 0
          },
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            amount: 100000,
            confirmations: 5735,
            double_spend_seen: false,
            fee: 60,
            height: 972181,
            locked: false,
            note: "",
            payment_id: "",
            subaddr_index: {
              major: 0,
              minor: 0
            },
            subaddr_indices: [
              {
                major: 0,
                minor: 0
              }
            ],
            suggested_confirmations_threshold: 1,
            timestamp: 1669849369,
            txid: "85deb31f7f0420be5880f8fc87cedaf7765e6e582298a8819edaa77a3b3af3a0",
            type: "in",
            unlock_time: 0
          },
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            amount: 20000,
            confirmations: 22876,
            double_spend_seen: false,
            fee: 60,
            height: 955040,
            locked: false,
            note: "",
            payment_id: "",
            subaddr_index: {
              major: 0,
              minor: 0
            },
            subaddr_indices: [
              {
                major: 0,
                minor: 0
              }
            ],
            suggested_confirmations_threshold: 1,
            timestamp: 1667775540,
            txid: "46f6658e21b98ab1ce7377cd2bdb3cbd7b73b520a84b0b6e1ab9a63a4f99b3e9",
            type: "in",
            unlock_time: 0
          },
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            amount: 10000,
            confirmations: 39406,
            double_spend_seen: false,
            fee: 60,
            height: 938510,
            locked: false,
            note: "",
            payment_id: "",
            subaddr_index: {
              major: 0,
              minor: 0
            },
            subaddr_indices: [
              {
                major: 0,
                minor: 0
              }
            ],
            suggested_confirmations_threshold: 1,
            timestamp: 1665780950,
            txid: "795af73e6bcc1ca1a0420220f5468d1bbbe32587bc9837a61d581069d6bb0cef",
            type: "in",
            unlock_time: 0
          },
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            amount: 10000,
            confirmations: 39420,
            double_spend_seen: false,
            fee: 60,
            height: 938496,
            locked: false,
            note: "",
            payment_id: "",
            subaddr_index: {
              major: 0,
              minor: 0
            },
            subaddr_indices: [
              {
                major: 0,
                minor: 0
              }
            ],
            suggested_confirmations_threshold: 1,
            timestamp: 1665779414,
            txid: "d0d1b6d5d9c12182821abee10bbb3d39134c728bcf40fa368f7bb7d98955bc2b",
            type: "in",
            unlock_time: 0
          }
        ]
      }
    }
    walletRPC.sendRPC = jest.fn(() => {
      return Promise.resolve(get_transfers)
    })
    // ACT
    const actual = await walletRPC.getTransactions(height)

    // ASSERT
    expect(actual).toEqual(expected)
  })
})

describe("getAddressBook", () => {
  it("should return wallet data when successful", async () => {
    // ARRANGE
    const expected = {
      address_list: {
        address_book: [
          {
            address: "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
            description: "",
            index: 0,
            starred: false,
            name: "test b wallet"
          }
        ],
        address_book_starred: [
          {
            address: "Tsz58Nfvb4GbMvtZfGVQb5hyyZeU1NgkaHj9FUpbWhDzcd5hW4E2rdoS73sMQgDA4UiSEAfArNVBhHYQHgd61doU5TQuPs8kkc",
            description: "My TO account",
            index: 1,
            starred: true,
            name: "TradeOgre"
          }
        ]
      }
    }
    walletRPC.sendRPC = jest.fn((value) => {
      return Promise.resolve(get_address_book)
    })

    // ACT
    const actual = await walletRPC.getAddressBook()

    // ASSERT
    expect(actual).toEqual(expected)
  })
  it("should return default empty wallet object when sendRPC returns no results", async () => {
    // ARRANGE
    const expected = {
      address_list: {
        address_book: [],
        address_book_starred: []
      }
    }
    walletRPC.sendRPC = jest.fn((value) => {
      return Promise.resolve({
        id: 10,
        jsonrpc: "2.0",
        result: {}
      })
    })

    // ACT
    const actual = await walletRPC.getAddressBook()

    // ASSERT
    expect(actual).toEqual(expected)
  })
  it("should return default empty wallet object when sendRPC returns no response", async () => {
    // ARRANGE
    const expected = {
      address_list: {
        address_book: [],
        address_book_starred: []
      }
    }
    walletRPC.sendRPC = jest.fn((value) => {
      return Promise.resolve({})
    })

    // ACT
    const actual = await walletRPC.getAddressBook()

    // ASSERT
    expect(actual).toEqual(expected)
  })
})

describe("deleteAddressBook", () => {

})

describe("addAddressBook", () => {

})

describe("saveTxNotes", () => {

})

describe("exportKeyImages", () => {

})

describe("importKeyImages", () => {

})

describe("listWallets", () => {

})

describe("changeWalletPassword", () => {

})

describe("deleteWallet", () => {

})

describe("saveWallet", () => {

})

describe("closeWallet", () => {

})

describe("parseWalletResponse", () => {

})
