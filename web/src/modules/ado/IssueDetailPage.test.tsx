import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { IssueDetailPage } from "./IssueDetailPage";
import type { IssueDetail } from "./api.ado";
import { VISIBILITY } from "../../shell/consts";

// The reading room's shell half. The agent's mapping is pinned in
// Tests/test_issue_detail.py; here the page: body, thread, timeline, the two
// act-in-place actions, and the two ways it says no. The page is the house
// reading frame -- ONE MarkdownViewer holds body, thread and timeline, so the
// mock renders what it was handed and the tests read that. The house viewer is
// mocked because react-markdown is ESM (the registry tests' rule), and the
// ActionDialog because its wiring is MyWork's test's subject, not this one's.
jest.mock("../../shared/MarkdownViewer", () => ({
  MarkdownViewer: ({ content }: { content: string }) => <pre data-testid="viewer">{content}</pre>,
}));
jest.mock("./ActionDialog", () => ({
  ActionDialog: () => null,
}));
// The Space's repository visibility. Private by default: the line is the
// last tests' subject.
let visibility = "private";
jest.mock("../../shell/api", () => ({
  useGetSpaceVisibilityQuery: () => ({ data: { supported: true, visibility, repos: [] } }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
}));

const answer: { data?: IssueDetail; isLoading: boolean; error?: unknown } = {
  isLoading: false,
};
jest.mock("./api.ado", () => ({
  useGetIssueDetailQuery: () => ({ ...answer, refetch: jest.fn() }),
  useEditWorkItemMutation: () => [jest.fn(), { isLoading: false }],
}));

const DETAIL: IssueDetail = {
  supported: true,
  number: 60,
  title: "Feature: issue details in the GUI",
  state: "open",
  body: "The body, **markdown**.",
  author: "johnfrog76",
  created: "2026-09-27",
  closed: "",
  url: "https://github.com/johnfrog76/toolkit/issues/60",
  labels: ["enhancement", "sev2"],
  kind: "Feature",
  milestone: "Milestone P",
  assignee: "johnfrog76",
  repo: "toolkit",
  comments: [{ author: "opus", when: "2026-09-27", body: "First comment." }],
  timeline: [
    {
      kind: "commit",
      text: "abc1234",
      url: "https://github.com/x/commit/abc1234",
      when: "2026-09-27",
    },
    {
      kind: "pr",
      text: "#58 The backlog PR",
      url: "https://github.com/x/pull/58",
      when: "2026-09-27",
    },
  ],
  reason: null,
};

function mount() {
  return render(
    <MemoryRouter initialEntries={["/issue/60?repo=toolkit"]}>
      <Routes>
        <Route path="/issue/:num" element={<IssueDetailPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the reading room", () => {
  it("shows the body, the thread and the timeline's high signal", () => {
    answer.data = DETAIL;
    answer.error = undefined;
    mount();
    expect(screen.getByText(/#60 Feature: issue details/)).toBeTruthy();
    // one document, one viewer: the body, then the thread, then the timeline
    const viewers = screen.getAllByTestId("viewer");
    expect(viewers).toHaveLength(1);
    const doc = viewers[0].textContent ?? "";
    expect(doc).toContain("The body, **markdown**.");
    expect(doc).toContain("## 1 comment\n\n### opus -- 2026-09-27\n\nFirst comment.");
    expect(doc).toContain("## Timeline");
    expect(doc).toContain("- (pr) [#58 The backlog PR](https://github.com/x/pull/58) 2026-09-27");
    expect(doc.indexOf("The body")).toBeLessThan(doc.indexOf("## Timeline"));
    // the chip grammar worn as badges (the owner: "parenthetical can be badges")
    expect(screen.getByText("gh")).toBeTruthy();
    expect(screen.getByText("feat")).toBeTruthy();
    expect(screen.getAllByText("sev2").length).toBeGreaterThan(0);
    // read, then act, one place -- and the way back
    expect(screen.getByText("Make a card")).toBeTruthy();
    // compact, as the 1:1 page's header: icons with a title, words on the one step
    expect(screen.getByTitle("Close issue")).toBeTruthy();
    expect(screen.getByTitle("Open on GitHub").getAttribute("href")).toBe(DETAIL.url);
    expect(screen.getByTitle("Refresh")).toBeTruthy();
    // the record's address, the shared line every detail page carries
    expect(screen.getByTestId("file-path").textContent).toContain(DETAIL.url);
    expect(screen.getByRole("button", { name: "Copy the issue link" })).toBeTruthy();
    expect(screen.getByTitle("Back")).toBeTruthy();
    expect(screen.getByLabelText("Severity")).toBeTruthy();
  });

  it("an unsupported space says so instead of pretending", () => {
    answer.data = { ...DETAIL, supported: false };
    mount();
    expect(screen.getByText(/does not read issues/)).toBeTruthy();
    expect(screen.queryByText("Make a card")).toBeNull();
    expect(screen.queryByTestId("viewer")).toBeNull();
  });

  it("an issue with no body says so, in the document", () => {
    answer.data = { ...DETAIL, body: "", comments: [], timeline: [] };
    mount();
    expect(screen.getByTestId("viewer").textContent).toMatch(/has no body/);
  });

  // The tracker's own pin, beside the state, with the same Pin / Unpin
  // the row's menu holds -- a closed issue still pinned keeps its Unpin.
  it("a pinned issue says Pinned on GitHub beside its state, and offers Unpin -- open or closed", () => {
    for (const state of ["open", "closed"]) {
      answer.data = { ...DETAIL, state, pinned: true };
      const { unmount } = mount();
      expect(screen.getByText("Pinned on GitHub")).toBeTruthy();
      expect(screen.getByTitle("Unpin")).toBeTruthy();
      expect(screen.queryByTitle("Pin on GitHub")).toBeNull();
      unmount();
    }
  });

  it("an unpinned issue offers Pin on GitHub and says nothing of a pin", () => {
    answer.data = { ...DETAIL, pinned: false };
    mount();
    expect(screen.queryByText("Pinned on GitHub")).toBeNull();
    expect(screen.getByTitle("Pin on GitHub")).toBeTruthy();
  });

  it("a stated reason is shown as the sentence it is", () => {
    answer.data = { ...DETAIL, reason: "toolkit: gh did not answer (TimeoutExpired)" };
    mount();
    expect(screen.getByText(/gh did not answer/)).toBeTruthy();
  });

  // On stage: the room's actions write to the Space's repository, so a
  // public one says so, once, under the issue's address; nothing is asked.
  it.each([
    ["public", 1],
    ["private", 0],
    ["unknown", 0],
  ] as const)("a %s repository: the public line %i times", (v, n) => {
    visibility = v;
    answer.data = DETAIL;
    mount();
    expect(screen.queryAllByText(VISIBILITY.publicLine)).toHaveLength(n);
  });
});
