import {
  FluentProvider,
  Button,
  makeStyles,
  tokens,
  useRestoreFocusTarget,
} from "@fluentui/react-components";
import { fluentThemeFor, noiseSvgUrl } from "./theme";
import { BootSpinner } from "./BootSpinner";
import { ThemePicker } from "./ThemePicker";
import { AvatarMenu } from "./AvatarMenu";
import { SpaceAnchor } from "./SpaceAnchor";

import { useState, useMemo, useEffect, useCallback } from "react";
import { useDispatch, useSelector } from "react-redux";
import type { AppDispatch, RootState } from "./store";
import { filtersActions } from "./filtersSlice";
import { Routes, Route, useLocation, useNavigate } from "react-router";
import { useGetEnvQuery, useGetHealthQuery, useSwitchModeMutation } from "./api";
import { AgentLostBanner, AgentUnreachable, NotFound, rememberCliPrefix } from "./ShellStates";
import {
  activeModules,
  moduleCards,
  moduleHeaderItems,
  moduleHomeTabs,
  moduleNav,
  moduleNavSplit,
  moduleRoutes,
  moduleSettings,
  moduleSettingsLinks,
  moduleSlot,
  isChromeless,
  modules,
  dormantOwner,
  // The filter tuple every card gets (spec S8.2) includes stateOptions, the
  // union of work-item and prompt states, and the shell needs it while
  // building CardContext during its own render -- before any module route has
  // mounted. Re-exported through the registry rather than imported from
  // modules/ado directly, so the registry stays the one door
  // (web/README.md, "The one place the shell imports from a module").
  useGetWorkItemsQuery,
  useGetStatusQuery,
} from "./registry";
import type { CardContext } from "./registry";
import { ShellProvider } from "./cards";
import { SettingsDrawer } from "./SettingsDrawer";
import { useUnsavedTotal } from "./settings";
import { ToolKitLogo } from "../shared/ToolKitLogo";
import { GrantedSkin } from "../shared/GrantedSkin";
import { useWornTheme } from "../hooks/useWornTheme";

const useStyles = makeStyles({
  root: {
    padding: "2rem",
    // border-box, or the page is 100vh PLUS its own padding: every page that
    // fits the window scrolled by exactly 4rem for nothing. The max width grows
    // by the same padding so the content column stays the 1200px it was.
    boxSizing: "border-box",
    minHeight: "100vh",
    backgroundColor: tokens.colorSubtleBackground,
    color: tokens.colorNeutralForeground1,
    maxWidth: "calc(1200px + 4rem)",
    marginLeft: "auto",
    marginRight: "auto",
    position: "relative",
    // A page is never wider than its viewport. The 16px gutter below is the
    // phone equivalent of the 2rem one: 2rem each side of a 430px screen spends
    // a seventh of it on nothing.
    minWidth: 0,
    "@media (max-width: 599px)": {
      padding: "1rem",
    },
  },
  nav: {
    display: "flex",
    alignItems: "center",
    // Wraps rather than overflows: below ~480px the logo, the links and the
    // theme selector do not fit on one line, and a phone must not scroll
    // sideways to reach the last of them.
    flexWrap: "wrap" as const,
    rowGap: tokens.spacingVerticalS,
    alignContent: "flex-start",
    marginBottom: tokens.spacingVerticalL,
  },
  navSlot: {
    flex: "0 0 auto",
    minWidth: 0,
    // Air between the brand and the strip, so the mark stands on its own.
    marginRight: tokens.spacingHorizontalXXL,
  },
  // The strip reads "this Space | yours": the anchor pill, the
  // divider, then the engineer's tabs -- grouped at the left, after the brand.
  navLinks: {
    flex: "1 1 auto",
    display: "flex",
    alignItems: "center",
    justifyContent: "flex-start",
    flexWrap: "wrap" as const,
    minWidth: 0,
    gap: tokens.spacingHorizontalM,
  },
  // A 1px rule in the theme's stroke; the strip's gap stands on both sides.
  navDivider: {
    width: "1px",
    height: "1.25rem",
    flexShrink: 0,
    backgroundColor: tokens.colorNeutralStroke1,
  },
  navPager: {
    flex: "1 1 auto",
    display: "flex",
    alignItems: "center",
    justifyContent: "flex-end",
    flexWrap: "wrap" as const,
    minWidth: 0,
    gap: tokens.spacingHorizontalXS,
  },
  main: { outline: "none" },
  // Off screen until a keyboard reaches it: the first Tab on any page.
  skipLink: {
    position: "absolute",
    left: "-9999px",
    top: "0.5rem",
    zIndex: 10,
    padding: "0.4rem 0.8rem",
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: tokens.colorNeutralBackground1,
    color: tokens.colorNeutralForeground1,
    ":focus": { left: "0.5rem" },
  },
});

