import { Button, Spinner } from "@fluentui/react-components";
import { ArrowSyncRegular } from "@fluentui/react-icons";

interface RefreshButtonProps {
  onClick: () => void;
  isFetching?: boolean;
  disabled?: boolean;
  title?: string;
}

export function RefreshButton({
  onClick,
  isFetching = false,
  disabled = false,
  title = "Refresh",
}: RefreshButtonProps) {
  return (
    <Button
      appearance="subtle"
      size="small"
      icon={isFetching ? <Spinner size="tiny" /> : <ArrowSyncRegular />}
      onClick={onClick}
      disabled={disabled || isFetching}
      title={title}
    />
  );
}
