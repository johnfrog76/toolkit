/**
 * A review card printed the org's SLUG raw ("initech") where a person
 * reads a name -- a file/storage fact standing in for the thing the card is
 * about.
 * `orgDisplayName` is the lookup the card renders instead.
 */
import { orgDisplayName } from "./ReviewArchive";
import type { SpaceInfo } from "../../shell/api";

const orgs = [
  { slug: "initech", name: "Initech Systems" },
  { slug: "globex", name: "Globex Corporation" },
] as SpaceInfo[];

describe("orgDisplayName", () => {
  it("resolves a known slug to the board's own name", () => {
    expect(orgDisplayName("initech", orgs)).toBe("Initech Systems");
  });

  it("falls back to the slug for an org this machine no longer configures", () => {
    expect(orgDisplayName("retired-client", orgs)).toBe("retired-client");
  });
});
