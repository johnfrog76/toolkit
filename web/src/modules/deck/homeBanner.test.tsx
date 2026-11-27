import { deckModule } from ".";
import { AZURE_DEMO_SPACE } from "../../shell/consts";
import { HOME_BANNER_SLOT } from "../../shell/slots";
import type { CardContext } from "../../shell/registry";
import type { EnvStatus } from "../../shell/api";

// The first-run banner is the deck module's contribution to Home's slot, and it
// is there only while /env says `firstRunWelcome` -- not before /env answers,
// not after the banner has been answered (the owner: dismissing it
// "writes something to the config so it no longer exists").

function ctx(env: Partial<EnvStatus> | undefined): CardContext {
  return {
    env: env as EnvStatus | undefined,
    filterValue: "",
    stateFilter: "All",
    stateOptions: ["All"],
    activeRepo: null,
    typeFilter: "All",
    linkFilter: "All",
    activeSkillTag: null,
    setActiveSkillTag: () => {},
  };
}

const banner = (env: Partial<EnvStatus> | undefined) =>
  deckModule.slotCards?.[HOME_BANNER_SLOT]?.(ctx(env)) ?? [];
// `org` and `status` are the active Space's own: the unconnected sample is local with no address.
const config = (
  firstRunWelcome?: boolean,
  firstRunPoet?: boolean,
  activeSpace = "demo",
  org: string | null = null,
  status: "active" | "local" = "local",
) =>
  ({
    spaceStatus: status,
    config: {
      org,
      projects: [],
      promptsFolder: "",
      activeSpace,
      spaces: [],
      firstRunWelcome,
      firstRunPoet,
    },
  }) as Partial<EnvStatus>;

describe("the first-run banner", () => {
  it("is absent before /env answers", () => {
    expect(banner(undefined)).toHaveLength(0);
  });

  it("is absent when firstRun.welcome is off or unset -- every machine not started from the sample hub", () => {
    expect(banner(config(false))).toHaveLength(0);
    expect(banner(config(undefined))).toHaveLength(0);
  });

  it("is one element while firstRun.welcome is on", () => {
    expect(banner(config(true))).toHaveLength(1);
  });
});

// The Prompt Poet's offer: the shipped Azure demo Space only, until it is closed,
// and never beside the commercial's.
describe("the Prompt Poet's first-run offer", () => {
  const azure = AZURE_DEMO_SPACE;

  it("shows on the shipped Azure demo Space while firstRun.poet is on", () => {
    expect(banner(config(false, true, azure))).toHaveLength(1);
    expect((banner(config(false, true, azure))[0] as { key: string }).key).toBe(
      "first-run-poet-banner",
    );
  });

  // Connect azure-demo -Address <url> keeps the slug and makes the Space active with an address:
  // a person's real organisation, no longer the sample.
  it("does not show once the sample is connected to an address, active or not", () => {
    expect(banner(config(false, true, azure, "https://dev.azure.com/acme", "active"))).toHaveLength(
      0,
    );
    expect(banner(config(false, true, azure, "https://dev.azure.com/acme", "local"))).toHaveLength(
      0,
    );
  });

  it.each([
    ["the GitHub demo", "github-demo"],
    ["the local demo", "demo"],
    ["a person's own Azure DevOps Space", "acme"],
  ])("does not show on %s", (_name, slug) => {
    expect(banner(config(false, true, slug))).toHaveLength(0);
  });

  it("does not show once closed, or before /env says", () => {
    expect(banner(config(false, false, azure))).toHaveLength(0);
    expect(banner(config(false, undefined, azure))).toHaveLength(0);
  });

  it("waits while the commercial's offer shows, and follows it when that is closed", () => {
    const keyOf = (e: Partial<EnvStatus>) => (banner(e)[0] as { key: string } | undefined)?.key;
    expect(keyOf(config(true, true, azure))).toBe("first-run-banner");
    expect(keyOf(config(true, false, azure))).toBe("first-run-banner");
    expect(keyOf(config(false, true, azure))).toBe("first-run-poet-banner");
    expect(keyOf(config(false, false, azure))).toBeUndefined();
  });
});