// The System page's cards, four to a page. Home has no pages: it has named
// tabs (registry HOME_TABS), and a tab shows all of its cards.
const PAGE_SIZE = 4;

export function App() {
  const styles = useStyles();
  // FULL SKIN (D-L13; the owner: "it is full skin"):
  // useWornTheme is the one truth -- the person's chosen theme, or the
  // skin's own record while a grant is worn. The logo and the avatar menu
  // read the same hook, so the skin owns the WHOLE palette, locked.
  const { theme, active: activeTheme } = useWornTheme();
  const isDark = theme === "dark";
  const fluentTheme = fluentThemeFor(activeTheme);
  const location = useLocation();
  const navigate = useNavigate();
  const {
    data: env,
    isLoading: envLoading,
    isError: envFailed,
    isFetching: envFetching,
    refetch: refetchEnv,
  } = useGetEnvQuery();
  // The heartbeat. Quick while the agent is away, so the page fills in by
  // itself within seconds of it starting; slow while all is well.
  const [heartbeatMs, setHeartbeatMs] = useState(15000);
  const {
    isError: heartbeatFailed,
    isFetching: heartbeatFetching,
    refetch: refetchHealth,
  } = useGetHealthQuery(undefined, { pollingInterval: heartbeatMs });
  const agentAway = heartbeatFailed || (envFailed && !env);
  useEffect(() => {
    setHeartbeatMs(agentAway ? 4000 : 15000); // eslint-disable-line react-hooks/set-state-in-effect
  }, [agentAway]);
  // Back again: everything on screen is stale or was never fetched.
  useEffect(() => {
    if (!heartbeatFailed && (envFailed || !env) && !envFetching) void refetchEnv();
  }, [heartbeatFailed]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => rememberCliPrefix(env?.cliPrefix), [env?.cliPrefix]);
  const checkAgent = () => {
    void refetchHealth();
    void refetchEnv();
  };
  const [switchMode, { isLoading: isSwitching }] = useSwitchModeMutation({
    fixedCacheKey: "org-switch",
  });
  const isTier1 = env?.tier === 1;
  const { data: workData } = useGetWorkItemsQuery(undefined, {
    skip: !isTier1,
  });
  const { data: statusData } = useGetStatusQuery();

  const isSystem = location.pathname === "/system";

  // The drawer's six values live in the store (filtersSlice): a successful
  // Space switch resets them there, so nothing here has to.
  const dispatch = useDispatch<AppDispatch>();
  const { filterValue, activeRepo, stateFilter, typeFilter, linkFilter, activeSkillTag } =
    useSelector((s: RootState) => s.filters);
  const setFilterValue = useCallback(
    (v: string) => void dispatch(filtersActions.setFilterValue(v)),
    [dispatch],
  );
  const setActiveRepo = useCallback(
    (v: string | null) => void dispatch(filtersActions.setActiveRepo(v)),
    [dispatch],
  );
  const setStateFilter = useCallback(
    (v: string) => void dispatch(filtersActions.setStateFilter(v)),
    [dispatch],
  );
  const setTypeFilter = useCallback(
    (v: string) => void dispatch(filtersActions.setTypeFilter(v)),
    [dispatch],
  );
  const setLinkFilter = useCallback(
    (v: string) => void dispatch(filtersActions.setLinkFilter(v)),
    [dispatch],
  );
  const setActiveSkillTag = useCallback(
    // The registry's contract is an updater (a tag click toggles), so read the store's current value.
    (update: (prev: string | null) => string | null) =>
      void dispatch((d, getState) =>
        d(filtersActions.setActiveSkillTag(update(getState().filters.activeSkillTag))),
      ),
    [dispatch],
  );

  // The themed background belongs to the DOCUMENT, not to a container.
  // FluentProvider's element is only as wide as the viewport, so anything that
  // did overflow showed a plain white band down the right-hand side of every
  // card -- the page's own theme stopping at the content's width. A background
  // on <body> propagates to the canvas and covers the whole scrollable area, so
  // a future overflow is a layout bug and never a white stripe.
  useEffect(() => {
    const { style } = document.body;
    style.backgroundImage = activeTheme.page.image;
    style.backgroundAttachment = "fixed";
    style.backgroundColor = activeTheme.page.color;
    style.colorScheme = isDark ? "dark" : "light";
  }, [isDark, activeTheme]);

  const activeSlug = env?.config?.activeSpace ?? "";
  useEffect(() => {
    setActiveSkillTag(() => null);
  }, [activeSlug, setActiveSkillTag]);

  const stateOptions = useMemo(() => {
    const set = new Set<string>();
    for (const wi of workData?.items ?? []) set.add(wi.state);
    for (const p of statusData?.prompts ?? []) set.add(p.status);
    return ["All", ...Array.from(set).sort()];
  }, [workData, statusData]);

  // Off means absent: a module whose feature flag is false contributes no
  // route, no nav entry and no card.
  const active = useMemo(() => activeModules(modules, env), [env]);

  const cardContext: CardContext = useMemo(
    () => ({
      env,
      filterValue,
      stateFilter,
      stateOptions,
      activeRepo,
      typeFilter,
      linkFilter,
      activeSkillTag,
      setActiveSkillTag,
    }),
    [
      env,
      filterValue,
      stateFilter,
      stateOptions,
      activeRepo,
      typeFilter,
      linkFilter,
      activeSkillTag,
      setActiveSkillTag,
    ],
  );

  const homeTabs = useMemo(() => moduleHomeTabs(active, cardContext), [active, cardContext]);
  const systemCards = useMemo(
    () => moduleCards(active, cardContext, "system"),
    [active, cardContext],
  );
  const settingsSections = useMemo(
    () => moduleSettings(active, cardContext),
    [active, cardContext],
  );
  const navEntries = useMemo(() => moduleNav(active, cardContext), [active, cardContext]);
  // Home is drawn as the Space anchor, the rest as the tabs after the divider.
  const { anchor: homeEntry, tabs: navTabs } = useMemo(
    () => moduleNavSplit(active, cardContext),
    [active, cardContext],
  );
  const headerItems = useMemo(() => moduleHeaderItems(active, cardContext), [active, cardContext]);
  const routes = useMemo(() => moduleRoutes(active), [active]);

  const settingsLinks = useMemo(
    () => moduleSettingsLinks(active, cardContext),
    [active, cardContext],
  );
  // Five tabs open used to be five tabs called "ToolKit". The page's name is
  // its nav entry's; a page with none (a bad address) is just the app.
  const pageName = navEntries.find((n) => n.match(location.pathname))?.label;
  useEffect(() => {
    document.title = pageName ? `${pageName} · ToolKit` : "ToolKit";
  }, [pageName]);

  const [settingsOpen, setSettingsOpen] = useState(false);
  // A door in the drawer may be a PAGE (the connect wizard): the drawer closes
  // when the address changes, so the page is what you see. Noticed while
  // rendering, against the address the last render saw.
  const [drawerPath, setDrawerPath] = useState(location.pathname);
  if (drawerPath !== location.pathname) {
    setDrawerPath(location.pathname);
    setSettingsOpen(false);
  }
  // Where the drawer should arrive. A fresh object per request, so asking for
  // the same place twice arrives twice.
  const [settingsAnchor, setSettingsAnchor] = useState<{ at?: string }>({});
  const openSettings = useCallback((anchor?: string) => {
    setSettingsAnchor({ at: anchor });
    setSettingsOpen(true);
  }, []);
  // "That page is switched off" goes to the switch, not to the top of a list.
  const dormant = dormantOwner(modules, active, location.pathname);
  // Closing the drawer hands keyboard focus back to the avatar. Without this
  // pair (the source half is in SettingsDrawer) Escape drops focus on <body>.
  const restoreFocusTarget = useRestoreFocusTarget();
  // Edits a section is holding for a Save. They survive the drawer closing, so
  // the avatar has to say they exist -- otherwise a closed drawer hides them.
  const unsaved = useUnsavedTotal();
  const [systemPage, setSystemPage] = useState(0);

  const totalPages = Math.max(1, Math.ceil(systemCards.length / PAGE_SIZE));
  const pageCards = systemCards.slice(systemPage * PAGE_SIZE, (systemPage + 1) * PAGE_SIZE);

  const shellValue = useMemo(
    () => ({
      cards: {
        home: isSystem ? [] : homeTabs.flatMap((t) => t.cards),
        system: isSystem ? pageCards : [],
      },
      homeTabs: isSystem ? [] : homeTabs,
      filters: {
        filterValue,
        setFilterValue,
        activeRepo,
        setActiveRepo,
        stateFilter,
        setStateFilter,
        stateOptions,
        typeFilter,
        setTypeFilter,
        linkFilter,
        setLinkFilter,
      },
      slot: (name: string) => moduleSlot(active, cardContext, name),
      openSettings,
      pager: { page: systemPage, totalPages, onPageChange: setSystemPage },
    }),
    [
      isSystem,
      pageCards,
      homeTabs,
      filterValue,
      setFilterValue,
      activeRepo,
      setActiveRepo,
      stateFilter,
      setStateFilter,
      stateOptions,
      typeFilter,
      setTypeFilter,
      linkFilter,
      setLinkFilter,
      active,
      cardContext,
      openSettings,
      systemPage,
      totalPages,
    ],
  );

  if (envLoading || isSwitching) {
    return (
      <FluentProvider
        theme={fluentTheme}
        style={{
          colorScheme: isDark ? "dark" : "light",
          backgroundImage: activeTheme.page.image,
          minHeight: "100vh",
        }}
      >
        <BootSpinner />
      </FluentProvider>
    );
  }

  // A module may want the whole screen for a path -- a deck is a room of its
  // own, not a card under the nav bar. The routes still come from the registry;
  // only the chrome around them is left off.
  if (isChromeless(active, location.pathname)) {
    return (
      <FluentProvider theme={fluentTheme}>
        <ShellProvider value={shellValue}>
          <Routes>
            {routes.map((route) => (
              <Route key={String(route.path)} path={route.path} element={route.element} />
            ))}
          </Routes>
        </ShellProvider>
      </FluentProvider>
    );
  }

  return (
    <FluentProvider
      theme={fluentTheme}
      style={{
        colorScheme: isDark ? "dark" : "light",
        backgroundImage: activeTheme.page.image,
        minHeight: "100vh",
      }}
    >
      {/* A skin the Lounge granted toolkit-wide (D-L11): worn as the first
          fixed layer, so it paints OVER the provider's theme background and
          UNDER everything after it -- the grain keeps its texture above the
          water, and .root's position:relative lifts every page above both.
          The shell WEARS, it never chooses, and with no grant written this
          renders nothing at all. */}
      <GrantedSkin />
      <div
        aria-hidden="true"
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundImage: `url("${noiseSvgUrl}")`,
          backgroundRepeat: "repeat",
          backgroundSize: "50px",
          mixBlendMode: "soft-light",
          opacity: activeTheme.grain,
          pointerEvents: "none",
        }}
      />
      <div className={styles.root}>
        <a href="#main" className={styles.skipLink}>
          Skip to content
        </a>
        <header className={styles.nav}>
          <div
            className={styles.navSlot}
            style={{
              display: "flex",
              alignItems: "center",
              gap: tokens.spacingHorizontalS,
            }}
          >
            <ToolKitLogo />
          </div>
          <nav className={styles.navLinks} aria-label="Main">
            {/* The Space anchor IS Home: the display name on its
                face, the slug in its tooltip -- the slug stays in the avatar
                menu, the hub folder and every verb. Then a rule, then yours. */}
            {homeEntry ? (
              <>
                <SpaceAnchor
                  entry={homeEntry}
                  here={homeEntry.match(location.pathname)}
                  config={env?.config}
                  onNavigate={navigate}
                />
                {navTabs.length > 0 ? (
                  <span aria-hidden="true" data-nav-divider="" className={styles.navDivider} />
                ) : null}
              </>
            ) : null}
            {navTabs.map((entry) => {
              const here = entry.match(location.pathname);
              // ONE element: a link that looks like the button. It used to be a
              // Button inside a Link -- two tab stops each, and a button nested
              // in an anchor. A plain click routes in place; a modified click
              // (new tab) is left to the browser, which is what a link is for.
              return (
                <Button
                  key={entry.to}
                  as="a"
                  href={entry.to}
                  aria-current={here ? "page" : undefined}
                  appearance={here ? "primary" : "subtle"}
                  size="small"
                  onClick={(e: React.MouseEvent) => {
                    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
                    e.preventDefault();
                    navigate(entry.to);
                  }}
                >
                  {entry.label}
                </Button>
              );
            })}
          </nav>
          {/* The header holds what is true on EVERY page: the brand, the org,
              where you can go, and you. The card pager used to sit here on Home
              only -- an unlabelled "1 / 3" -- and is under the cards it pages now. */}
          <div className={styles.navPager}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: "1rem",
                marginLeft: "1rem",
              }}
            >
              {/* A module's header signals, left of "me" and 1rem from it -- the
                  reminder bell. */}
              {headerItems}
              {/* "Me and my settings." A menu, not a toggle: theme and
                  organisation change in place, and every other entry opens the
                  drawer AT a place the registry named. Who this is comes from
                  /env, not from source -- a name in a committed file is the
                  defect the Portability suite exists to catch (spec S8.7). */}
              <AvatarMenu
                displayName={env?.displayName}
                detail={[env?.identity?.email, env?.config?.activeSpace]
                  .filter(Boolean)
                  .join(" · ")}
                unsaved={unsaved}
                spaces={(env?.config?.spaces ?? []).map((o) => ({
                  slug: o.slug,
                  name: o.name ?? o.slug,
                }))}
                activeSpace={env?.config?.activeSpace ?? ""}
                onSwitchSpace={(slug) => void switchMode({ mode: slug })}
                links={settingsLinks}
                onOpenSettings={openSettings}
                restoreFocusTarget={restoreFocusTarget}
              />
            </div>
          </div>
        </header>

        <main id="main" tabIndex={-1} className={styles.main}>
          {agentAway && !env ? (
            <AgentUnreachable onRetry={checkAgent} retrying={heartbeatFetching || envFetching} />
          ) : (
            <ShellProvider value={shellValue}>
              {agentAway ? (
                <AgentLostBanner onRetry={checkAgent} retrying={heartbeatFetching || envFetching} />
              ) : null}
              <Routes>
                {routes.map((route) => (
                  <Route key={String(route.path)} path={route.path} element={route.element} />
                ))}
                <Route
                  path="*"
                  element={
                    <NotFound
                      pathname={location.pathname}
                      dormant={dormant}
                      onOpenSettings={() =>
                        openSettings(dormant?.feature ? `features.${dormant.feature}` : undefined)
                      }
                    />
                  }
                />
              </Routes>
            </ShellProvider>
          )}
        </main>
      </div>

      {/* Every section is contributed by a module through the registry, gated
          by that module's flag like its cards are -- the shell does not know
          what they are. Today that is one: the ADO core's Configuration. */}
      <SettingsDrawer
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        theme={activeTheme}
        anchor={settingsAnchor.at}
        anchorRequest={settingsAnchor}
      >
        {/* The shell's own section, first: the one setting that is about the
            page you are looking at. Module sections follow, from the registry. */}
        <ThemePicker />
        {settingsSections}
      </SettingsDrawer>
    </FluentProvider>
  );
}

export default App;
