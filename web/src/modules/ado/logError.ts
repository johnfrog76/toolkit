/**
 * Log a web-side error back to the agent's /api/log endpoint so it shows up
 * in the toolkit log alongside backend entries. Fire-and-forget — never throws.
 */
export function logWebError(source: string, detail: string): void {
  fetch("/api/log", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      log_type: "ERR",
      source,
      detail: detail.slice(0, 500),
    }),
  }).catch(() => {
    // Swallow — if the agent is unreachable, nothing we can do
  });
}
