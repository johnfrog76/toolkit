import {
  Avatar,
  Menu,
  MenuDivider,
  MenuGroup,
  MenuGroupHeader,
  MenuItem,
  MenuItemRadio,
  MenuList,
  MenuPopover,
  MenuTrigger,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import type { MenuProps } from "@fluentui/react-components";
import { useCurrentTheme } from "../hooks/useCurrentTheme";
import { useSkinGrant, writeSkinGrant } from "../shared/skinGrant";
import { THEMES, SKIN_THEMES } from "./themeList";
import type { SettingsLink } from "./registry";
import { SPACE_QUICK_MENU_THRESHOLD, SpaceQuickMenu } from "./SpaceQuickMenu";

// The avatar is "me and my settings". It used to open one long drawer and leave
// you to hunt; it is a menu now, because the hunt is the problem:
//
//   - the two things changed OFTEN happen right here and never open the drawer:
//     the theme (choosing is the preview) and the organisation;
//   - everything else is a DESTINATION: the drawer opens AT that place.
//
// The destinations come from the registry (a module's `settingsLinks`), so the
// shell still names no setting.

const useStyles = makeStyles({
  trigger: {
    position: "relative",
    padding: 0,
    border: "none",
    background: "none",
    cursor: "pointer",
    borderRadius: tokens.borderRadiusCircular,
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "2px" },
  },
  unsavedDot: {
    position: "absolute",
    top: "-1px",
    right: "-1px",
    width: "10px",
    height: "10px",
    borderRadius: tokens.borderRadiusCircular,
    backgroundColor: tokens.colorPaletteDarkOrangeBackground3,
    border: `2px solid ${tokens.colorNeutralBackground1}`,
  },
  who: { display: "flex", flexDirection: "column", padding: "6px 10px 2px" },
  whoName: { fontWeight: tokens.fontWeightSemibold },
  whoDetail: { color: tokens.colorNeutralForeground3, fontSize: tokens.fontSizeBase200 },
  swatch: {
    display: "inline-block",
    width: "14px",
    height: "14px",
    borderRadius: "3px",
    border: `1px solid ${tokens.colorNeutralStroke1}`,
    verticalAlign: "-2px",
  },
});

export interface SpaceChoice {
  slug: string;
  name: string;
}

interface Props {
  displayName?: string;
  detail?: string;
  unsaved: number;
  spaces: SpaceChoice[];
  activeSpace: string;
  onSwitchSpace: (slug: string) => void;
  links: SettingsLink[];
  onOpenSettings: (anchor?: string) => void;
  /** Spread on the trigger so a closing drawer hands focus back to it. */
  restoreFocusTarget: object;
}

