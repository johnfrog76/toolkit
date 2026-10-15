import { deckModule } from ".";
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
const config = (firstRunWelcome?: boolean) =>
  ({
    config: {
      org: null,
      projects: [],
      promptsFolder: "",
      activeSpace: "demo",
      spaces: [],
      firstRunWelcome,
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
