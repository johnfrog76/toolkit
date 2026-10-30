import { Navigate } from "react-router";
import type { ReactElement } from "react";
import type { CardContext, HomeTabId, ToolkitModule } from "../../shell/registry";
import { homeTabPlan } from "./homeTabs";
import type { HomeCardId } from "./homeTabs";

import { Board } from "./Board";
import { ConnectPage } from "./ConnectPage";
import { AdoHome, AdoSystem } from "./routes";
import { PRCommentsDetail } from "./PRCommentsDetail";
import { PromptDetailPage } from "./PromptDetailPage";
import { CARD_ROUTE, SYSTEM_PATH } from "./paths";
import { ReviewPage } from "./ReviewPage";
import { Billing } from "./Billing";

import { PRCommentsList } from "./PRCommentsList";
import { PromptStatus } from "./PromptStatus";
import { MyPRs } from "./MyPRs";
import { MyWork } from "./MyWork";
import { IssueReportCard } from "./IssueReportCard";
import { MilestonesCard } from "./MilestonesCard";
import { IssueDetailPage } from "./IssueDetailPage";
import { DeploysCard } from "./DeploysCard";
import { DesignList } from "./DesignList";
import { DesignDocPage } from "./DesignDocPage";
import { DocsLanding } from "./DocsLanding";
import { DocsDocPage } from "./DocsDocPage";
import { EngagementSummary } from "./EngagementSummary";
import { WorkBreakdown } from "./WorkBreakdown";
import { SprintVelocity } from "./SprintVelocity";
import { Dashboard } from "./Dashboard";
import { PromptActions } from "./CreatePrompt";

// Growth's, imported rather than forked (spec S8.4). The registry is what
// makes this safe: the archive branch below only renders when the shell has
// mounted this module, and these two cards read routes the growth module
// serves -- so with features.growth off they are simply not asked for.
import { ReviewArchive, SkillsSnapshot } from "../growth";

import { EnvCard } from "./EnvCard";
import { ModulesCard } from "./ModulesCard";
import { ConfigSettings } from "./ConfigSettings";
import { ConnectAdoCard } from "./ConnectAdoCard";
import { ToolkitLog } from "./ToolkitLog";
import { TestHealth } from "./TestHealth";

/**
 * The ADO prompt-engineering module -- the always-on core.
 *
 * No `feature` flag: this is what the toolkit is for, and an install that
 * switched it off would have no home page. Everything else is opt-in.
 */
export const adoModule: ToolkitModule = {
  id: "ado",

  routes: [
    { path: "/", element: <AdoHome /> },
    { path: SYSTEM_PATH, element: <AdoSystem /> },
    { path: "/pr-comments/:filename", element: <PRCommentsDetail /> },
    { path: CARD_ROUTE, element: <PromptDetailPage /> },
    { path: "/review", element: <ReviewPage /> },
    { path: "/review/:folder", element: <ReviewPage /> },
    // Home's tabs, each an address, so a tab can be linked and Back walks
    // between them; `/` is the strip's
    // first tab. The Board is a tab now; it was a toggle and an alias.
    { path: "/board", element: <AdoHome /> },
    { path: "/backlog", element: <AdoHome /> },
    { path: "/issue/:num", element: <IssueDetailPage /> },
    // The connect wizard, on an address (settings by workflow W2, D-W12).
    { path: "/connect/:slug", element: <ConnectPage /> },
    { path: "/sprint", element: <AdoHome /> },
    { path: "/actions", element: <AdoHome /> },
    // The Design tab and one document's reading room (Studio S2, D-S11).
    { path: "/design", element: <AdoHome /> },
    { path: "/design/:folder/:name", element: <DesignDocPage /> },
    // The archive under each root (design lifecycle L2): design/archive/x.md.
    { path: "/design/:folder/archive/:name", element: <DesignDocPage archive /> },
    // The Docs tab -- it lands on the README -- and one document's room, its
    // path in the repo after the prefix (D-S12).
    { path: "/docs", element: <AdoHome /> },
    { path: "/docs/*", element: <DocsDocPage /> },
    { path: "/daily", element: <Billing /> },
    // The address this page had while it was called Billing. Bookmarks keep working.
    { path: "/billing", element: <Navigate to="/daily" replace /> },
  ],

  nav: [
    // `/board` is Home with the board on, and `/sprint` and `/actions` are
    // Home's other tabs, so Home is where you are on all of them.
    {
      label: "Home",
      to: "/",
      match: (p) =>
        ["/", "", "/board", "/backlog", "/sprint", "/actions", "/design", "/docs"].includes(p) ||
        p.startsWith("/issue/") ||
        p.startsWith("/design/") ||
        p.startsWith("/docs/"),
    },
    { label: "System", to: SYSTEM_PATH, match: (p) => p === SYSTEM_PATH },
    {
      label: "Daily",
      to: "/daily",
      match: (p) => p === "/daily",
      // A finished engagement has nothing left to bill.
      hidden: (ctx) => ctx.env?.spaceStatus === "archive",
    },
  ],

  homeTabs,
  systemCards,
  // Tier-independent and unflagged, like the module: config is what a Tier 3
  // machine needs most.
  settingsSections: () => [<ConfigSettings key="config" />],
  // Where in it a person wants to GO. The anchors are marked in ConfigSettings.
  settingsLinks: () => [
    { label: "This Space", anchor: "organisation" },
    { label: "Modules", anchor: "modules" },
    { label: "Shortcuts", anchor: "shortcuts" },
  ],
};

