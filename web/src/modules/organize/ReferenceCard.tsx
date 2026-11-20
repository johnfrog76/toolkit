/**
 * The Reference panel -- the Organize add-on's second surface.
 *
 * The hub's reference documents, kept for reading: a list panel with a card item
 * per document, its title the row, its Valid dates and its Source the meta, and
 * Open, which reads it here (ReferencePage.tsx). The search asks the agent --
 * every word, any order, case ignored, the rule the hub's other searches use --
 * and a hit says the line that matched. Read only: nothing is written, moved or
 * archived from the browser (docs/modules/organize.md, "Reference").
 */
import { useEffect, useState } from "react";
import { useNavigate } from "react-router";
import { BookRegular } from "@fluentui/react-icons";
import { ROW } from "../../shared/CardActions";
import { ListPanel } from "../../shell/kinds/ListPanel";
import type { CardItemData } from "../../shell/CardItem";
import { useGetReferenceQuery } from "./api.organize";
import type { ReferenceDoc } from "./api.organize";
import { referencePath } from "./paths";

/** How long typing rests before the agent is asked. */
const SEARCH_REST_MS = 250;

export function ReferenceCard() {
  const navigate = useNavigate();
  const [typed, setTyped] = useState("");
  const [asked, setAsked] = useState("");
  useEffect(() => {
    const t = setTimeout(() => setAsked(typed.trim()), SEARCH_REST_MS);
    return () => clearTimeout(t);
  }, [typed]);
  const { data, isLoading, isError, isFetching, refetch } = useGetReferenceQuery(asked);
  const items = data?.items ?? [];
  const searching = asked !== "";

  const toItem = (doc: ReferenceDoc): CardItemData => ({
    id: doc.name,
    title: doc.title,
    // The card clamps this to two lines. A search says the line that matched,
    // which is why the document is here; the list says what the document opens with.
    description: (searching && doc.line ? doc.line : doc.excerpt) || undefined,
    meta: [
      ...(doc.source
        ? [
            {
              badge: {
                label: doc.source,
                color: "informative" as const,
                appearance: "outline" as const,
              },
            },
          ]
        : []),
      { text: doc.valid ? `Valid: ${doc.valid}` : "No valid dates" },
    ],
    primary: ROW.open.action({
      detail: "the document",
      onClick: () => navigate(referencePath(doc.name)),
    }),
  });

  const icon = <BookRegular />;
  return (
    <ListPanel
      title="Reference"
      info="Documents you keep for reading, not for doing -- a holiday list, a policy guide. Each is one file in your hub's reference folder; you file them by hand."
      items={items}
      item={toItem}
      loading={isLoading ? { label: "Loading reference documents..." } : undefined}
      empty={
        isError
          ? {
              icon,
              title: "Could not load your reference documents",
              detail: "The agent did not answer. Nothing was read.",
            }
          : {
              icon,
              title: "No reference documents",
              detail: "A document is a .md file in the reference folder of your hub.",
            }
      }
      filteredEmpty={
        searching && !isError
          ? {
              icon,
              tone: "filtered",
              title: "Nothing found",
              detail: "No document has every word you typed.",
            }
          : undefined
      }
      search={{
        label: "Search reference documents",
        placeholder: "Search",
        value: typed,
        onChange: setTyped,
      }}
      refresh={{ onClick: refetch, isFetching }}
      count={data?.count ?? 0}
      countLabel={`${data?.count ?? 0} reference documents`}
    />
  );
}
