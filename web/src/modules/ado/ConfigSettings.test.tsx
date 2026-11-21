import { fireEvent, render, screen } from "@testing-library/react";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import { ConfigSettings, FieldRow } from "./ConfigSettings";
import { SettingsFooterContext } from "../../shell/settings";
import type { ConfigSchemaRow, ConfigSetting } from "./api.ado";
import { RITUALS } from "../../shell/consts";

// A field with a short list of allowed values is a select whatever its type,
// and one that is not required offers its way back to unset, first.

const teamSizeRow: ConfigSchemaRow = {
  key: "spaces.<slug>.features.teamSize",
  scope: "org",
  type: "int",
  allowed: RITUALS.teamSizes.map(String),
  required: false,
  file: "hub.json",
  help: "How many developers attend standup?",
};

const statusRow: ConfigSchemaRow = {
  key: "spaces.<slug>.status",
  scope: "org",
  type: "enum",
  allowed: ["active", "local", "archive"],
  required: false,
  file: "hub.json",
  help: "active runs Tier 1.",
};

function setting(key: string, value: string, source: ConfigSetting["source"]): ConfigSetting {
  return { key, scope: "org", file: "hub.json", value, source };
}

function mount(props: Parameters<typeof FieldRow>[0]) {
  return render(
    <FluentProvider theme={webLightTheme}>
      <FieldRow {...props} />
    </FluentProvider>,
  );
}

const defaultText = `Default (${RITUALS.teamSizeDefault})`;

describe("FieldRow: a field with allowed values", () => {
  it("draws an int with allowed values as a select, reading Default while unset", () => {
    mount({
      setting: setting("spaces.acme.features.teamSize", "", "unset"),
      row: teamSizeRow,
      draft: undefined,
      onChange: () => {},
    });
    const select = screen.getByRole("combobox");
    expect(select.textContent).toBe(defaultText);
    expect(screen.queryByRole("textbox")).toBeNull();
    // The row still says nobody has set it.
    expect(screen.getByText("unset")).toBeTruthy();
  });

  it("offers Default first, then every allowed value", () => {
    mount({
      setting: setting("spaces.acme.features.teamSize", "6", "hub"),
      row: teamSizeRow,
      draft: undefined,
      onChange: () => {},
    });
    fireEvent.click(screen.getByRole("combobox"));
    const options = screen.getAllByRole("option").map((o) => o.textContent);
    expect(options).toEqual([defaultText, ...RITUALS.teamSizes.map(String)]);
  });

  it("choosing Default hands the form an empty value, which the save sends as an unset", () => {
    const onChange = jest.fn();
    mount({
      setting: setting("spaces.acme.features.teamSize", "6", "hub"),
      row: teamSizeRow,
      draft: undefined,
      onChange,
    });
    fireEvent.click(screen.getByRole("combobox"));
    fireEvent.click(screen.getByRole("option", { name: defaultText }));
    expect(onChange).toHaveBeenCalledWith("");
  });

  it("a required field has no Default entry", () => {
    mount({
      setting: setting("spaces.acme.features.teamSize", "6", "hub"),
      row: { ...teamSizeRow, required: true },
      draft: undefined,
      onChange: () => {},
    });
    fireEvent.click(screen.getByRole("combobox"));
    expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual(
      RITUALS.teamSizes.map(String),
    );
  });

  it("an enum's select is unchanged: its allowed values only", () => {
    mount({
      setting: setting("spaces.acme.status", "active", "hub"),
      row: statusRow,
      draft: undefined,
      onChange: () => {},
    });
    const select = screen.getByRole("combobox");
    expect(select.textContent).toBe("active");
    fireEvent.click(select);
    expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual(statusRow.allowed);
  });
});

// The whole section, with the agent stood in: what each save sends, and the
// re-read list the write hands back is what the rows draw afterwards. A Space
// field the hub holds is unset with -Hub, in its own write -- without it the
// verb removes only this machine's patch and the save changes nothing.
const teamKey = "spaces.acme.features.teamSize";
const hoursKey = "spaces.acme.features.trainingHoursPerQuarter";
const hoursRow: ConfigSchemaRow = {
  key: "spaces.<slug>.features.trainingHoursPerQuarter",
  scope: "org",
  type: "int",
  allowed: [],
  required: false,
  file: "hub.json",
  help: "Training hours each quarter.",
};
const emailRow: ConfigSchemaRow = {
  key: "email",
  scope: "machine",
  type: "string",
  allowed: [],
  required: false,
  file: "config.local.json",
  help: "Your work email.",
};
const machine = (key: string, value: string, source: ConfigSetting["source"]): ConfigSetting => ({
  key,
  scope: "machine",
  file: "config.local.json",
  value,
  source,
});

let configReply: { settings: ConfigSetting[] } = { settings: [] };
let schemaRows: ConfigSchemaRow[] = [];
const writeConfig = jest.fn();

