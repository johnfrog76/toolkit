import { render, screen } from "@testing-library/react";
import { readFileSync } from "fs";
import { join } from "path";
import {
  FrontMatterDetails,
  frontMatterValue,
  leftoverFrontMatter,
  unquoted,
} from "./FrontMatterDetails";
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

describe("a list and an escaped quote read as a person writes them", () => {
  it("reads the real tools line of agentic/new-bug.prompt.md as a plain list", () => {
    const text = readFileSync(join(__dirname, "../../../agentic/new-bug.prompt.md"), "utf8");
    const { frontMatter } = frontMatterOf(text);
    const tools = leftoverFrontMatter(frontMatter, ["description"]).find(([k]) => k === "tools");
    expect(tools?.[1]).toBe("read_file, list_dir, run_in_terminal, grep_search");
  });
  it("reads a flow sequence of bare and quoted items, and a review's orgs", () => {
    expect(unquoted('[a, "b"]')).toBe("a, b");
    expect(unquoted("[test]")).toBe("test");
    expect(unquoted("[]")).toBe("");
    expect(unquoted('["a, b", c]')).toBe("a, b, c");
  });
  it("unescapes a quote inside a quoted value", () => {
    expect(unquoted('"He said \\"hi\\""')).toBe('He said "hi"');
    expect(unquoted("'it''s'")).toBe("it's");
  });
  it("finds a key without regard to case", () => {
    expect(frontMatterValue([["Description", '"Upper"']], "description")).toBe("Upper");
    expect(frontMatterValue([], "description")).toBe("");
  });
  it("draws two rows with one key without a duplicate-key warning", () => {
    const warn = jest.spyOn(console, "error").mockImplementation(() => undefined);
    render(
      <FrontMatterDetails
        pairs={[
          ["agent", "a"],
          ["agent", "b"],
        ]}
      />,
    );
    expect(warn).not.toHaveBeenCalled();
    warn.mockRestore();
  });
});
