import { useMemo } from "react";
import { useNavigate, useParams } from "react-router";
import { Badge, Body1, Caption1, Subtitle2, makeStyles, tokens } from "@fluentui/react-components";
import { SlideTextRegular } from "@fluentui/react-icons";
import { BackButton } from "../../shared/BackButton";
import { CardActions, ROW } from "../../shared/CardActions";
import { EmptyState } from "../../shared/EmptyState";
import { FilePath } from "../../shared/FilePath";
import { PageCard } from "../../shared/PageCard";
import { StatusMessage } from "../../shared/StatusMessage";
import { DECKS } from "./decks/index";
import { estimateDeckDuration } from "./engine/deckDuration";
import { STATE_LABEL, deckFilePath, deckState } from "./deckList";
import { DECK_MOVES } from "./deckMoves";
import { deckPlayPath } from "./paths";
import { useDeckArchive } from "./useDeckArchive";

// A deck's page: the house's detail page -- PageCard, the back arrow and
// the title on the left, the controls on the right, the body below -- between
// the Decks card and the player. Everything on it is READ from the deck file;
// nothing here edits one. Play is the one exposed action and opens the player
// unchanged. Archive is this machine's: it writes `deck.archived` through
// Config, and the deck's own state stays the studio's (docs/modules/deck.md,
// "A deck's page").

const useStyles = makeStyles({
  page: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalM, width: "100%" },
  titleBlock: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  metaRow: {
    display: "flex",
    columnGap: tokens.spacingHorizontalS,
    rowGap: tokens.spacingVerticalXXS,
    flexWrap: "wrap",
    alignItems: "center",
    color: tokens.colorNeutralForeground3,
  },
  body: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalM,
    marginTop: tokens.spacingVerticalS,
  },
  away: { color: tokens.colorNeutralForeground3 },
  facts: {
    display: "grid",
    gridTemplateColumns: "max-content minmax(0, 1fr)",
    columnGap: tokens.spacingHorizontalL,
    rowGap: tokens.spacingVerticalS,
    alignItems: "center",
    margin: 0,
  },
  term: { color: tokens.colorNeutralForeground3 },
  value: {
    margin: 0,
    minWidth: 0,
    display: "flex",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalXS,
  },
});

export function DeckPage() {
  const styles = useStyles();
  const navigate = useNavigate();
  const { deckId = "" } = useParams<{ deckId: string }>();
  const deck = DECKS.find((d) => d.id === deckId);
  const facts = useMemo(() => {
    if (!deck) return null;
    const slides = deck.slides();
    return { slideCount: slides.length, duration: estimateDeckDuration(slides) };
  }, [deck]);
  const { isArchived, setArchived, busy, refusal, clearRefusal } = useDeckArchive();
  const away = deck ? isArchived(deck.id) : false;

  const empty = deck ? undefined : (
    <EmptyState
      icon={<SlideTextRegular />}
      tone="error"
      title={`No deck ${deckId}`}
      detail="No deck by that id is registered in this build. The Decks card lists the ones that are."
    />
  );

  return (
    <div className={styles.page}>
      <PageCard
        empty={empty}
        headerLeft={
          <>
            <BackButton />
            {deck && (
              <div className={styles.titleBlock}>
                <Subtitle2 as="h1">{deck.title}</Subtitle2>
                <div className={styles.metaRow}>
                  <Badge appearance="tint" color="brand" size="small">
                    deck
                  </Badge>
                  <Badge appearance="tint" color="subtle" size="small">
                    {STATE_LABEL[deckState(deck)]}
                  </Badge>
                  {away ? (
                    <Badge appearance="outline" color="subtle" size="small">
                      archived on this machine
                    </Badge>
                  ) : null}
                </div>
              </div>
            )}
          </>
        }
        headerRight={
          deck ? (
            <CardActions
              primaryAction={DECK_MOVES.play.action({
                onClick: () => navigate(deckPlayPath(deck.id)),
              })}
              menuLabel={`Actions for ${deck.title}`}
              busy={busy}
              secondaryActions={[
                away
                  ? DECK_MOVES.unarchive.action({ onClick: () => void setArchived(deck.id, false) })
                  : ROW.archive.action({ onClick: () => void setArchived(deck.id, true) }),
              ]}
            />
          ) : undefined
        }
      >
        {deck && facts && (
          <div className={styles.body}>
            {refusal ? (
              <StatusMessage status="error" onDismiss={clearRefusal}>
                {refusal}
              </StatusMessage>
            ) : null}
            {away ? (
              <Caption1 className={styles.away}>
                Archived on this machine: the Decks card lists it under its archived filter, not in
                its list. The deck file is unchanged; Unarchive brings it back.
              </Caption1>
            ) : null}
            <Body1>{deck.summary}</Body1>
            <dl className={styles.facts} aria-label="About this deck">
              <dt className={styles.term}>
                <Caption1>State</Caption1>
              </dt>
              <dd className={styles.value}>
                <Body1>{STATE_LABEL[deckState(deck)]}</Body1>
              </dd>
              <dt className={styles.term}>
                <Caption1>Tags</Caption1>
              </dt>
              <dd className={styles.value}>
                {(deck.tags ?? []).length > 0 ? (
                  (deck.tags ?? []).map((tag) => (
                    <Badge key={tag} appearance="tint" color="informative" size="small">
                      {tag}
                    </Badge>
                  ))
                ) : (
                  <Body1>none</Body1>
                )}
              </dd>
              <dt className={styles.term}>
                <Caption1>Slides</Caption1>
              </dt>
              <dd className={styles.value}>
                <Body1>{facts.slideCount}</Body1>
              </dd>
              <dt className={styles.term}>
                <Caption1>Running time</Caption1>
              </dt>
              <dd className={styles.value}>
                <Body1>about {facts.duration}</Body1>
              </dd>
              <dt className={styles.term}>
                <Caption1>Played copy</Caption1>
              </dt>
              <dd className={styles.value}>
                <FilePath path={deckFilePath(deck.id)} what="deck file's path" />
              </dd>
            </dl>
          </div>
        )}
      </PageCard>
    </div>
  );
}
