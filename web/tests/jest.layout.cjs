// Jest only, run before every suite (web/jest.config.mjs `setupFiles`).
//
// jsdom lays nothing out: every element's offsetParent is null and <body>
// measures 0 x 0. Tabster, the focus layer under Fluent's dialogs and menus,
// reads exactly those two facts to decide what can take focus, so in jsdom it
// finds nothing focusable anywhere. A dialog that opens then focuses its own
// surface instead of its first control, Tabster never makes that dialog the
// active modal (it activates a modal when focus lands INSIDE it, not on it),
// and the next pass that hides what lies outside the active modal marks the
// open dialog aria-hidden -- for good. A test that opens a second dialog
// within 250 ms of closing the first meets that pass.
//
// So the test window answers the two questions as a browser would: an element
// has an offsetParent unless it, or an ancestor, is display:none, it is
// position:fixed, or it is not in the document, and <body> has a size. Nothing else about layout is faked.
if (typeof HTMLElement !== "undefined") {
  Object.defineProperty(HTMLElement.prototype, "offsetParent", {
    configurable: true,
    get() {
      if (!this.isConnected || this === this.ownerDocument.body) return null;
      const style = (e) => e.ownerDocument.defaultView.getComputedStyle(e);
      for (let e = this; e; e = e.parentElement) {
        if (style(e).display === "none") return null;
      }
      // A browser gives a position:fixed element no offsetParent either.
      return style(this).position === "fixed" ? null : this.parentElement;
    },
  });

  const VIEWPORT = { width: 1024, height: 768 };
  HTMLBodyElement.prototype.getBoundingClientRect = function () {
    const { width, height } = VIEWPORT;
    const rect = { x: 0, y: 0, top: 0, left: 0, width, height, right: width, bottom: height };
    return { ...rect, toJSON: () => rect };
  };
}
