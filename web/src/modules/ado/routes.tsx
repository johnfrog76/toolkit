import { useState } from "react";
import {
  Body1,
  Button,
  Caption1,
  Spinner,
  Tab,
  TabList,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { AddRegular } from "@fluentui/react-icons";
import { Navigate, useLocation, useNavigate } from "react-router";
import { Tips, tipsReady } from "../../shared/Tips";
import type { Tip } from "../../shared/Tips";
import { Board } from "./Board";
import { useLaneLabel } from "./laneNames";
import {
  ModuleCardGrid,
  PageGrid,
  useHomeTabs,
  useOpenSettings,
  useShellFilters,
  useShellSlot,
} from "../../shell/cards";
import { homeTabFor } from "../../shell/registry";
import { HOME_BANNER_SLOT } from "../../shell/slots";
import type { HomeTabId } from "../../shell/registry";
import { ActionDialog } from "./ActionDialog";
import { useGetEnvQuery, useGetSurfacesQuery } from "../../shell/api";
import {
  tippableEntries,
  entryAnchor,
  entryRoute,
  spaceHasOwnTip,
  spaceTipEntries,
} from "../../shell/settingsWorkflows";
import { useGetEngagementSummaryQuery, useGetEngagementWorkBreakdownQuery } from "./api.ado";
import { FilterDrawer } from "./FilterDrawer";
import { drawerSections } from "./homeTabs";
import { trackerName } from "./TrackerBadge";
import { GH_EXPLAIN } from "./ghExplain";

const useStyles = makeStyles({
  // The row above Home's cards spans the whole centre block: the tabs at its
  // left edge, the List / Boards toggle at its right edge, flush with the right
  // edge of the cards below, nothing between. The geometry
  // is the earlier row's; the pager that sat at the right is gone -- a tab
  // has all its cards. The tabs never move, so nothing reflows when the toggle
  // is absent.
  // The row the tab strip sits in, and where its 0.5rem of inset lives -- on the
  // WRAPPER, not on the TabList (the owner: "probably put that on wrapper
  // obviously"). Everything on the row moves together, and the strip keeps the
  // one adjustment that is about Fluent rather than about layout.
  viewBar: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
    marginBottom: tokens.spacingVerticalS,
    paddingLeft: tokens.spacingHorizontalS,
  },
  // The tab strip's TEXT starts flush with the cards and the explain line: a
  // small Fluent tab insets its label by the tab's inline padding (SNudge) plus
  // the content's (XXS), so the list is pulled back by exactly that. It was
  // spacingHorizontalM, a medium tab's figure, and overshot by 4px.
  // With the wrapper's inset, the label then lands level with the intro line
  // underneath. The strip is not a shared component -- it is
  // Home's -- but it lines up with one.
  tabs: {
    marginLeft: `calc(-1 * (${tokens.spacingHorizontalSNudge} + ${tokens.spacingHorizontalXXS}))`,
  },
  // The explain line, then the button that belongs to it -- "New card button
  // always follows the explain text".
  explainRow: {
    display: "flex",
    alignItems: "center",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalM,
    marginBottom: tokens.spacingVerticalM,
  },
  // The text gives way -- it wraps inside itself -- so its button stays at the
  // end of the same row. Body1 and the same padding as the board's line above
  // the lanes (Board.tsx, barText): they are the same row doing the same job,
  // and they drifted apart once already.
  explain: {
    color: tokens.colorNeutralForeground3,
    flex: "1 1 20rem",
    minWidth: 0,
    padding: `${tokens.spacingVerticalL} ${tokens.spacingHorizontalS}`,
  },
  pageSpinner: {
    display: "flex",
    flexDirection: "column" as const,
    alignItems: "center",
    justifyContent: "center",
    minHeight: "60vh",
    gap: tokens.spacingVerticalL,
  },
});

