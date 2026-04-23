import { describe, expect, it, beforeEach } from "@jest/globals"
import { Backend } from "./backend"

jest.mock("electron")
jest.mock("./logger", () => ({
  ...jest.requireActual("./logger"),
  info: jest.fn(),
  error: jest.fn()
}))

describe("save_config_init", () => {
  it("DON'T FORGET ME!!", () => {
    expect(1).toBe(1)
  })
})
