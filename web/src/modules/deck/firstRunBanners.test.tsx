import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { HomeBanner } from "./HomeBanner";
import { PoetBanner } from "./PoetBanner";

// Each first-run banner ends its own offer by writing one config key false, through the Config
// verb's one writer. The key is asserted as the literal dotted string the Config schema knows,
// not the imported constant, so a mistyped constant fails here.
const writeConfig = jest.fn();
jest.mock("../ado/api.ado", () => ({
  useWriteConfigMutation: () => [writeConfig],
}));

// jsdom has no ResizeObserver; the poster measures its box with one.
class StubResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}
beforeAll(() => {
  (globalThis as { ResizeObserver?: unknown }).ResizeObserver = StubResizeObserver;
});

const offers = [
  {
    name: "Prompt Poet",
    Banner: PoetBanner,
    key: "firstRun.poet",
    close: "Hide the Prompt Poet banner",
  },
  {
    name: "Introducing ToolKit",
    Banner: HomeBanner,
    key: "firstRun.welcome",
    close: "Hide the Introducing ToolKit banner",
  },
];

describe.each(offers)("the $name first-run banner", ({ Banner, key, close }) => {
  beforeEach(() => writeConfig.mockClear());

  it("writes its own key false when closed, and is gone", () => {
    render(
      <MemoryRouter>
        <Banner />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole("button", { name: close }));
    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: { [key]: false }, unset: [] });
    expect(screen.queryByRole("button", { name: close })).toBeNull();
  });

  it("writes its own key false on Get Started", () => {
    render(
      <MemoryRouter>
        <Banner />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Get Started" }));
    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig).toHaveBeenCalledWith({ set: { [key]: false }, unset: [] });
  });
});
