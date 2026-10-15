/**
 * The Design tab's kind row and the Docs tab's folder row, in the filter
 * drawer. The same chip rows the Issues filters are drawn with
 * (FilterBadge, a radiogroup per axis), so a tab's filters read the same
 * wherever they are. The list under each tab reads the same choice
 * (docFilters.ts) and says what it is set to in its header.
 */
import { makeStyles, tokens } from "@fluentui/react-components";
import { FilterBadge } from "../../shared/FilterBadge";
import { useGetDocsQuery } from "./api.ado";
import { ALL, DESIGN_KINDS, docFolders, useDesignFilters, useDocsFilters } from "./docFilters";

const useStyles = makeStyles({
  row: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
    justifyContent: "center",
    marginBottom: tokens.spacingVerticalS,
  },
});

export function DesignKindRow() {
  const styles = useStyles();
  const { kind, setKind } = useDesignFilters();
  return (
    <div className={styles.row} role="radiogroup" aria-label="Design kind">
      <FilterBadge
        label="any kind"
        appearance="pink"
        active={kind === ALL}
        onClick={() => setKind(ALL)}
      />
      {DESIGN_KINDS.map((k) => (
        <FilterBadge
          key={k.value}
          label={k.label}
          appearance="pink"
          active={kind === k.value}
          onClick={() => setKind(kind === k.value ? ALL : k.value)}
        />
      ))}
    </div>
  );
}

export function DocsFolderRow() {
  const styles = useStyles();
  const { folder, setFolder } = useDocsFilters();
  // The same cache entry the Docs tab reads -- no second fetch. The folders
  // are the tree's own, so a repo with docs/hub offers it and one without
  // does not. A remembered folder the tree no longer has still shows (and
  // clears), so the way back never disappears.
  const { data } = useGetDocsQuery();
  const folders = docFolders(data?.items ?? []);
  if (folder !== ALL && !folders.includes(folder)) folders.push(folder);
  return (
    <div className={styles.row} role="radiogroup" aria-label="Docs folder">
      <FilterBadge label="all folders" active={folder === ALL} onClick={() => setFolder(ALL)} />
      {folders.map((f) => (
        <FilterBadge
          key={f}
          label={`${f}/`}
          active={folder === f}
          onClick={() => setFolder(folder === f ? ALL : f)}
        />
      ))}
    </div>
  );
}