/**
 * Home's cards, by tab. WHICH card goes on WHICH tab is `homeTabPlan`
 * (homeTabs.ts) -- data, pinned by a table; this only builds each card.
 */
function homeTabs(ctx: CardContext): Partial<Record<HomeTabId, ReactElement[]>> {
  const {
    env,
    filterValue,
    stateFilter,
    stateOptions,
    activeRepo,
    typeFilter,
    linkFilter,
    activeSkillTag,
  } = ctx;
  const activeSlug = env?.config?.activeSpace ?? "";
  const isArchived = env?.spaceStatus === "archive";
  // Clicking a skill tag filters the breakdown beside it, and clicking the
  // same one again clears it. The state is the shell's, so the handler goes
  // through the context rather than holding its own copy.
  const onTagClick = (tag: string) => ctx.setActiveSkillTag((prev) => (prev === tag ? null : tag));

  // Two of the retrospective's cards are growth's (spec S8.4): a module may
  // import another module's card, it may not fork one. The plan names them only
  // when growth is on.
  const build: Record<HomeCardId, () => ReactElement> = {
    comments: () => <PRCommentsList key="comments" filter={filterValue} activeRepo={activeRepo} />,
    prs: () => <MyPRs key="prs" filter={filterValue} activeRepo={activeRepo} />,
    status: () => (
      <PromptStatus
        key="status"
        filter={filterValue}
        globalState={stateFilter}
        stateOptions={stateOptions}
        activeRepo={activeRepo}
        typeFilter={typeFilter}
        linkFilter={linkFilter}
      />
    ),
    work: () => (
      <MyWork
        key="work"
        filter={filterValue}
        globalState={stateFilter}
        stateOptions={stateOptions}
        activeRepo={activeRepo}
      />
    ),
    // Where My Work and My PRs would be. Said, not faked -- see ConnectAdoCard.
    // The Board tab's one card IS the board. Home draws it in place of a grid
    // (routes.tsx); it is here so the tab exists by the same declaration as
    // every other, and so moduleCards('home') is honest.
    board: () => <Board key="board" />,
    "connect-ado": () => (
      <ConnectAdoCard
        key="connect-ado"
        slug={activeSlug}
        orgName={env?.config?.spaces?.find((o) => o.slug === activeSlug)?.name ?? activeSlug}
      />
    ),
    "engagement-summary": () => (
      <EngagementSummary key="engagement-summary" slug={activeSlug} isArchived={isArchived} />
    ),
    "work-breakdown": () => (
      <WorkBreakdown key="work-breakdown" slug={activeSlug} activeTag={activeSkillTag} />
    ),
    "sprint-velocity": () => <SprintVelocity key="sprint-velocity" />,
    "issue-report": () => <IssueReportCard key="issue-report" />,
    milestones: () => <MilestonesCard key="milestones" />,
    deploys: () => <DeploysCard key="deploys" />,
    design: () => <DesignList key="design" />,
    docs: () => <DocsLanding key="docs" />,
    dashboard: () => <Dashboard key="dashboard" />,
    actions: () => <PromptActions key="actions" />,
    "review-archive": () => <ReviewArchive key="review-archive" activeTag={activeSkillTag} />,
    "skills-snapshot": () => (
      <SkillsSnapshot
        key="skills-snapshot"
        slug={activeSlug}
        activeTag={activeSkillTag}
        onTagClick={onTagClick}
      />
    ),
  };

  const plan = homeTabPlan(env);
  // Every lane the plan names, mechanically -- naming the lanes by hand here
  // is how the Backlog tab shipped in the plan and never rendered (the owner's
  // UAT): the plan was pinned by a table, this mapping was not.
  return Object.fromEntries(
    (Object.entries(plan) as [HomeTabId, HomeCardId[]][]).map(([tab, ids]) => [
      tab,
      ids.map((id) => build[id]()),
    ]),
  );
}

function systemCards(ctx: CardContext): ReactElement[] {
  const { env } = ctx;
  // Environment reports what the machine resolved. What CHANGES it is the
  // Configuration section of the settings drawer (settingsSections below) --
  // a card here once.
  // Environment, Modules, Log, Test Health -- four (the owner: "system tab
  // four and lounge tab four"); Modules holds the add-ons' rows that were
  // the Environment card's foot, and the Space switcher went with them: the
  // avatar menu is the one place a Space is switched.
  const list: ReactElement[] = [
    <EnvCard key="env" />,
    <ModulesCard key="modules" />,
    <ToolkitLog key="log" />,
  ];
  if (env && env.tier <= 2) list.push(<TestHealth key="test-health" />);
  // The Face card lives in the LOUNGE now (spec D-L24, the owner:
  // "face first then games", then: "I was expecting face card now lives in
  // lounge rather than system") -- and only there: with the Lounge off it is
  // absent, like the rest of the module. (It went into the settings drawer
  // for a day, on a misreading; then it was here, in the slot the
  // Configuration card left free.)
  return list;
}
