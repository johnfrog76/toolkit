/**
 * The skin owns the palette everywhere (D-L22;
 * The owner's rule: "the skin owns all of the palette"). The first
 * defect of the rule: the Face picker -- and every chart, Test Health and the
 * Log -- read useCurrentTheme, the person's CHOSEN theme, so under a worn
 * skin they kept that theme's colours. The rule as a test: useCurrentTheme
 * is the store's own hook, called by the ThemePicker, the avatar menu and
 * useWornTheme itself, and by nothing else in the tree.
 */
import * as fs from "fs";
import * as path from "path";

const SRC = path.resolve(__dirname, "..");
const ALLOWED = new Set([
  "shell/ThemePicker.tsx",
  "shell/AvatarMenu.tsx",
  "hooks/useWornTheme.ts",
  "hooks/useCurrentTheme.ts",
]);

function walk(dir: string, out: string[] = []): string[] {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) walk(full, out);
    else if (/\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name)) out.push(full);
  }
  return out;
}

it("only the picker, the avatar menu and useWornTheme call useCurrentTheme", () => {
  const callers = walk(SRC)
    .filter((f) => /\buseCurrentTheme\(/.test(fs.readFileSync(f, "utf8")))
    .map((f) => path.relative(SRC, f).split(path.sep).join("/"))
    .sort();
  expect(callers.filter((c) => !ALLOWED.has(c))).toEqual([]);
  expect(callers).toContain("hooks/useWornTheme.ts");
});
