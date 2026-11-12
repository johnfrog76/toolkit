import { render } from "@testing-library/react";
import type { ReactElement } from "react";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import { VisibilityBadge } from "../shared/visibility";
import { FieldRow } from "../modules/ado/ConfigSettings";
import type { ConfigSetting } from "../modules/ado/api.ado";

// Badges whose appearance or colour is computed, which badgeContrast.test.ts
// cannot read from the source. Each one is mounted and every Badge it draws is
// read through a recording wrapper. This covers the computed sites by name,
// not every Badge in the app.
const seen: { appearance?: string; color?: string; text: string }[] = [];

jest.mock("@fluentui/react-components", () => {
  const actual = jest.requireActual("@fluentui/react-components");
  const Real = actual.Badge;
  const React = jest.requireActual("react");
  return {
    ...actual,
    Badge: (props: { appearance?: string; color?: string; children?: unknown }) => {
      seen.push({
        appearance: props.appearance,
        color: props.color,
        text: String(props.children ?? ""),
      });
      return React.createElement(Real, props);
    },
  };
});

function mount(node: ReactElement) {
  seen.length = 0;
  render(<FluentProvider theme={webLightTheme}>{node}</FluentProvider>);
  return [...seen];
}

const setting = (source: ConfigSetting["source"]): ConfigSetting => ({
  key: "email",
  scope: "machine",
  file: "config.local.json",
  value: "",
  source,
});

function expectReadable(badges: { appearance?: string; color?: string }[]) {
  expect(badges.length).toBeGreaterThan(0);
  for (const b of badges) {
    expect(b.appearance === "outline" && b.color === "subtle").toBe(false);
  }
}

describe("computed badges are never outline with the subtle colour", () => {
  it.each(["public", "PRIVATE", "internal", "unknown"])("VisibilityBadge %s", (v) => {
    expectReadable(mount(<VisibilityBadge visibility={v} />));
  });

  it("a private repository is a subtle tint", () => {
    expect(mount(<VisibilityBadge visibility="PRIVATE" />)[0]).toMatchObject({
      appearance: "tint",
      color: "subtle",
    });
  });

  it.each(["default", "hub", "local", "env", "unset"] as const)("Settings source %s", (source) => {
    const badges = mount(
      <FieldRow setting={setting(source)} row={undefined} draft={undefined} onChange={() => {}} />,
    );
    expectReadable(badges.filter((b) => b.text === source));
  });

  it("an unset setting's source badge is a subtle tint", () => {
    const badges = mount(
      <FieldRow setting={setting("unset")} row={undefined} draft={undefined} onChange={() => {}} />,
    );
    expect(badges.find((b) => b.text === "unset")).toMatchObject({
      appearance: "tint",
      color: "subtle",
    });
  });
});
