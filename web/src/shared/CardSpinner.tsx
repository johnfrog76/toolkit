import { Spinner, type SpinnerProps } from "@fluentui/react-components";

export function CardSpinner({
  label,
  size = "tiny",
}: {
  label: string;
  size?: SpinnerProps["size"];
}) {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        flex: 1,
        gridRow: "1 / -1",
        gridColumn: "1 / -1",
      }}
    >
      <Spinner size={size} label={label} />
    </div>
  );
}
