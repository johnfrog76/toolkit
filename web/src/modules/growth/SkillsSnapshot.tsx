import { Subtitle2, Caption1, Badge, Button, makeStyles, tokens } from "@fluentui/react-components";
import { DismissRegular } from "@fluentui/react-icons";
import { PageCard } from "../../shared/PageCard";
import { useGetEngagementSkillsQuery } from "./api.growth";
import type { SkillGroups } from "./api.growth";

const useStyles = makeStyles({
  groups: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
  },
  group: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
  },
  tags: {
    display: "flex",
    flexWrap: "wrap" as const,
    gap: tokens.spacingHorizontalXS,
  },
  tag: {
    cursor: "pointer",
    transition: "opacity 0.15s",
    ":hover": { opacity: 0.75 },
  },
  tagDimmed: {
    opacity: 0.35,
    cursor: "pointer",
  },
  empty: {
    color: tokens.colorNeutralForeground3,
  },
});

const GROUP_ORDER: (keyof SkillGroups)[] = [
  "Languages",
  "Frameworks",
  "Domains",
  "A11y",
  "Auth",
  "Tools",
  "Patterns",
];

interface SkillsSnapshotProps {
  slug: string;
  activeTag?: string | null;
  onTagClick?: (tag: string) => void;
}

export function SkillsSnapshot({ slug, activeTag, onTagClick }: SkillsSnapshotProps) {
  const styles = useStyles();
  const { data, isLoading, isError } = useGetEngagementSkillsQuery(slug);

  if (isLoading)
    return (
      <PageCard
        loading
        loadingLabel="Loading skills…"
        headerLeft={<Subtitle2>Skills Snapshot</Subtitle2>}
      />
    );
  if (isError || !data) return null;

  const nonEmpty = GROUP_ORDER.filter((g) => data.groups[g]?.length > 0);
  if (nonEmpty.length === 0) return null;

  return (
    <PageCard
      headerLeft={<Subtitle2>Skills Snapshot</Subtitle2>}
      headerRight={
        activeTag ? (
          <Button
            size="small"
            appearance="subtle"
            icon={<DismissRegular />}
            iconPosition="after"
            onClick={() => onTagClick?.(activeTag)}
            style={{ color: tokens.colorBrandForeground1, minWidth: 0 }}
          >
            {activeTag}
          </Button>
        ) : undefined
      }
    >
      <div className={styles.groups}>
        {nonEmpty.map((group) => (
          <div key={group} className={styles.group}>
            <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>{group}</Caption1>
            <div className={styles.tags}>
              {data.groups[group].map((tag) => {
                const isActive = activeTag === tag;
                const isDimmed = activeTag !== null && activeTag !== tag;
                return (
                  <Badge
                    key={tag}
                    appearance="tint"
                    color={isActive ? "brand" : "informative"}
                    size="small"
                    className={isDimmed ? styles.tagDimmed : styles.tag}
                    onClick={() => onTagClick?.(tag)}
                  >
                    {tag}
                  </Badge>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </PageCard>
  );
}
