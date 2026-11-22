import fs from "fs";
import path from "path";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SIGN_IN } from "./consts";
import type { EnvStatus } from "./api";
import { SignInStrip, signInCommand } from "./SignInStrip";

// "Sign in to Azure DevOps" (docs/modules/ado.md, "Signing in"): shown in ONE state,
// neutral in style, and it only shows the command -- the app never signs in.
const refresh = jest.fn();
jest.mock("./api", () => ({
  useRefreshEnvMutation: () => [refresh, { isLoading: false }],
}));

const COMMAND = SIGN_IN.azCommand;
const sign = (
  needed: boolean,
  installed: boolean | null,
  signedIn: boolean | null,
): NonNullable<EnvStatus["azSignIn"]> => ({ needed, installed, signedIn, command: COMMAND });
const envWith = (azSignIn: EnvStatus["azSignIn"]) => ({ azSignIn }) as unknown as EnvStatus;

beforeEach(() => {
  refresh.mockReset();
  Object.assign(navigator, { clipboard: { writeText: jest.fn().mockResolvedValue(undefined) } });
});

describe("the sign-in strip, by the state the agent reports", () => {
  it.each<[string, EnvStatus | undefined, boolean]>([
    // The agent derives `needed`; each row is what it sends for that state.
    ["Azure DevOps, active, az signed out", envWith(sign(true, true, false)), true],
    ["Azure DevOps, active, az signed in", envWith(sign(false, true, true)), false],
    ["Azure DevOps, active, az not installed", envWith(sign(false, false, null)), false],
    ["a local Space (az is not asked)", envWith(sign(false, null, null)), false],
    ["a GitHub Space (az is not asked)", envWith(sign(false, null, null)), false],
    ["an older agent that serves no field", envWith(undefined), false],
    ["no env yet", undefined, false],
  ])("%s", (_name, env, shown) => {
    render(<SignInStrip env={env} />);
    expect(screen.queryByTestId("sign-in-strip") !== null).toBe(shown);
    expect(signInCommand(env) !== null).toBe(shown);
  });
});

describe("the sign-in strip, drawn", () => {
  it("names the exact command the contract holds, with Copy and Check again", async () => {
    render(<SignInStrip env={envWith(sign(true, true, false))} />);
    expect(screen.getByText("Sign in to Azure DevOps.")).toBeTruthy();
    expect(screen.getByText(COMMAND)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Copy" }));
    await waitFor(() => expect(navigator.clipboard.writeText).toHaveBeenCalledWith(COMMAND));
  });

  it("Check again asks the agent to probe again, once, and does nothing else", () => {
    render(<SignInStrip env={envWith(sign(true, true, false))} />);
    fireEvent.click(screen.getByRole("button", { name: "Check again" }));
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it("is informational: a status, never an alert", () => {
    render(<SignInStrip env={envWith(sign(true, true, false))} />);
    expect(screen.getByRole("status")).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("is in the neutral style: no error, danger, warning or yellow colour in its source", () => {
    const source = fs.readFileSync(path.join(__dirname, "SignInStrip.tsx"), "utf8");
    const code = source
      .split("\n")
      .filter((l) => !l.trim().startsWith("//"))
      .join("\n");
    expect(code).not.toMatch(/Danger|Error|Warning|Yellow|Red|Orange|role="alert"/);
    expect(code).toMatch(/colorNeutralBackground3/);
  });

  it("never signs in for you: it holds no way to run a command", () => {
    const source = fs.readFileSync(path.join(__dirname, "SignInStrip.tsx"), "utf8");
    expect(source).not.toMatch(/useRunCommandMutation|cmd\//);
  });
});
