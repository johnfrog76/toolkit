/** Text made safe to put inside a RegExp: every character a pattern reads as
 *  syntax is escaped, so the text matches only itself. The one copy of the
 *  rule: a second, hand-typed escape is how one of them misses a character. */
export function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
