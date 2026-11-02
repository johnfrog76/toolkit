/**
 * Jest config for the web UI's logic tests.
 *
 * Scoped deliberately narrow: the shell's module registry (which modules
 * contribute routes, nav and cards for a given feature set) and the small
 * shared primitives everything else is built on (persisted state, pagination).
 * Browser-level verification stays with Playwright -- this runner exists so
 * the rules that decide what the app even mounts cannot drift, and a headless
 * assertion is the cheapest way to keep them honest.
 *
 * jsdom (not node) because the registry test renders through
 * @testing-library/react. ts-jest compiles the TSX/TS sources directly, so
 * there's no build step between source and test.
 */
export default {
  preset: "ts-jest",
  testEnvironment: "jsdom",
  testMatch: ["<rootDir>/src/**/*.test.ts", "<rootDir>/src/**/*.test.tsx"],
  // TextEncoder/TextDecoder for jsdom, which React Router 8 needs at import.
  setupFiles: ["<rootDir>/tests/jest.setup.cjs"],
  // Testing Library's wait for an element, raised for the whole suite.
  setupFilesAfterEnv: ["<rootDir>/tests/jest.afterEnv.cjs"],
  // The @consts alias, third of three resolvers (vite.config.ts and tsconfig's
  // `paths` are the others). The contract file is real JSON on disk and jest
  // requires it directly -- nothing is stubbed, so a test reads exactly what
  // the bundle will.
  moduleNameMapper: {
    "^@consts$": "<rootDir>/../consts.json",
    "^@workflows$": "<rootDir>/../Config/settings-workflows.json",
    // React Router 8's one file that reads import.meta, swapped for a stub
    // (tests/routeModules.jest.cjs says why). Only react-router imports it.
    "^\\./routeModules\\.js$":"<rootDir>/tests/routeModules.jest.cjs",
  },
  // The markdown stack (react-markdown, remark-*, rehype-*, unified and their
  // unist/mdast/hast/micromark dependencies) ships ESM only. Registry tests
  // never load it -- they mock every module -- but markdownPlugins.test.tsx
  // renders the REAL pipeline, so exactly these packages are passed
  // through ts-jest (allowJs) instead of being skipped as node_modules.
  // React Router 8 ships ESM only too, with its two dependencies, and nearly
  // every page imports it, so it is passed through the same way.
  transformIgnorePatterns: [
    "/node_modules/(?!(?:" +
      [
        "react-markdown",
        "remark-[^/]+",
        "rehype-[^/]+",
        "unified",
        "unist-[^/]+",
        "vfile[^/]*",
        "mdast-[^/]+",
        "micromark[^/]*",
        "hast[^/]*",
        "decode-named-character-reference",
        "character-entities[^/]*",
        "bail",
        "trough",
        "is-plain-obj",
        "property-information",
        "space-separated-tokens",
        "comma-separated-tokens",
        "html-url-attributes",
        "html-void-elements",
        "devlop",
        "ccount",
        "markdown-table",
        "trim-lines",
        "zwitch",
        "longest-streak",
        "parse5",
        "web-namespaces",
        "stringify-entities",
        "estree-util-[^/]+",
        "inline-style-parser",
        "style-to-[^/]+",
        "escape-string-regexp",
        "react-router",
        "@remix-run/route-pattern",
        "cookie-es",
      ].join("|") +
      ")/)",
  ],
  transform: {
    "^.+\\.(?:tsx?|m?js)$": [
      "ts-jest",
      {
        tsconfig: {
          jsx: "react-jsx",
          esModuleInterop: true,
          allowJs: true,
          // The app targets bundler resolution; tests just need it to compile.
          module: "commonjs",
          moduleResolution: "node",
          // TypeScript 6 deprecates the node10 resolver named above and, with
          // no tsconfig file behind this object, cannot work out a common
          // source directory. The first is silenced until 7 removes it
          // (commonjs has no other resolver); the second is set.
          ignoreDeprecations: "6.0",
          rootDir: "..",
        },
      },
    ],
  },
};