jest.mock("./api.ado", () => ({
  useGetConfigQuery: () => ({ data: { activeSpace: "acme", ...configReply }, isLoading: false }),
  useGetConfigSchemaQuery: () => ({ data: { schema: schemaRows, error: null } }),
  useWriteConfigMutation: () => [writeConfig, { isLoading: false }],
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { spaces: [] } } }),
}));

function reply(status: "success" | "error", after?: ConfigSetting[]) {
  return () => {
    if (after) configReply = { settings: after };
    return {
      unwrap: () =>
        Promise.resolve({
          result: { status, error: status === "error" ? "Refused." : null },
          config: configReply,
        }),
    };
  };
}

function section() {
  const footer = document.createElement("div");
  document.body.appendChild(footer);
  const tree = () => (
    <FluentProvider theme={webLightTheme}>
      <SettingsFooterContext.Provider value={footer}>
        <ConfigSettings />
      </SettingsFooterContext.Provider>
    </FluentProvider>
  );
  const view = render(tree());
  return { rerender: () => view.rerender(tree()) };
}

/** The control a row draws, found by the label that names it. */
function controlFor(key: string): HTMLElement {
  const id = `cfg-${key.replace(/[^A-Za-z0-9]+/g, "-")}-label`;
  const el = document.querySelector<HTMLElement>(`[aria-labelledby="${id}"]`);
  if (!el) throw new Error(`no control for ${key}`);
  return el;
}

function clear(key: string) {
  fireEvent.change(controlFor(key), { target: { value: "" } });
}

describe("ConfigSettings: what a save sends", () => {
  beforeEach(() => {
    writeConfig.mockReset();
  });
  afterEach(() => {
    // The drafts outlive the component on purpose; a test must not leak them.
    const discard = screen.queryByRole("button", { name: "Discard" });
    if (discard) fireEvent.click(discard);
  });

  it("choosing Default on a hub-held select is an unset with -Hub, and the row reads unset", async () => {
    schemaRows = [teamSizeRow];
    configReply = { settings: [setting(teamKey, "6", "hub")] };
    writeConfig.mockImplementation(reply("success", [setting(teamKey, "", "unset")]));
    const view = section();
    fireEvent.click(controlFor(teamKey));
    fireEvent.click(screen.getByRole("option", { name: defaultText }));
    fireEvent.click(await screen.findByRole("button", { name: "Save 1" }));
    await screen.findByText("Saved.", { exact: false });

    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: {}, unset: [teamKey], hub: true });

    view.rerender();
    expect(controlFor(teamKey).textContent).toBe(defaultText);
    expect(screen.getByText("unset")).toBeTruthy();
  });

  it("clearing a hub-held text field is an unset with -Hub", async () => {
    schemaRows = [hoursRow];
    configReply = { settings: [setting(hoursKey, "8", "hub")] };
    writeConfig.mockImplementation(reply("success", [setting(hoursKey, "", "unset")]));
    section();
    clear(hoursKey);
    fireEvent.click(await screen.findByRole("button", { name: "Save 1" }));
    await screen.findByText("Saved.", { exact: false });

    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: {}, unset: [hoursKey], hub: true });
  });

  it("clearing a machine key is an unset without -Hub", async () => {
    schemaRows = [emailRow];
    configReply = { settings: [machine("email", "a@example.com", "local")] };
    writeConfig.mockImplementation(reply("success", [machine("email", "", "unset")]));
    section();
    clear("email");
    fireEvent.click(await screen.findByRole("button", { name: "Save 1" }));
    await screen.findByText("Saved.", { exact: false });

    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: {}, unset: ["email"] });
  });

  it("a mixed save is two writes: the rest first, then the hub's unsets with -Hub", async () => {
    schemaRows = [emailRow, hoursRow];
    configReply = {
      settings: [machine("email", "a@example.com", "local"), setting(hoursKey, "8", "hub")],
    };
    writeConfig.mockImplementation(reply("success"));
    section();
    clear("email");
    clear(hoursKey);
    fireEvent.click(await screen.findByRole("button", { name: "Save 2" }));
    await screen.findByText("Saved.", { exact: false });

    expect(writeConfig.mock.calls).toEqual([
      [{ set: {}, unset: ["email"] }],
      [{ set: {}, unset: [hoursKey], hub: true }],
    ]);
  });

  it("a refusal stops the batch and keeps every draft", async () => {
    schemaRows = [emailRow, hoursRow];
    configReply = {
      settings: [machine("email", "a@example.com", "local"), setting(hoursKey, "8", "hub")],
    };
    writeConfig.mockImplementation(reply("error"));
    section();
    clear("email");
    clear(hoursKey);
    fireEvent.click(await screen.findByRole("button", { name: "Save 2" }));
    await screen.findByText("Refused.", { exact: false });

    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: {}, unset: ["email"] });
    expect(screen.getByRole("button", { name: "Save 2" })).toBeTruthy();
  });
});