/**
 * `/` -- the filter drawer above the shell's page of home cards.
 *
 * An archived org's cards all read the same engagement endpoints, so they are
 * pre-fetched here and the grid gates on all of them at once rather than
 * flickering card by card. Two of the four queries the old shell pre-fetched
 * belonged to ReviewArchive and SkillsSnapshot, which growth owns (spec S8.4):
 * when growth lands, it contributes those cards and its own gate.
 */
// Home has two pictures of the same cards: FOCUS (the list -- the card grid
// Home has always been) and the BOARD (the same cards, by where they are).
// They were a toggle, remembered per browser; now (the owner:
// "remove the toggle ... instead have in-page tabs: Focus | Board | Sprint |
// Actions") they are two TABS, each an address, and which of them a space
// has is the tab plan's business (homeTabs.ts): an ADO space has both, a
// local or GitHub space the Board alone. The Board component still knows
// nothing about where it is mounted (the owner: "a component that is
// just a route").

// The demo Spaces' slugs are not typed here: each one is named by
// the `space` of its entry in Config/settings-workflows.json, the one list the
// CLI and the agent read too, and the tips below follow those entries.

export function AdoHome() {
  const styles = useStyles();
  const { data: env, isFetching: envFetching } = useGetEnvQuery();
  // The discovery tips come from the settings-by-workflow list against the
  // CLI's states (D-W3); they wait for the inventory the way every tip waits
  // for /env, so a Space switch never flashes a stale one.
  const { data: surfaceData, isFetching: surfacesFetching } = useGetSurfacesQuery();
  const filters = useShellFilters();
  const location = useLocation();
  const tabs = useHomeTabs();
  const banner = useShellSlot(HOME_BANNER_SLOT);
  const [creating, setCreating] = useState(false);

  const navigate = useNavigate();

  const isArchive = env?.spaceStatus === "archive";
  // An org with no Azure DevOps has ONE view. The owner's rule: "if you don't
  // have ADO do you even need to see the other view -- no." The list is the ADO
  // worklist; without ADO it is the same cards drawn worse, beside a PR-comments
  // card that can never fill. So: the Board alone (homeTabs.ts), and the
  // connect tip at the foot -- plugging Azure DevOps in is what brings Focus.
  const boardOnly = env?.spaceStatus === "local";
  const activeSlug = env?.config?.activeSpace ?? "";
  const laneLabel = useLaneLabel();
  const openSettings = useOpenSettings();

  // The tips at the foot of every Home tab (the owner: "it lives in all
  // orgs, bottom of home tab(s)"). Each condition is a synchronous read of
  // /env, and a tip is retired by DOING: make a second board and the first tip
  // has nothing to say; no flag is written anywhere. There is no off switch
  // for now, on purpose. The CONTAINER is a Space (the owner:
  // "Switch Spaces from the menu under your avatar"); "board" stays the word
  // for the board itself.
  const tips: Tip[] = [];
  const orgs = env?.config?.spaces ?? [];
  // The demo Spaces' own tips first (the owner: connect-github
  // rotates first): each is an entry of Config/settings-workflows.json that
  // names a `space`. A journey tips while its Space is still local and its CTA
  // is that Space's wizard; the Demo's tip says where you are and has none.
  if (env) {
    for (const entry of spaceTipEntries(orgs, activeSlug)) {
      const page = entryRoute(entry, activeSlug, orgs);
      tips.push({
        id: entry.id,
        sentence: entry.tip ?? entry.question,
        cta: page ? "Try it" : undefined,
        onAction: page ? () => navigate(page) : undefined,
      });
    }
  }
  if (env && orgs.length === 1) {
    tips.push({
      id: "boards",
      sentence: "You can have more than one board to contain your cards.",
      cta: "Try it",
      onAction: () => openSettings("organisation"),
    });
  }
  if (env && orgs.length > 1) {
    // The boards tip's complement: once a second board exists, the thing to
    // teach is moving between them, and why. The instruction IS the sentence
    // -- the switcher is the avatar menu's submenu, which nothing can open for
    // you -- so this tip carries no CTA.
    tips.push({
      id: "switch",
      sentence:
        "Each board keeps its own cards and archive. Switch Spaces from the menu under your avatar.",
    });
  }
  // A local Space of your own gets the generic connect tip. A demo Space with
  // a tip of its own says it in its own words instead: Demo never
  // carries it -- connecting is the one thing Demo is built not to need -- and
  // the GitHub and Azure demos carry connect-github and connect-azure, which
  // replaced the old "switch to Example" tip (the owner: "each one is
  // part of the tips ... not required").
  if (env && boardOnly && !spaceHasOwnTip(activeSlug)) {
    tips.push({
      id: "connect",
      sentence: "You can connect a board to a GitHub repo or an Azure DevOps organization.",
      cta: "Try it",
      onAction: () => navigate(`/connect/${activeSlug}`),
    });
  }
  // The DISCOVERY tips (the tips card's family): the core naming an opt-in
  // door. Since settings by workflow (D-W3) they are the entries of
  // Config/settings-workflows.json that carry a tip, offered while every
  // surface of the entry reads `not configured` in the CLI's inventory --
  // never merely off: features.lounge=false is an answered no, and the tip
  // respects it. Retirement by doing, applied to a decision. The Lounge's tip
  // was the first of the family and is now one row of the list.
  if (env && surfaceData) {
    for (const entry of tippableEntries(surfaceData.surfaces)) {
      const target = entryAnchor(entry, surfaceData.activeSpace);
      tips.push({
        id: entry.id,
        sentence: entry.tip ?? entry.question,
        cta: target ? "Try it" : undefined,
        onAction: target ? () => openSettings(target) : undefined,
      });
    }
  }

  // Which tab the ADDRESS names; `/` is the strip's first tab.
  const tab = homeTabFor(location.pathname, tabs);
  const tabId: HomeTabId = tab?.id ?? "cards";
  const explainLine =
    (env?.tracker === "github" ? GH_EXPLAIN[tabId]?.(trackerName(env.tracker)) : undefined) ??
    EXPLAIN[tabId];
  const showStrip = tabs.length > 1;
  // Which of the drawer's sections reach a card on THIS tab -- read from the
  // same plan that decided which cards are on it, so the two cannot disagree
  // (the Issues tab's filters are one of them). None: the slot's control, disabled.
  const sections = drawerSections(env, tabId);
  // The strip's toolbar slot is drawn on EVERY tab of a strip so
  // nothing moves between tabs: with no sections the drawer renders its
  // control disabled. No strip, no hop, so the slot is drawn only where a
  // drawer has something in it.
  const showDrawer = showStrip || sections.length > 0;

  const { isLoading: engSummaryLoading } = useGetEngagementSummaryQuery(activeSlug, {
    skip: !isArchive || !activeSlug,
  });
  const { isLoading: workBreakdownLoading } = useGetEngagementWorkBreakdownQuery(activeSlug, {
    skip: !isArchive || !activeSlug,
  });
  const archiveLoading = isArchive && (engSummaryLoading || workBreakdownLoading);

  // An address for a tab this Home does not have -- /sprint in an archived org,
  // /actions at Tier 2 -- goes to Cards rather than showing an empty page.
  if (!tab && tabs.length > 0 && location.pathname !== "/") return <Navigate to="/" replace />;

  return (
    <>
      {showDrawer ? (
        <FilterDrawer
          value={filters.filterValue}
          onChange={filters.setFilterValue}
          activeRepo={filters.activeRepo}
          onRepoChange={filters.setActiveRepo}
          stateFilter={filters.stateFilter}
          onStateChange={filters.setStateFilter}
          stateOptions={filters.stateOptions}
          stateLabel={laneLabel}
          typeFilter={filters.typeFilter}
          onTypeChange={filters.setTypeFilter}
          linkFilter={filters.linkFilter}
          onLinkChange={filters.setLinkFilter}
          sections={sections}
        />
      ) : null}
      {archiveLoading ? (
        <div className={styles.pageSpinner}>
          <Spinner size="huge" />
          <Caption1>Loading engagement...</Caption1>
        </div>
      ) : (
        <>
          {banner}
          {showStrip ? (
            <div className={styles.viewBar}>
              <TabList
                className={styles.tabs}
                size="small"
                aria-label="Home"
                selectedValue={tabId}
                onTabSelect={(_e, d) => {
                  const next = tabs.find((t) => t.id === d.value);
                  if (next) navigate(next.path);
                }}
              >
                {tabs.map((t) => (
                  <Tab key={t.id} value={t.id}>
                    {t.label}
                  </Tab>
                ))}
              </TabList>
            </div>
          ) : null}
          {/* ONE view at a time. The owner's rule: "you toggle views, ADO or sprint
              lanes -- seeing both [is] too much ... users have limited ability to
              track things -- RAM." So the Board tab IS the board; it does not sit
              above the list. The board carries its own explain line and New card. */}
          {tabId === "board" ? (
            <Board />
          ) : (
            <>
              {explainLine && !isArchive ? (
                <div className={styles.explainRow}>
                  <Body1 className={styles.explain}>{explainLine}</Body1>
                  {tabId === "cards" ? (
                    <Button
                      size="small"
                      appearance="primary"
                      icon={<AddRegular />}
                      onClick={() => setCreating(true)}
                    >
                      New card
                    </Button>
                  ) : null}
                </div>
              ) : null}
              <PageGrid full={tabId === "backlog" || tabId === "design" || tabId === "docs"}>
                {tab?.cards ?? []}
              </PageGrid>
            </>
          )}
          {/* One invitation at a time, in order: nothing at the foot until the
              first-run banner has been answered. The gate is the SLOT, not the
              flag -- with deck off no banner ever renders (or clears the flag),
              and the tips must not wait on it. */}
          {banner.length === 0 && tipsReady(envFetching || surfacesFetching) ? (
            <Tips tips={tips} />
          ) : null}
          {/* The plain plus: create lives at the module's
              bottom right on every tab and both views, opening the SAME
              dialog -- local card, pickup, or (on gh) a new issue. An
              archived space makes nothing new. */}
          {!isArchive ? (
            <Button
              appearance="primary"
              shape="circular"
              size="large"
              icon={<AddRegular />}
              aria-label="Create"
              title="Create"
              style={{ position: "fixed", right: "28px", bottom: "28px", zIndex: 10 }}
              onClick={() => setCreating(true)}
            />
          ) : null}
          <ActionDialog open={creating} onClose={() => setCreating(false)} tab="create" />
        </>
      )}
    </>
  );
}

// One line per tab saying what it is for, on the row its button ends. The
// Cards line is the owner's, tightened. Sprint's and Actions' are
// drafts in the same voice. An archived org's Home is the retrospective, and
// says nothing here.
// Partial on purpose: an ADO space has no Backlog tab (its My Work list
// lives on Cards, assigned-to-you -- the board IS the backlog there), so a
// line for it would be dead text. Each tracker names ITSELF in its lines
// -- Azure DevOps here, GitHub in GH_EXPLAIN.
const EXPLAIN: Partial<Record<HomeTabId, string>> = {
  cards:
    "Your cards in Azure DevOps and your files on this machine, side by side. Dual entry is what keeps the sprint and the record moving together.",
  sprint:
    "How the ADO sprint is going: the engagement, where the work went, the pace, and the pipelines.",
  actions: "ADO actions: commands that belong to no one card.",
};

/** `/system` -- the shell's page of system cards, nothing else. */
export function AdoSystem() {
  return <ModuleCardGrid kind="system" />;
}
