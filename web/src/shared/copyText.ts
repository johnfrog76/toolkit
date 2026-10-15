/**
 * Put text on the clipboard, with the one fallback that works where the async
 * clipboard is refused (a non-secure origin, an old WebView): a hidden textarea
 * and execCommand. Lifted out of Daily's Copy Day so every copy in the app is
 * the same copy.
 */
export async function copyText(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
  }
}
