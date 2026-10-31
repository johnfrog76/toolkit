import { useState } from "react";
import { useGetEnvQuery } from "../../shell/api";
import { useWriteConfigMutation } from "../ado/api.ado";
import { commandResultMessage } from "../ado/cliBridge";
import { archiveEdit, archivedIds } from "./deckList";

/**
 * This machine's put-away list (`deck.archived`), read from `/env` and written
 * through PUT /api/config -> `Config -Set`, the one writer. The write
 * invalidates `/env`, so the list and the page catch up when it lands. The deck
 * file is never touched.
 */
export function useDeckArchive() {
  const { data: env } = useGetEnvQuery();
  const archived = archivedIds(env?.config?.deckArchived);
  const [writeConfig, { isLoading: busy }] = useWriteConfigMutation();
  const [refusal, setRefusal] = useState<string | null>(null);

  const setArchived = async (id: string, put: boolean) => {
    setRefusal(null);
    try {
      const { result } = await writeConfig(archiveEdit(archived, id, put)).unwrap();
      if (result.status !== "success") {
        setRefusal(commandResultMessage(result, "Saved."));
      }
    } catch {
      setRefusal("Could not reach the agent. Nothing was written.");
    }
  };

  return {
    archived,
    isArchived: (id: string) => archived.includes(id),
    setArchived,
    busy,
    refusal,
    clearRefusal: () => setRefusal(null),
  };
}
