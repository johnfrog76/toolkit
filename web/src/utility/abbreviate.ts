/** Derive a short abbreviation from a project name. */
export function getProjectTag(name: string): string {
  const words = name.split(/\s+/);
  if (words.length > 1) {
    return words
      .map((w) => w[0])
      .join("")
      .toUpperCase();
  }
  const segments = name.split(/(?=[A-Z])/);
  return segments
    .map((s) => s[0])
    .join("")
    .toUpperCase();
}
