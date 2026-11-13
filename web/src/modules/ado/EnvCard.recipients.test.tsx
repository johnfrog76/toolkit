import { render, screen } from "@testing-library/react";
import { EnvCard } from "./EnvCard";
import { sendButtonState } from "../communication/sendButton";
import { RECIPIENT_STATE_LABEL } from "../communication/recipientState";

// The Environment card lists each Teams recipient /env serves: what it does,
// where it was declared, and its state in a few neutral words. The variable's
// name and the how-to are behind the row's info icon.
let env: Record<string, unknown>;
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: env, isLoading: false, isError: false, isFetching: false }),
  useRefreshEnvMutation: () => [jest.fn(), { isLoading: false }],
  useCheckHubSyncMutation: () => [jest.fn(), { isLoading: false }],
}));
jest.mock("./api.ado", () => ({
  useRunCommandMutation: () => [jest.fn(), { isLoading: false }],
}));

// Set by the stand-in the module-off test registers for the rows' chunk: its
// factory runs only when that chunk is fetched.
let rowsChunkLoaded = false;

const base = {
  os: "Linux",
  uptime: 60,
  tier: 2,
  tierLabel: "Local (Tier 2)",
  spaceStatus: "local",
  container: false,
  machine: "box",
  checks: {},
  config: {},
};
const communication = {
  postRetroSummary: true,
  retroChannel: "manager",
  recipients: [
    {
      key: "manager",
      display: "My Manager (DM via Workflow)",
      type: "channel",
      scope: "managerWorkflow" as const,
      webhookEnv: "TEAMS_WEBHOOK_MANAGER",
      configured: true,
    },
    {
      key: "team",
      display: "Team Channel",
      type: "channel",
      scope: "org" as const,
      webhookEnv: "TEAMS_WEBHOOK_TEAM",
      configured: false,
    },
  ],
};

const MANAGER = "Your manager: Teams direct message";
const TEAM = "Team Channel: Teams post";

/** The row for one recipient, and the text a person reads on it. */
function row(key: string): HTMLElement {
  const el = document.querySelector<HTMLElement>(`[data-recipient="${key}"]`);
  if (!el) throw new Error(`no row for ${key}`);
  return el;
}

/** The how-to behind a row's info icon: the tooltip its icon is described by. */
function howTo(label: string): string {
  const icon = screen.getByRole("img", { name: `About ${label}` });
  const id = icon.getAttribute("aria-describedby") ?? "";
  return document.getElementById(id)?.textContent ?? "";
}

