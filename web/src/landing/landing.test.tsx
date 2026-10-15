import fs from "node:fs";
import path from "node:path";
import { render, screen, within } from "@testing-library/react";
import { Landing, PRODUCT_NAME } from "./Landing";
import { COPY, fileUrl } from "./copy";
import { PEOPLE } from "./people";
import { BUTLER_NAME } from "./Butler";
import { FACES_NAME } from "./Faces";
import { FACES } from "../shared/faces";

// The landing page's words are its own (copy.ts), written for a visitor and
// kept apart from the README on purpose. This suite holds the page to that
// file: every piece drawn where the design puts it, every document it links a
// file that exists, and the people one per way of working.

const PACKAGE_ROOT = path.resolve(__dirname, "..", "..", "..");
const visible = (el: HTMLElement) => (el.textContent ?? "").replace(/\s+/g, " ").trim();

describe("the words", () => {
  test("every document the footer links is a file in the repository", () => {
    for (const doc of COPY.documents) {
      expect(fs.existsSync(path.join(PACKAGE_ROOT, doc.path))).toBe(true);
    }
  });

  test("the repository is a GitHub address, and the page links files under it", () => {
    expect(COPY.repository).toMatch(/^https:\/\/github\.com\/[^/]+\/[^/]+$/);
    expect(fileUrl(COPY.repository, "LICENSE")).toBe(`${COPY.repository}/blob/HEAD/LICENSE`);
  });

  test("the quick start is five lines, each a command with its comment", () => {
    expect(COPY.quickStart).toHaveLength(5);
    for (const line of COPY.quickStart) expect(line).toMatch(/^\S.*\s#\s\S/);
  });

  test("the people: one per way of working, each a member of the cast, each with a line", () => {
    expect(PEOPLE.map((p) => p.way)).toEqual(COPY.ways.map((w) => w.id));
    expect(new Set(PEOPLE.map((p) => p.castId)).size).toBe(3);
    for (const p of PEOPLE) expect(p.line.trim().length).toBeGreaterThan(0);
  });
});

describe("the page draws exactly those words", () => {
  test("the banner: the wordmark named for a screen reader, the offering, three bullets, the many faces with their line", () => {
    render(<Landing />);
    const banner = screen.getByRole("banner");
    const mark = within(banner).getByRole("img", { name: PRODUCT_NAME });
    expect(mark.tagName).toBe("svg");
    expect(screen.getByRole("heading", { level: 1 }).contains(mark)).toBe(true);
    expect(visible(banner)).toContain(COPY.offering);
    const bullets = Array.from(banner.querySelectorAll(".lp-bullets li"));
    expect(bullets.map((b) => b.textContent)).toEqual([...COPY.bullets]);
    const faces = within(banner).getByRole("list", { name: FACES_NAME });
    expect(faces.querySelectorAll("li")).toHaveLength(FACES.length);
    expect(visible(banner)).toContain(COPY.facesLine);
    expect(within(banner).queryByRole("button")).toBeNull();
  });

  test("the call to action plays the commercial, in the deck's name, and gets focus back", () => {
    const onPlay = jest.fn();
    render(<Landing onPlay={onPlay} playLabel="Play the deck" focusCta />);
    const button = screen.getByRole("button", { name: /Play the deck/ });
    expect(document.activeElement).toBe(button);
    button.click();
    expect(onPlay).toHaveBeenCalledTimes(1);
  });

  test("the three ways under the eyebrow, each with its heading, its copy and one of the cast delivering their line", () => {
    render(<Landing />);
    const ways = screen.getByRole("region", { name: COPY.eyebrow });
    const articles = within(ways).getAllByRole("article");
    expect(articles).toHaveLength(3);
    articles.forEach((article, i) => {
      const way = COPY.ways[i];
      expect(within(article).getByRole("heading", { level: 3 }).textContent).toBe(way.heading);
      expect(visible(article)).toContain(way.text);
      const who = PEOPLE.find((p) => p.way === way.id)!;
      expect(within(article).getByText(who.line)).toBeTruthy();
    });
  });

  test("quick start: the five lines, character for character, with the butler beside the shell", () => {
    render(<Landing />);
    const quick = screen.getByRole("region", { name: COPY.quickStartHeading });
    expect(within(quick).getByRole("heading", { level: 2 }).textContent).toBe(
      COPY.quickStartHeading,
    );
    expect(quick.querySelector("code")?.textContent).toBe(COPY.quickStart.join("\n"));
    expect(within(quick).getByRole("img", { name: BUTLER_NAME })).toBeTruthy();
  });

  test("the footer: the repository, every document in order, and the disclosure", () => {
    render(<Landing />);
    const footer = screen.getByRole("contentinfo");
    const hrefs = within(footer)
      .getAllByRole("link")
      .map((a) => a.getAttribute("href"));
    expect(hrefs).toEqual([
      COPY.repository,
      ...COPY.documents.map((d) => fileUrl(COPY.repository, d.path)),
    ]);
    expect(visible(footer)).toContain(COPY.narration);
  });
});