export function AvatarMenu({
  displayName,
  detail,
  unsaved,
  spaces,
  activeSpace,
  onSwitchSpace,
  links,
  onOpenSettings,
  restoreFocusTarget,
}: Props) {
  const styles = useStyles();
  const { active, setThemeId } = useCurrentTheme();
  const skinGrant = useSkinGrant();

  const onCheckedChange: MenuProps["onCheckedValueChange"] = (_e, { name, checkedItems }) => {
    const value = checkedItems[0];
    if (!value) return;
    if (name === "theme") {
      // Picking a theme while a skin is worn TAKES THE SKIN OFF -- no locked
      // controls (D-L17, the owner: "if you switch back to basement -- it just
      // puts the fishtank in the lounge"). The skin goes home to the room;
      // the theme you picked is what you get.
      if (skinGrant) writeSkinGrant(null);
      setThemeId(value);
    }
    if (name === "org" && value !== activeSpace) onSwitchSpace(value);
  };

  const themeGroup = (mode: "dark" | "light", label: string) => (
    <MenuGroup>
      <MenuGroupHeader>{label}</MenuGroupHeader>
      {THEMES.filter((t) => t.mode === mode).map((t) => (
        // persistOnClick: the menu stays open, so you can try one after
        // another with the page changing behind it. That IS the preview.
        <MenuItemRadio key={t.id} name="theme" value={t.id} persistOnClick>
          <span
            className={styles.swatch}
            style={{ backgroundColor: t.page.color, backgroundImage: t.page.image }}
            aria-hidden
          />{" "}
          {t.name}
        </MenuItemRadio>
      ))}
    </MenuGroup>
  );

  return (
    <Menu
      checkedValues={{ theme: [active.id], org: [activeSpace] }}
      onCheckedValueChange={onCheckedChange}
      positioning="below-end"
    >
      <MenuTrigger disableButtonEnhancement>
        <button
          type="button"
          className={styles.trigger}
          aria-label={
            unsaved > 0
              ? `You and your settings, ${unsaved} unsaved ${unsaved === 1 ? "change" : "changes"}`
              : "You and your settings"
          }
          {...restoreFocusTarget}
        >
          <Avatar name={displayName || undefined} size={32} aria-hidden />
          {unsaved > 0 ? <span className={styles.unsavedDot} aria-hidden /> : null}
        </button>
      </MenuTrigger>
      <MenuPopover>
        <MenuList>
          <div className={styles.who}>
            <span className={styles.whoName}>{displayName || "You"}</span>
            {detail ? <span className={styles.whoDetail}>{detail}</span> : null}
          </div>
          <MenuDivider />
          <Menu
            checkedValues={{ theme: [active.id] }}
            onCheckedValueChange={onCheckedChange}
            hasCheckmarks
          >
            <MenuTrigger disableButtonEnhancement>
              {/* While a skin is granted, the product wears the SKIN's theme
                  (full skin, D-L11): the picker keeps working underneath --
                  your choice is what returns when the room takes the skin
                  back -- and this row tells that truth rather than moving
                  any control out of the Lounge. */}
              <MenuItem
                secondaryContent={
                  skinGrant ? `worn: ${SKIN_THEMES[skinGrant.skinId].name}` : active.name
                }
              >
                Theme
              </MenuItem>
            </MenuTrigger>
            <MenuPopover>
              <MenuList>
                {skinGrant ? (
                  <MenuItem disabled>
                    The {SKIN_THEMES[skinGrant.skinId].name} skin is worn -- picking a theme below
                    takes it off and sends it home to the Lounge.
                  </MenuItem>
                ) : null}
                {themeGroup("dark", "Dark")}
                <MenuDivider />
                {themeGroup("light", "Light")}
              </MenuList>
            </MenuPopover>
          </Menu>
          {spaces.length > 1 ? (
            <Menu
              checkedValues={{ org: [activeSpace] }}
              onCheckedValueChange={onCheckedChange}
              hasCheckmarks
            >
              <MenuTrigger disableButtonEnhancement>
                <MenuItem secondaryContent={spaces.find((o) => o.slug === activeSpace)?.name}>
                  Space
                </MenuItem>
              </MenuTrigger>
              <MenuPopover>
                {/* Past the threshold a dropdown cannot hold them: the same
                    entry opens the quick menu instead. */}
                {spaces.length > SPACE_QUICK_MENU_THRESHOLD ? (
                  <SpaceQuickMenu
                    spaces={spaces}
                    activeSpace={activeSpace}
                    onSwitchSpace={onSwitchSpace}
                  />
                ) : (
                  <MenuList>
                    {spaces.map((o) => (
                      <MenuItemRadio key={o.slug} name="org" value={o.slug}>
                        {o.name}
                      </MenuItemRadio>
                    ))}
                  </MenuList>
                )}
              </MenuPopover>
            </Menu>
          ) : null}
          <MenuDivider />
          <MenuGroup>
            <MenuGroupHeader>Settings</MenuGroupHeader>
            {links.map((link) => (
              <MenuItem key={link.anchor} onClick={() => onOpenSettings(link.anchor)}>
                {link.label}
              </MenuItem>
            ))}
            <MenuItem
              onClick={() => onOpenSettings()}
              secondaryContent={unsaved > 0 ? `${unsaved} unsaved` : undefined}
            >
              All settings
            </MenuItem>
          </MenuGroup>
        </MenuList>
      </MenuPopover>
    </Menu>
  );
}
