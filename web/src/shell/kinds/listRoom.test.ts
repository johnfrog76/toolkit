import { LIST_FOOT_ROW_PX, measureListRoom } from "./listRoom";

// jsdom lays nothing out, so each element is given the box a browser would
// give it, and the frame its padding and gap. What is under test is the sum:
// from the list's top, less its own padding, down to where the foot begins.
interface Box {
  top: number;
  height: number;
}

function el(box: Box, style: Partial<CSSStyleDeclaration> = {}): HTMLElement {
  const node = document.createElement("div");
  node.getBoundingClientRect = () =>
    ({ top: box.top, bottom: box.top + box.height, height: box.height }) as DOMRect;
  styles.set(node, style);
  return node;
}
const styles = new Map<Element, Partial<CSSStyleDeclaration>>();

beforeEach(() => {
  styles.clear();
  jest
    .spyOn(window, "getComputedStyle")
    .mockImplementation((node: Element) => (styles.get(node) ?? {}) as CSSStyleDeclaration);
});
afterEach(() => jest.restoreAllMocks());

/** A 592 px panel at the top of the page: 12 px padding, 12 px between parts. */
function panel(opts: { capped?: boolean; listTop: number; after: number[] }) {
  const root = el({ top: 0, height: 592 }, { maxHeight: opts.capped === false ? "none" : "592px" });
  const frame = el(
    { top: 0, height: 592 },
    { rowGap: "12px", paddingBottom: "12px", borderBottomWidth: "0px" },
  );
  const frameBody = el({ top: 49, height: 400 });
  const list = el({ top: opts.listTop, height: 300 }, { paddingTop: "4px" });
  root.append(frame);
  frame.append(el({ top: 12, height: 24 }), el({ top: 48, height: 1 }), frameBody);
  for (const height of opts.after) frame.append(el({ top: 0, height }));
  frameBody.append(list);
  return { root, frame, frameBody, list };
}

describe("measureListRoom", () => {
  it("is from the list's top, under its padding, down to the foot row", () => {
    const p = panel({ listTop: 49, after: [32] });
    // 592 - 12 padding - (32 foot + 12 gap) - (49 + 4) = 483.
    expect(measureListRoom(p.root, p.frame, p.frameBody, p.list, true)).toBe(483);
  });

  it("whatever sits above the list takes its real height", () => {
    // A status line and two chip rows push the list down 120 px.
    const p = panel({ listTop: 169, after: [32] });
    expect(measureListRoom(p.root, p.frame, p.frameBody, p.list, true)).toBe(363);
  });

  it("a line under the foot row takes its height and its gap", () => {
    const p = panel({ listTop: 49, after: [32, 20] });
    expect(measureListRoom(p.root, p.frame, p.frameBody, p.list, true)).toBe(483 - 32);
  });

  it("with no foot drawn, the foot row's room is kept free, so a pager appearing changes nothing", () => {
    const drawn = panel({ listTop: 49, after: [LIST_FOOT_ROW_PX] });
    const none = panel({ listTop: 49, after: [] });
    expect(measureListRoom(none.root, none.frame, none.frameBody, none.list, false)).toBe(
      measureListRoom(drawn.root, drawn.frame, drawn.frameBody, drawn.list, true),
    );
  });

  it("is nothing where the panel has no fixed height: a narrow page, where it grows with its items", () => {
    const p = panel({ capped: false, listTop: 49, after: [32] });
    expect(measureListRoom(p.root, p.frame, p.frameBody, p.list, true)).toBeNull();
  });

  it("is nothing where there is no layout", () => {
    const p = panel({ listTop: 49, after: [32] });
    p.root.getBoundingClientRect = () => ({ top: 0, bottom: 0, height: 0 }) as DOMRect;
    expect(measureListRoom(p.root, p.frame, p.frameBody, p.list, true)).toBeNull();
  });
});
