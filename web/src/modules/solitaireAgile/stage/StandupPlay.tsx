import { useMemo } from "react";
import { GeneratedDeckHost } from "../../deck/GeneratedDeckHost";
import type { DeckResolution } from "../../deck/GeneratedDeckHost";
import { useGetEnvQuery } from "../../../shell/api";
import { useGetStandupQuery } from "../api.solitaireAgile";
import { buildStandupDeck } from "./standupDeck";

// `/deck/ritual/standup` (paths.ts ROUTES.play): today's standup, PLAYED.
//
// The resolver for the generated deck: the same read the useful view makes
// (the standup route for the Space you are in -- RTK's cache means opening
// Play from the page fetches nothing new), built into a Deck by
// ./standupDeck.tsx and handed to the deck engine's second resolver
// (deck/GeneratedDeckHost.tsx). Nothing is pushed into the deck module's
// static list, and the deck module's flag need not be on: this file and the
// engine are a chunk fetched when this route is first drawn (index.tsx).

export function StandupPlay() {
  const { data: env, isLoading: envLoading } = useGetEnvQuery();
  const space = env?.config?.activeSpace ?? "";
  const { data, isLoading, error } = useGetStandupQuery(space, { skip: envLoading });
  const deck = useMemo(() => (data && !error ? buildStandupDeck(data) : undefined), [data, error]);
  const loading = envLoading || isLoading;
  const resolution: DeckResolution = {
    deck,
    loading,
    error:
      !loading && !deck
        ? {
            title: "Could not read today's standup",
            detail: "The agent did not answer. Nothing was read.",
          }
        : undefined,
  };
  return <GeneratedDeckHost resolution={resolution} />;
}
