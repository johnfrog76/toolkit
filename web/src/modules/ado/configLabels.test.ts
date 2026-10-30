import { NAMED_SCHEMA_KEYS, schemaKeyOf, wordsFor } from "./configLabels";

describe("configLabels", () => {
  it("names a plain key, and says it did", () => {
    const words = wordsFor("email", "schema help");
    expect(words.named).toBe(true);
    expect(words.label).toBe("Your work email");
    expect(words.hint).not.toBe("schema help");
  });

  it("names an org's field whatever the org is called", () => {
    expect(schemaKeyOf("spaces.demo.features.sprintAwareness")).toBe(
      "spaces.<slug>.features.sprintAwareness",
    );
    expect(wordsFor("spaces.acme.status", "").label).toBe("Status");
  });

  // The string pass: the Space's address and status name EITHER tracker --
  // the address decides which (D-G2) -- so neither reads as Azure DevOps only.
  it("a Space's address and status name either tracker", () => {
    expect(wordsFor("spaces.acme.org", "").label).toBe("Tracker address");
    expect(wordsFor("spaces.acme.org", "").hint).toMatch(/GitHub/);
    expect(wordsFor("spaces.acme.status", "").hint).toMatch(/GitHub or Azure DevOps/);
    expect(wordsFor("spaces.acme.features.sprintAwareness", "").hint).not.toMatch(/board/);
  });

  it("a shortcut's label carries the shortcut's own name", () => {
    expect(wordsFor("aliases.Hub.path", "").label).toBe("Shortcut: Hub");
  });

  // A key nobody has named yet must still be usable: its own name, the schema's
  // help. Hidden-until-named would make every new config key a web change.
  it("falls back to the key and the schema's help", () => {
    expect(wordsFor("brand.new.key", "What the schema says.")).toEqual({
      label: "brand.new.key",
      hint: "What the schema says.",
      named: false,
    });
  });

  // The owner's rule: a person chooses to HIDE things, so both first-run
  // switches read "Hide ...". The banner's key is named for showing it, so its
  // switch is drawn inverted; isDemoDismissed already means "hidden".
  it("the two first-run switches are named for hiding, and only the banner's is inverted", () => {
    expect(wordsFor("isDemoDismissed", "")).toMatchObject({ label: "Hide Demo" });
    expect(wordsFor("isDemoDismissed", "").inverted).toBeFalsy();
    expect(wordsFor("firstRun.welcome", "")).toMatchObject({
      label: "Hide Overview Deck",
      inverted: true,
    });
  });

  // A Space's checkout (#146) is keyed by its slug, like a Space's own fields.
  it("names a Space's checkout by its pattern", () => {
    expect(schemaKeyOf("spaceCheckouts.toolkit.path")).toBe("spaceCheckouts.<slug>.path");
    expect(wordsFor("spaceCheckouts.toolkit.path", "")).toMatchObject({
      label: "This Space's checkout",
      named: true,
    });
  });

  it("every label and hint is a sentence a person can read", () => {
    for (const key of NAMED_SCHEMA_KEYS) {
      const { label, hint } = wordsFor(key.replace("<slug>", "x").replace("<name>", "X"), "");
      expect(label).not.toMatch(/[<>{}]|\.\w/); // no key syntax leaking into a label
      expect(hint.length).toBeGreaterThan(20);
      expect(hint).toMatch(/\.$/);
    }
  });
});
