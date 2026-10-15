/**
 * The rule behind "off means no bytes":
 * an opt-in module's descriptor -- its index.tsx, the one file
 * the registry imports statically -- imports NO component of its own. Pages,
 * cards and header items come through `lazyPart` and a dynamic import, so they
 * are chunks the browser fetches when first drawn. A static `import { Page }
 * from "./Page"` in a descriptor would quietly put the module back in the first
 * load, and nothing else would notice -- so this reads the source and says so.
 *
 * What a descriptor MAY import statically from its own folder: a paths file
 * (route strings) and nothing else. The shell, react and react-router are fine:
 * they are in the first load anyway.
 *
 * The Studio is on this list although it has no flag: it is core from day one
 * (D-S13), and lazy is about bytes, not about
 * being optional -- its pages still arrive only when someone opens the tab.
 */
import fs from "node:fs";
import path from "node:path";

const LAZY = ["growth", "communication", "organize", "studio", "solitaireAgile", "lounge", "deck"];
const OWN_FOLDER_ALLOWED = new Set(["paths"]);

function staticOwnImports(source: string): string[] {
  // `import ... from "./x"` and `export ... from "./x"`, not `import type`
  // and not `import("./x")`.
  const found: string[] = [];
  const re = /^(?:import|export)\s+(?!type\b)[^;]*?\bfrom\s+"\.\/([^"]+)"/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source))) found.push(m[1]);
  return found;
}

describe("a lazily loaded module's descriptor imports no component statically", () => {
  for (const id of LAZY) {
    it(`${id}/index.tsx`, () => {
      const file = path.join(__dirname, "..", "modules", id, "index.tsx");
      const source = fs.readFileSync(file, "utf8");
      const offenders = staticOwnImports(source).filter((s) => !OWN_FOLDER_ALLOWED.has(s));
      expect(offenders).toEqual([]);
      // And it really does defer something: at least one dynamic import.
      expect(source).toMatch(/import\("\.\//);
    });
  }

  it("the rule reads what it thinks it reads", () => {
    expect(
      staticOwnImports(
        'import { A } from "./A";\nimport type { B } from "./B";\nconst C = lazy(() => import("./C"));\nexport { D } from "./D";\nimport { ROUTES } from "./paths";',
      ),
    ).toEqual(["A", "D", "paths"]);
  });
});
