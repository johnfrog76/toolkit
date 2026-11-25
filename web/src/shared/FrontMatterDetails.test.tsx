import { render, screen } from "@testing-library/react";
import { FrontMatterDetails, leftoverFrontMatter, unquoted } from "./FrontMatterDetails";
import { frontMatterOf } from "./prepareMarkdown";

describe("leftoverFrontMatter", () => {
  it("drops the keys the header draws, empty values and one pair of quotes", () => {
    const { frontMatter } = frontMatterOf(
      '---\ndescription: "Does a thing"\nagent: "agent"\ntools:\nid: abc\n---\n\nBody\n',
    );
    expect(leftoverFrontMatter(frontMatter, ["description"])).toEqual([
      ["agent", "agent"],
      ["id", "abc"],
    ]);
  });
  it("unquotes only a matched pair", () => {
    expect(unquoted('"a b"')).toBe("a b");
    expect(unquoted("'a'")).toBe("a");
    expect(unquoted('"a')).toBe('"a');
  });
});

describe("frontMatterOf", () => {
  it("lifts the block off and leaves the prose", () => {
    const r = frontMatterOf("---\nid: 1\n---\n\n# Title\n\nText\n");
    expect(r.frontMatter).toEqual([["id", "1"]]);
    expect(r.body).toBe("# Title\n\nText\n");
  });
  it("leaves a file that opens with a rule and prose whole", () => {
    const text = "---\nnot a key value\n---\n\nText\n";
    expect(frontMatterOf(text).body).toBe(text);
  });
});

describe("FrontMatterDetails", () => {
  it("draws a collapsed row, or nothing at all", () => {
    const { rerender } = render(<FrontMatterDetails pairs={[["agent", "agent"]]} />);
    expect(screen.getByTestId("front-matter-details").hasAttribute("open")).toBe(false);
    rerender(<FrontMatterDetails pairs={[]} />);
    expect(screen.queryByTestId("front-matter-details")).toBeNull();
  });
});
