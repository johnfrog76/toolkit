// Named slots: places on one module's page that another module fills, without
// either importing the other (registry.ts, `slotCards`). The name is the whole
// contract between the two sides, so it is written once, here -- in a file that
// imports nothing, because the registry imports every module and a module that
// read the name from the registry would read it before the registry had run.

/** Home's slot above its tabs: rendered by the ADO module's Home, filled by the
 *  deck module's first-run banner. */
export const HOME_BANNER_SLOT = "home-banner";
