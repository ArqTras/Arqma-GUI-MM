/** @type {import('jest').Config} */
export default {
//   preset: "@quasar/quasar-app-extension-testing-unit-jest",
  // collectCoverage: true,
  // coverageThreshold: {
  //   global: {
  //      branches: 50,
  //      functions: 50,
  //      lines: 50,
  //      statements: 50
  //   },
  // },
  testEnvironment: "jest-environment-node",
  setupFiles: ["dotenv/config"],
  transform: {
    ".*\\.js$": "babel-jest"
  }
}
