// Jest only, run before every suite once the test environment is ready
// (web/jest.config.mjs `setupFilesAfterEnv`). jest.setup.cjs runs earlier, as a
// `setupFiles` entry, too early to load Testing Library.
//
// A findBy* or waitFor gives up after 1000 ms by default. A full run with a
// worker on every core can take longer than that to draw a dialog, on a machine
// whose antivirus scans every file most of all, so the whole suite waits up to
// 5 s (docs/TESTING.md, "How long a web test waits"). One that succeeds still
// returns at once, so a passing run takes no longer.
const { configure } = require("@testing-library/react");

configure({ asyncUtilTimeout: 5000 });
