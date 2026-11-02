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

  it("the rule reads what it thinks it reads, across folders", () => {
    expect(
      staticImportsOf(
        'import { A } from "../studio/A";\nimport type { B } from "../studio/B";\nconst C = lazyPart(() => import("../studio/C"));\nimport { n } from "../studio/paths";',
      ),
    ).toEqual(["../studio/A", "../studio/paths"]);
  });
});

/**
 * The other half of the same rule: a descriptor importing nothing is not
 * enough if a file that DOES load with the app imports a module's component or
 * API statically. The Design tab (ado, always mounted) once imported the
 * Studio's MoveDesignDialog, which pulled the dialog and api.studio.ts into the
 * first load. A file outside a lazy module may import from it only its paths
 * file, or types (erased at build); anything else comes through `lazyPart`.
 */
function staticImportsOf(source: string): string[] {
  const found: string[] = [];
  const re = /^(?:import|export)\s+(?!type\b)[^;]*?\bfrom\s+"([^"]+)"/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source))) found.push(m[1]);
  return found;
}

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return sourceFiles(full);
    return /\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name) ? [full] : [];
  });
}

// The Studio is core: every other module is reached from the registry and, for
// growth and the deck, from the landing page's own entry or a sibling's stage,
// by design. The Studio's code is reached only through its own descriptor.
const CHECKED_ACROSS_FOLDERS = ["studio"];

describe("nothing that loads with the app imports a lazy module's code statically", () => {
  const src = path.join(__dirname, "..");
  const files = sourceFiles(src);
  for (const id of CHECKED_ACROSS_FOLDERS) {
    it(`${id}`, () => {
      const offenders: string[] = [];
      for (const file of files) {
        const rel = path.relative(src, file);
        if (rel.startsWith(path.join("modules", id) + path.sep)) continue;
        for (const spec of staticImportsOf(fs.readFileSync(file, "utf8"))) {
          const target = path.normalize(path.join(path.dirname(file), spec));
          const inside = path.relative(path.join(src, "modules", id), target);
          if (
            spec.startsWith(".") &&
            !inside.startsWith("..") &&
            inside !== "" &&
            !OWN_FOLDER_ALLOWED.has(inside)
          ) {
            offenders.push(`${rel} imports ${spec}`);
          }
        }
      }
      expect(offenders).toEqual([]);
    });
  }
});
