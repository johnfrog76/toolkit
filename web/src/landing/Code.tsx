// The quick start's five lines, coloured the way a Solarized terminal would
// colour them: the verb, its flags, its strings and the comment after `#`.
// Pure markup over the README's lines; nothing is retyped.

type Token = { kind: "verb" | "flag" | "string" | "comment" | "plain"; text: string };

function tokenize(line: string): Token[] {
  const out: Token[] = [];
  const hash = line.indexOf("#");
  const code = hash >= 0 ? line.slice(0, hash) : line;
  const comment = hash >= 0 ? line.slice(hash) : "";
  const re = /("[^"]*")|(\s-[A-Za-z]+)|(\S+)|(\s+)/g;
  let first = true;
  let m: RegExpExecArray | null;
  while ((m = re.exec(code))) {
    if (m[1]) out.push({ kind: "string", text: m[1] });
    else if (m[2]) out.push({ kind: "flag", text: m[2] });
    else if (m[3]) {
      out.push({ kind: first ? "verb" : "plain", text: m[3] });
      first = false;
    } else out.push({ kind: "plain", text: m[0] });
  }
  if (comment) out.push({ kind: "comment", text: comment });
  return out;
}

export function Code({ lines }: { lines: readonly string[] }) {
  return (
    <code>
      {lines.map((line, i) => (
        <span key={i} className="lp-code-line">
          {tokenize(line).map((t, j) =>
            t.kind === "plain" ? (
              t.text
            ) : (
              <span key={j} className={`lp-tok-${t.kind}`}>
                {t.text}
              </span>
            ),
          )}
          {i < lines.length - 1 ? "\n" : ""}
        </span>
      ))}
    </code>
  );
}
