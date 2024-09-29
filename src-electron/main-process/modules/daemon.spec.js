import { describe, expect, it, beforeEach } from "@jest/globals"
import { Daemon } from "./daemon"

jest.mock("electron")
jest.mock("./logger", () => ({
  ...jest.requireActual("./logger"),
  info: jest.fn(),
  error: jest.fn()
}))

describe("checkVersion", () => {
  it("DON'T FORGET ME!!", () => {
    expect(1).toBe(1)
  })
})

describe("checkRemote", () => {

})

describe("register_sn", () => {

})

describe("handle", () => {

})

describe("banPeer", () => {

})

describe("timestampToHeight", () => {

})

describe("parseDaemonResponse", () => {

})
