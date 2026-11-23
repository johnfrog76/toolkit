// The @changelog alias under jest: the package's real CHANGELOG.md, read as
// text and exported as the module's default, the way Vite's `?raw` hands it to
// the bundle. Nothing is stubbed -- a test reads exactly what the build packs.
const fs = require("node:fs");
const path = require("node:path");

module.exports = {
  __esModule: true,
  default: fs.readFileSync(path.join(__dirname, "..", "..", "CHANGELOG.md"), "utf8"),
};
