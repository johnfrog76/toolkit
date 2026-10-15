import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import consts from "@consts";
import { STAMPS } from "../../shell/consts";
import { Board } from "./Board";
import { CardPictures, CoverThumb, imageLine } from "./CardCover";
import type { PromptInfo } from "./api.ado";

// Card covers (docs/hub/cards.md, "A card's pictures"): a card's pictures on the board's
// face, in the Home list's meta line and on the card page. The agent serves
// `cover` and `before` as URLs or null; null draws nothing at all.

function card(file: string, name: string, cover?: string | null): PromptInfo {
  return {
    file,
    id: null,
    type: "Task",
    name,
    linked: false,
    tracker: "none",
    billable: true,
    title: name,
    sprint: "--",
    progress: "--",
    checked: 0,
    total: 0,
    modified: "",
    ado_url: null,
    pr_url: null,
    status: "Active",
    ...(cover === undefined ? {} : { cover }),
  };
}

const prompts = [
  card(
    "214-search-duplicates.prompt.md",
    "Search returns duplicates",
    "/api/assets/demo/214/cover.png",
  ),
  card("Task211-extract.prompt.md", "Extract unit conversion", null),
  card("US-216-scale.prompt.md", "Scale by servings"),
];

jest.mock("../../shell/api", () => ({
  // The repository's visibility is the write surfaces' subject, not this one's.
  useGetSpaceVisibilityQuery: () => ({ data: undefined }),
  useRefreshSpaceVisibilityMutation: () => [jest.fn(), { isLoading: false }],
  useGetEnvQuery: () => ({
    data: { tier: 3, tracker: "none", ado: { enabled: false, explicit: false }, config: {} },
  }),
}));
jest.mock("./api.ado", () => {
  const mutation = () => [jest.fn(), { isLoading: false }];
  return {
    useGetStatusQuery: () => ({
      data: { count: prompts.length, prompts },
      isLoading: false,
      isFetching: false,
      isError: false,
      refetch: jest.fn(),
    }),
    useArchivePromptMutation: mutation,
    useMoveCardMutation: mutation,
    useSetBillableMutation: mutation,
    useWriteConfigMutation: mutation,
    useCreatePromptMutation: mutation,
    useUploadAssetMutation: mutation,
    useAttachCoverMutation: mutation,
    useCreatePRMutation: mutation,
    useResolveBugMutation: mutation,
    useCreateAdoItemMutation: mutation,
  };
});

function faces(container: HTMLElement) {
  return Array.from(container.querySelectorAll("[draggable]")).map((face) => ({
    name: face.querySelector("button")?.textContent,
    cover: face.querySelector("[data-card-cover]") as HTMLElement | null,
    first: face.firstElementChild as HTMLElement | null,
  }));
}

describe("the board's card face wears its cover", () => {
  it("draws the cover as the top of the face, above the title, and nothing for a card without one", () => {
    const { container } = render(
      <MemoryRouter>
        <Board />
      </MemoryRouter>,
    );
    const [withCover, nullCover, absentCover] = faces(container);
    expect(withCover.name).toBe("Search returns duplicates");
    expect(withCover.cover).not.toBeNull();
    expect(withCover.first).toBe(withCover.cover);
    expect(withCover.cover?.style.backgroundImage).toContain("/api/assets/demo/214/cover.png");
    expect(withCover.cover?.getAttribute("aria-label")).toBe("Cover of Search returns duplicates");
    // No cover, no gap: the face starts with its title row, as it always has.
    for (const face of [nullCover, absentCover]) {
      expect(face.cover).toBeNull();
      expect(face.first?.querySelector("button")?.textContent).toBe(face.name);
    }
  });

  it("puts no image element in a draggable face -- the drag must carry the card", () => {
    const { container } = render(
      <MemoryRouter>
        <Board />
      </MemoryRouter>,
    );
    expect(container.querySelectorAll("[draggable] img")).toHaveLength(0);
  });
});

describe("the Home list's thumbnail", () => {
  it("is drawn for a cover and is nothing at all without one", () => {
    const { container, rerender } = render(
      <CoverThumb cover="/api/assets/demo/214/cover.png" label="Search" />,
    );
    expect(container.querySelector("[data-cover-thumb]")).not.toBeNull();
    rerender(<CoverThumb cover={null} label="Search" />);
    expect(container.innerHTML).toBe("");
    rerender(<CoverThumb label="Search" />);
    expect(container.innerHTML).toBe("");
  });
});

describe("the card page's pictures", () => {
  const footer = (lines: string[]) =>
    ["# Bug 214: Search", "", "---", "", ...lines, `${consts.stamps.created} 2026-09-14`, ""].join(
      "\n",
    );

  it("draws nothing for a card with neither line", () => {
    const { container } = render(<CardPictures content={footer([])} label="Search" />);
    expect(container.innerHTML).toBe("");
  });

  it("draws a cover alone, unlabelled", () => {
    const { container, getByRole } = render(
      <CardPictures
        cover="/api/assets/demo/214/cover.png"
        content={footer([`${STAMPS.cover} ../assets/214/cover.png`])}
        label="Search"
      />,
    );
    expect(getByRole("img").getAttribute("src")).toBe("/api/assets/demo/214/cover.png");
    expect(container.textContent).not.toContain("Before");
  });

  it("draws Before and After side by side", () => {
    const { getAllByRole, container } = render(
      <CardPictures
        cover="/api/assets/demo/214/cover.png"
        before="/api/assets/demo/214/before.png"
        content={footer([
          `${STAMPS.before} ../assets/214/before.png`,
          `${STAMPS.cover} ../assets/214/cover.png`,
        ])}
        label="Search"
      />,
    );
    expect(getAllByRole("img").map((i) => i.getAttribute("src"))).toEqual([
      "/api/assets/demo/214/before.png",
      "/api/assets/demo/214/cover.png",
    ]);
    const labels = Array.from(container.querySelectorAll("figure")).map(
      (f) => f.firstElementChild?.textContent,
    );
    expect(labels).toEqual(["Before", "After"]);
  });

  it("says the image is missing rather than drawing a broken one", () => {
    const { container, queryByRole } = render(
      <CardPictures
        cover={null}
        content={footer([`${STAMPS.cover} ../assets/214/cover.png`])}
        label="Search"
      />,
    );
    expect(queryByRole("img")).toBeNull();
    expect(container.querySelector("[data-image-missing]")?.textContent).toBe(
      "The image is missing: ../assets/214/cover.png",
    );
  });
});

describe("imageLine", () => {
  it("reads the line's value as written, from an LF or a CRLF card", () => {
    const text = `x\n${STAMPS.cover} ../assets/K7M2/cover.png  \n${consts.stamps.created} 2026-09-18\n`;
    expect(imageLine(text, STAMPS.cover)).toBe("../assets/K7M2/cover.png");
    expect(imageLine(text.replace(/\n/g, "\r\n"), STAMPS.cover)).toBe("../assets/K7M2/cover.png");
    expect(imageLine(text, STAMPS.before)).toBeNull();
  });
});
