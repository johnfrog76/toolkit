import { Dropdown, makeStyles } from "@fluentui/react-components";
import type { DropdownProps } from "@fluentui/react-components";

const useStyles = makeStyles({
  root: {
    minWidth: 0,
  },
});

type TruncatedDropdownProps = DropdownProps & {
  /** Max characters shown in the toggle button. Truncates with "…". */
  maxToggleLength?: number;
};

function truncate(text: string | undefined, max: number | undefined) {
  if (!text || !max || text.length <= max) return text;
  const cut = text.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  const word = lastSpace > 0 ? cut.slice(0, lastSpace) : cut;
  return word.replace(/\s*\($/, "") + "…";
}

export function TruncatedDropdown({
  maxToggleLength,
  value,
  defaultValue,
  className,
  ...rest
}: TruncatedDropdownProps) {
  const styles = useStyles();
  const display = truncate(value, maxToggleLength);
  return (
    <Dropdown
      {...rest}
      className={`${styles.root}${className ? ` ${className}` : ""}`}
      value={display}
      defaultValue={truncate(defaultValue ?? value, maxToggleLength)}
    />
  );
}
