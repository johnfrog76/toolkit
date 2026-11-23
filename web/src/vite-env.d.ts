/// <reference types="vite/client" />

// Vite's client types: `import.meta.glob`, `import.meta.env`, asset imports.
// The first file here to need them is modules/deck/bakedVoices.ts, which finds a
// deck's baked voice files with a glob so there is no manifest to fall out of
// step with the files on disk.

// The packaged CHANGELOG.md as text: the `@changelog` alias (vite.config.ts,
// jest.config.mjs) resolves it with `?raw`; shell/changelog.ts is its one reader.
declare module "@changelog" {
  const text: string;
  export default text;
}