describe("the Environment card's Teams recipients", () => {
  it("titles the section Teams messages and says what each recipient does", async () => {
    env = { ...base, features: { communication: true }, communication };
    render(<EnvCard />);
    expect(await screen.findByText("Teams messages")).toBeTruthy();
    expect(screen.getByText(MANAGER)).toBeTruthy();
    expect(screen.getByText(TEAM)).toBeTruthy();
    expect(screen.getByText("Every Space")).toBeTruthy();
    expect(screen.getByText("This Space")).toBeTruthy();
    // Not the recipient's internal name and route.
    expect(document.body.textContent).not.toContain("DM via Workflow");
  });

  it("reads a recipient whose webhook is set as Ready", async () => {
    env = { ...base, features: { communication: true }, communication };
    render(<EnvCard />);
    await screen.findByText(MANAGER);
    expect(row("manager").dataset.state).toBe("ready");
    expect(row("manager").textContent).toContain("Ready");
    expect(row("manager").textContent).not.toContain("TEAMS_WEBHOOK_MANAGER");
  });

  it("reads an unset recipient as Webhook not set, the variable in the info icon only", async () => {
    env = { ...base, features: { communication: true }, communication };
    render(<EnvCard />);
    await screen.findByText(TEAM);
    expect(row("team").textContent).toContain("Webhook not set");
    // A state, not an instruction, and nothing drawn as an error.
    expect(row("team").textContent).not.toContain("TEAMS_WEBHOOK_TEAM");
    expect(row("team").textContent).not.toMatch(/\bSet\b|✗/);
    expect(howTo(TEAM)).toContain("TEAMS_WEBHOOK_TEAM");
  });

  it("reads every recipient as Sending off on this server where the server says so", async () => {
    env = {
      ...base,
      features: { communication: true },
      communication: { ...communication, sendingOff: true },
    };
    render(<EnvCard />);
    await screen.findByText(MANAGER);
    for (const [key, label] of [
      ["manager", MANAGER],
      ["team", TEAM],
    ]) {
      expect(row(key).textContent).toContain("Sending off on this server");
      expect(row(key).textContent).not.toContain("Webhook not set");
      // Nothing to fix here, so the how-to names no variable.
      expect(howTo(label)).not.toContain("TEAMS_WEBHOOK");
    }
  });

  it("asks a person recipient for no webhook", async () => {
    const person = {
      key: "lead",
      display: "Team Lead",
      type: "person",
      scope: "org" as const,
      webhookEnv: "TEAMS_WEBHOOK_LEAD",
      configured: false,
    };
    env = {
      ...base,
      features: { communication: true },
      communication: { ...communication, recipients: [person] },
    };
    render(<EnvCard />);
    const label = "Team Lead: a person, not posted to";
    expect(await screen.findByText(label)).toBeTruthy();
    expect(row("lead").textContent).toContain("No webhook needed");
    expect(row("lead").textContent).not.toContain("Webhook not set");
    expect(howTo(label)).not.toContain("TEAMS_WEBHOOK_LEAD");
  });

  it.each([
    ["Webhook not set", false, RECIPIENT_STATE_LABEL.unset],
    ["Sending off on this server", true, RECIPIENT_STATE_LABEL.off],
  ])("says %s in the row and on the send button, from one source", async (phrase, off, source) => {
    // The two cannot drift apart: both read recipientState.ts, and this holds
    // what each one shows to the phrase and to each other.
    const block = {
      ...communication,
      sendingOff: off,
      recipients: [{ ...communication.recipients[0], configured: false }],
    };
    env = { ...base, features: { communication: true }, communication: block };
    render(<EnvCard />);
    await screen.findByText(MANAGER);
    const button = sendButtonState(block, { session_stage: "retro" });
    expect(source).toBe(phrase);
    expect(row("manager").textContent).toContain(phrase);
    expect(button.reason).toBe(`${phrase}.`);
    expect(button.info).toBe(howTo(MANAGER));
  });

  it("draws no recipient rows, and fetches none, with the module off", async () => {
    // A fresh registry for the whole render, with a stand-in for the rows'
    // chunk whose factory runs only if this render fetches it. Testing Library
    // registers hooks when it loads, so this test mounts the card itself.
    rowsChunkLoaded = false;
    env = { ...base, features: { communication: false }, communication };
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    const host = document.createElement("div");
    document.body.appendChild(host);
    jest.doMock("../communication/EnvRecipients", () => {
      rowsChunkLoaded = true;
      return { EnvRecipients: () => null };
    });
    await jest.isolateModulesAsync(async () => {
      const React = await import("react");
      const { createRoot } = await import("react-dom/client");
      const { EnvCard: FreshCard } = await import("./EnvCard");
      const root = createRoot(host);
      await React.act(async () => {
        root.render(React.createElement(FreshCard));
        await new Promise((resolve) => setTimeout(resolve, 50));
      });
      expect(host.textContent).toContain("Linux");
      for (const text of [
        "Teams messages",
        "Your manager",
        "Team Channel",
        "Every Space",
        "This Space",
      ]) {
        expect(host.textContent).not.toContain(text);
      }
      await React.act(async () => root.unmount());
    });
    jest.dontMock("../communication/EnvRecipients");
    host.remove();
    expect(rowsChunkLoaded).toBe(false);
  });
});
