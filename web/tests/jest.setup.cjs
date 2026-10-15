// Jest only, run before every suite (web/jest.config.mjs `setupFiles`).
//
// jsdom gives a test window no TextEncoder or TextDecoder, and React Router 8
// builds one when its index loads (its cookie signing), so every suite that
// imports react-router failed before its first line. The browser has both,
// and so does Node: hand the window Node's.
const { TextDecoder, TextEncoder } = require("node:util");

if (typeof globalThis.TextEncoder === "undefined") globalThis.TextEncoder = TextEncoder;
if (typeof globalThis.TextDecoder === "undefined") globalThis.TextDecoder = TextDecoder;
