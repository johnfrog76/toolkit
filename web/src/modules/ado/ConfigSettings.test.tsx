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

// The whole section, with the agent stood in: choosing Default for a value the
// hub holds is an unset with -Hub, and the re-read list the write hands back
// is what the row draws afterwards.
const teamKey = "spaces.acme.features.teamSize";
let configReply = { settings: [setting(teamKey, "6", "hub")] };
const writeConfig = jest.fn();

jest.mock("./api.ado", () => ({
  useGetConfigQuery: () => ({ data: { activeSpace: "acme", ...configReply }, isLoading: false }),
  useGetConfigSchemaQuery: () => ({ data: { schema: [teamSizeRow], error: null } }),
  useWriteConfigMutation: () => [writeConfig, { isLoading: false }],
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { config: { spaces: [] } } }),
}));

describe("ConfigSettings: choosing Default", () => {
  it("sends an unset through the hub's writer, and the row reads unset afterwards", async () => {
    writeConfig.mockImplementation(() => {
      configReply = { settings: [setting(teamKey, "", "unset")] };
      return {
        unwrap: () => Promise.resolve({ result: { status: "success" }, config: configReply }),
      };
    });
    const footer = document.createElement("div");
    document.body.appendChild(footer);
    const view = render(
      <FluentProvider theme={webLightTheme}>
        <SettingsFooterContext.Provider value={footer}>
          <ConfigSettings />
        </SettingsFooterContext.Provider>
      </FluentProvider>,
    );
    fireEvent.click(screen.getAllByRole("combobox")[0]);
    fireEvent.click(screen.getByRole("option", { name: defaultText }));
    fireEvent.click(await screen.findByRole("button", { name: "Save 1" }));
    await screen.findByText("Saved.", { exact: false });

    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: {}, unset: [teamKey], hub: true });

    view.rerender(
      <FluentProvider theme={webLightTheme}>
        <SettingsFooterContext.Provider value={footer}>
          <ConfigSettings />
        </SettingsFooterContext.Provider>
      </FluentProvider>,
    );
    expect(screen.getAllByRole("combobox")[0].textContent).toBe(defaultText);
    expect(screen.getByText("unset")).toBeTruthy();
  });
});
