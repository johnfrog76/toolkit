/** How much room a list panel's card list has, measured. The page size is
 *  worked out from this at runtime, so whatever sits above the list -- a
 *  status line, a search's results, a second row of chips, a header that
 *  wrapped -- takes its real height and nothing under it is cut off. */

/** The foot row's height, in px, kept free while the panel draws no foot: a
 *  pager appears when there is a second page, and must not change the page. */
export const LIST_FOOT_ROW_PX = 32;

const px = (value: string): number => {
  const n = parseFloat(value);
  return Number.isFinite(n) ? n : 0;
};

/**
 * The height, in px, the list's items may take: from the list's top, less its
 * own padding, down to where the frame's foot begins. `null` when there is
 * nothing to measure against -- the panel has no fixed height here (a narrow
 * page, where it grows with its items), or there is no layout at all.
 *
 * `root` is the panel, `frame` the PanelFrame inside it, `frameBody` the
 * frame's body element, `list` the card list. `hasFoot` says whether the frame
 * is drawing its foot row now.
 */
export function measureListRoom(
  root: HTMLElement,
  frame: HTMLElement,
  frameBody: HTMLElement,
  list: HTMLElement,
  hasFoot: boolean,
): number | null {
  const cap = getComputedStyle(root).maxHeight;
  if (!cap || cap === "none") return null;
  const rootBox = root.getBoundingClientRect();
  if (rootBox.height === 0) return null;
  const frameStyle = getComputedStyle(frame);
  const gap = px(frameStyle.rowGap);
  // What follows the body in the frame: the foot row, and a line under it.
  let after = 0;
  let next = frameBody.nextElementSibling;
  while (next) {
    after += next.getBoundingClientRect().height + gap;
    next = next.nextElementSibling;
  }
  if (!hasFoot) after += LIST_FOOT_ROW_PX + gap;
  const bottom = rootBox.bottom - px(frameStyle.paddingBottom) - px(frameStyle.borderBottomWidth);
  const top = list.getBoundingClientRect().top + px(getComputedStyle(list).paddingTop);
  return bottom - after - top;
}
