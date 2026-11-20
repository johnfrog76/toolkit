/**
 * How a card writes a count: exact, with the reader's locale grouping the digits (12,661 in en-US,
 * 12.661 in de-DE). Exact on purpose -- a compact 12.7K would hide the one failure in 12,660/12,661.
 * Test Health's tiles, its per-suite rows and its chart's y-axis all read from here, so the three
 * cannot disagree about how a number looks.
 */
export function formatCount(n: number, locale?: string): string {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(n);
}

/** `passed/total`, both grouped: `12,660/12,661`. */
export function formatRatio(passed: number, total: number, locale?: string): string {
  return `${formatCount(passed, locale)}/${formatCount(total, locale)}`;
}

/**
 * A count axis's ticks, from 0 to the first round step that holds `max`, in `intervals` steps. The
 * step is a whole half of its power of ten (3,500 for a max of 12,661: 0, 3,500, 7,000, 10,500,
 * 14,000), and never below 1, since a count has no fractions. The chart is given these ticks
 * rather than working out its own, so the widest label is known before it is drawn.
 */
export function countTicks(max: number, intervals = 4): number[] {
  const raw = Math.max(max, 0) / intervals;
  let step = 1;
  if (raw > 1) {
    const pow = 10 ** Math.floor(Math.log10(raw));
    const unit = pow >= 10 ? pow / 2 : pow;
    step = Math.ceil(raw / unit) * unit;
  }
  return Array.from({ length: intervals + 1 }, (_, i) => i * step);
}

/**
 * The width a y-axis needs for its widest tick label, so none is cut off (a 30px axis showed
 * 14000 as 4000). A digit at `fontSize` is a little over half the size wide, a separator less;
 * the allowance is generous rather than exact, because an axis too wide costs a few pixels and
 * one too narrow loses a digit.
 */
export function countAxisWidth(ticks: number[], fontSize = 10, locale?: string): number {
  const widest = ticks.reduce((w, t) => {
    const label = formatCount(t, locale);
    const digits = label.replace(/[^0-9]/g, "").length;
    const marks = label.length - digits;
    return Math.max(w, digits * 0.62 * fontSize + marks * 0.35 * fontSize);
  }, 0);
  // The tick's own offset from the axis line, and a margin at the left edge.
  return Math.ceil(widest + 12);
}
