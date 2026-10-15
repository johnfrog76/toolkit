// Which voices exist for which slide, and where their audio is.
//
// The filename is the whole contract: voices/<deckId>/<slideId>-<voiceId>.mp3.
// Vite turns the glob into hashed asset URLs at build time, so there is no
// manifest to fall out of step with the files -- a voice is offered exactly
// when its file is on disk. The files sit under src/, not public/: an import
// from public/ ships every file twice (once hashed, once copied verbatim).
//
// The glob is relative to THIS file. Move it and a wrong path resolves to zero
// files with no error -- the deck plays silent and nothing says why.
const voiceUrls = import.meta.glob<string>("./voices/*/*.mp3", {
  eager: true,
  query: "?url",
  import: "default",
});

const urlByKey = new Map<string, string>();
for (const [path, url] of Object.entries(voiceUrls)) {
  const tail = path.split("/voices/")[1]; // "<deckId>/<slideId>-<voice>.mp3"
  if (tail) urlByKey.set(tail, url);
}

// The voice list is the ENGINE's (narrationConstants) -- the ids are the ones the
// files were baked with and are in their filenames, so a second list here could
// only ever disagree with the first.
export { NARRATION_VOICES as BAKED_VOICES } from "./engine/narrationConstants";

export function voiceUrl(
  deckId: string | undefined,
  slideId: string,
  voice: string,
): string | null {
  if (!deckId) return null;
  return urlByKey.get(`${deckId}/${slideId}-${voice}.mp3`) ?? null;
}
