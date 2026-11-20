import { escapeRegExp } from "./escapeRegExp";

describe("escapeRegExp", () => {
  it.each([
    "var(--spacingVerticalS)",
    "a **bold** label:",
    "a.b*c+d?e^f$g{h}i(j)k|l[m]n\\o",
    "",
    "plain",
  ])("makes %j match only itself", (text) => {
    const re = new RegExp(`^${escapeRegExp(text)}$`);
    expect(re.test(text)).toBe(true);
    expect(re.test(`${text}x`)).toBe(false);
  });
});
