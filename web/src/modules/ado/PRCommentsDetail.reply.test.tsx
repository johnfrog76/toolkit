import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { PRCommentsDetail, REPLY_STATUSES, statusFor } from "./PRCommentsDetail";
import type { DetailResponse } from "./api.ado";

// The reply box: an open thread with no reply in the card gets a box,
// Suggest a reply fills it from the agent's model route, and Post reply runs
// ReplyPR through the bridge -- the card's one writer. The page never calls
// a native save route, because there is none. react-markdown is ESM (the
// registry tests' rule), so it is mocked; so are the two API slices.
jest.mock("react-markdown", () => ({
  __esModule: true,
  default: ({ children }: { children: string }) => <div>{children}</div>,
}));
jest.mock("remark-gfm", () => ({ __esModule: true, default: () => null }));
// The web-side error log posts with fetch, which jsdom does not have.
jest.mock("./logError", () => ({ logWebError: jest.fn() }));

const env: { anthropicConfigured: boolean } = { anthropicConfigured: true };
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: env, isLoading: false }),
}));

const runCommand = jest.fn();
const suggestReply = jest.fn();
const refetch = jest.fn();
const answer: { data?: DetailResponse; isLoading: boolean } = { isLoading: false };
jest.mock("./api.ado", () => ({
  useGetPrCommentDetailQuery: () => ({ ...answer, isError: false, isFetching: false, refetch }),
  useRunCommandMutation: () => [runCommand],
  useSuggestReplyMutation: () => [suggestReply],
}));

const OPEN = {
  number: 1,
  thread_id: 5000002,
  file_path: "/src/Carousel.tsx",
  line: 18,
  reviewer: "bot",
  severity: "minor",
  category: "style",
  status: "active",
  comment_text: "Use const.",
  code_suggestion: "",
  decision: "take / reject / modify",
  reply: "",
  is_open: true,
};
const TRIAGED = {
  ...OPEN,
  number: 2,
  thread_id: 5000003,
  comment_text: "Rename it.",
  decision: "take",
  reply: "Renamed in 1234567.",
};

function mount() {
  answer.data = {
    file: "Task1-card.prompt.md",
    title: "The card",
    pr_id: 77,
    round_num: 1,
    open_count: 2,
    total_count: 2,
    comments: [OPEN, TRIAGED],
  };
  return render(
    <MemoryRouter initialEntries={["/pr-comments/Task1-card.prompt.md"]}>
      <Routes>
        <Route path="/pr-comments/:filename" element={<PRCommentsDetail hideGuide />} />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(() => {
  env.anthropicConfigured = true;
  runCommand.mockReset();
  suggestReply.mockReset();
  refetch.mockReset();
});

describe("the reply box", () => {
  it("an open thread with no reply gets the box; a triaged one keeps Resolve", () => {
    mount();
    expect(screen.getByTestId("reply-box-5000002")).toBeTruthy();
    expect(screen.queryByTestId("reply-box-5000003")).toBeNull();
    expect(screen.getByRole("button", { name: /resolve/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /suggest a reply/i })).toBeTruthy();
  });

  it("Suggest a reply fills the draft from the model's answer and maps the status", async () => {
    suggestReply.mockReturnValue({
      unwrap: () =>
        Promise.resolve({
          recommendation: "reject",
          confidence: "medium",
          draft_reply: "Leaving as is.",
        }),
    });
    mount();
    fireEvent.click(screen.getByRole("button", { name: /suggest a reply/i }));
    await waitFor(() =>
      expect((screen.getByLabelText("Reply to comment 1") as HTMLTextAreaElement).value).toBe(
        "Leaving as is.",
      ),
    );
    expect(suggestReply).toHaveBeenCalledWith({
      filename: "Task1-card.prompt.md",
      body: {
        thread_id: 5000002,
        comment_text: "Use const.",
        file_path: "/src/Carousel.tsx",
        line: 18,
        reviewer: "bot",
        code_suggestion: "",
      },
    });
    expect(screen.getByText(/Suggested: reject \(medium confidence\)/)).toBeTruthy();
    expect(screen.getByRole("combobox", { name: "Status for comment 1" }).textContent).toContain(
      "wontFix",
    );
  });

  it("Post reply runs ReplyPR through the bridge with the draft and the status, then re-reads the card", async () => {
    runCommand.mockReturnValue({ unwrap: () => Promise.resolve({ status: "success" }) });
    mount();
    const post = screen.getByRole("button", { name: /post reply/i }) as HTMLButtonElement;
    expect(post.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("Reply to comment 1"), {
      target: { value: "Done in abc1234." },
    });
    expect(post.disabled).toBe(false);
    fireEvent.click(post);
    await waitFor(() => expect(runCommand).toHaveBeenCalledTimes(1));
    expect(runCommand).toHaveBeenCalledWith({
      name: "ReplyPR",
      params: ["77", "5000002", "-Reply", "Done in abc1234.", "-Status", "fixed"],
    });
    await waitFor(() => expect(screen.getByText(/Reply posted/)).toBeTruthy());
    expect(refetch).toHaveBeenCalled();
    expect(screen.queryByTestId("reply-box-5000002")).toBeNull();
  });

  it("the agent's typed decline is shown as its own sentence", async () => {
    suggestReply.mockReturnValue({
      unwrap: () =>
        Promise.reject({ status: 412, data: { detail: "No model key: set ANTHROPIC_API_KEY" } }),
    });
    mount();
    fireEvent.click(screen.getByRole("button", { name: /suggest a reply/i }));
    await waitFor(() =>
      expect(screen.getByText(/No model key: set ANTHROPIC_API_KEY/)).toBeTruthy(),
    );
  });

  it("with no key the button is absent and the box says what would switch it on", () => {
    env.anthropicConfigured = false;
    mount();
    expect(screen.queryByRole("button", { name: /suggest a reply/i })).toBeNull();
    expect(screen.getByText(/Set ANTHROPIC_API_KEY/)).toBeTruthy();
    expect(screen.getByRole("button", { name: /post reply/i })).toBeTruthy();
  });

  it("the status list is ReplyPR's and the recommendation map is total", () => {
    expect([...REPLY_STATUSES]).toEqual([
      "fixed",
      "active",
      "pending",
      "byDesign",
      "wontFix",
      "closed",
    ]);
    expect(statusFor("take")).toBe("fixed");
    expect(statusFor("reject")).toBe("wontFix");
    expect(statusFor("modify")).toBe("pending");
    expect(statusFor("anything else")).toBe("fixed");
  });
});

// The card's title is the page's one h1 (axe's page-has-heading-one) --
// Title2 kept for its look, marked up as the heading it is.
describe("the page heading", () => {
  it("the card's title is the level-one heading", () => {
    mount();
    expect(screen.getByRole("heading", { level: 1, name: "The card" })).toBeTruthy();
  });
});
