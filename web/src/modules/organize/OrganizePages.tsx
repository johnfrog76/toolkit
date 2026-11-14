import { Tab, TabList } from "@fluentui/react-components";
import { useNavigate } from "react-router";
import { PageGrid, useShellSlot } from "../../shell/cards";
import { TabRows } from "../../shared/TabRows";
import { ReferenceCard } from "./ReferenceCard";
import { RemindersCard } from "./RemindersCard";
import { ORGANIZE_HOME, REFERENCE_HOME } from "./paths";

// The Organize tab's pages, Reminders | Reference: one nav entry, and under it
// a strip of in-page tabs, each an ADDRESS -- the same TabRows / TabList Home's
// strip and Team Agile's use, so a tab can be linked and Back walks between
// them. The cards know nothing about the strip.

/** The tabs, in strip order; Reminders is `/organize`. */
const TABS = [
  { id: "reminders", label: "Reminders", path: ORGANIZE_HOME },
  { id: "reference", label: "Reference", path: REFERENCE_HOME },
] as const;

function OrganizeTabs({ current }: { current: (typeof TABS)[number]["id"] }) {
  const navigate = useNavigate();
  return (
    <TabRows>
      <TabList
        size="small"
        aria-label="Organize"
        selectedValue={current}
        onTabSelect={(_e, d) => {
          const next = TABS.find((t) => t.id === d.value);
          if (next && next.id !== current) navigate(next.path);
        }}
      >
        {TABS.map((t) => (
          <Tab key={t.id} value={t.id}>
            {t.label}
          </Tab>
        ))}
      </TabList>
    </TabRows>
  );
}

/**
 * `/organize` -- Reminders, laid out like any other tab: cards in the shell's
 * grid at half width. Meetings first, then Reminders. Meetings is the
 * communication module's card and arrives through the `organize` SLOT: this page
 * imports nothing of that module and does not know what the slot holds, so with
 * communication off the slot is empty and the page is Reminders alone. Each card
 * fetches its own data from the store; the page only places them.
 */
export function OrganizeHome() {
  const slotCards = useShellSlot("organize");
  return (
    <>
      <OrganizeTabs current="reminders" />
      <PageGrid>
        {slotCards}
        <RemindersCard />
      </PageGrid>
    </>
  );
}

/** `/organize/reference` -- the hub's reference documents, listed and searched. */
export function OrganizeReference() {
  return (
    <>
      <OrganizeTabs current="reference" />
      <PageGrid>
        <ReferenceCard />
      </PageGrid>
    </>
  );
}
