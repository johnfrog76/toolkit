// Jest only: stands in for react-router's lib/dom/ssr/routeModules.js, which
// web/jest.config.mjs maps here.
//
// React Router 8 ships ESM only, and jest.config.mjs passes it through ts-jest
// to CommonJS. That works for every file but this one: it reads
// `import.meta.hot`, which has no CommonJS form, so the transformed file still
// fails to load and takes every suite that imports react-router with it. The
// function it exports loads a framework-mode route module by URL; this app
// is a plain SPA (BrowserRouter, and MemoryRouter in the suites) and never
// reaches it. If it ever does, the stub says so instead of loading nothing.
async function loadRouteModule(route) {
  throw new Error(`react-router route modules are not loaded under jest (${route && route.id})`);
}

module.exports = { loadRouteModule };
