/**
 * The Design tab's kind row and the Docs tab's folder row, in the filter
 * drawer. The same chip rows the Issues filters are drawn with
 * (FilterBadge, a radiogroup per axis), so a tab's filters read the same
 * wherever they are. The list under each tab reads the same choice
 * (docFilters.ts) and says what it is set to in its header.
 */
import { makeStyles, tokens } from "@fluentui/react-components";
import { FilterBadge } from "../../shared/FilterBadge";
import { useGetDesignQuery, useGetDocsQuery } from "./api.ado";
import {
  ALL,
  DESIGN_KINDS,
  designMatches,
  docFolders,
  useDesignFilters,
  useDocsFilters,
} from "./docFilters";

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
  // The same cache entry the Design tab reads -- no second fetch.
  const { data } = useGetDesignQuery();
  const designs = data?.designs ?? [];
  return (
    <div className={styles.row} role="radiogroup" aria-label="Design kind">
      <FilterBadge
        label="any kind"
        count={designs.length}
        appearance="tabColorOne"
        active={kind === ALL}
        onClick={() => setKind(ALL)}
      />
      {DESIGN_KINDS.map((k) => (
        <FilterBadge
          key={k.value}
          label={k.label}
          count={designs.filter((d) => designMatches(d, "", k.value)).length}
          appearance="tabColorOne"
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
  const items = data?.items ?? [];
  const folders = docFolders(items);
  if (folder !== ALL && !folders.includes(folder)) folders.push(folder);
  return (
    <div className={styles.row} role="radiogroup" aria-label="Docs folder">
      <FilterBadge
        label="all folders"
        count={items.length}
        active={folder === ALL}
        onClick={() => setFolder(ALL)}
      />
      {folders.map((f) => (
        <FilterBadge
          key={f}
          label={`${f}/`}
          count={items.filter((d) => d.folder === f).length}
          active={folder === f}
          onClick={() => setFolder(folder === f ? ALL : f)}
        />
      ))}
    </div>
  );
}
