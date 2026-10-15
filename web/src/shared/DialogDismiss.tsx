import { Button, DialogTrigger } from "@fluentui/react-components";
import { DismissRegular } from "@fluentui/react-icons";

/**
 * Global dismiss (X) control for dialog titles. Plug into the title's `action`
 * prop — `<DialogTitle action={<DialogDismiss />}>` — so the top-right close
 * button has one consistent style and size across every dialog in the app.
 */
export function DialogDismiss() {
  return (
    <DialogTrigger action="close">
      <Button appearance="subtle" size="small" icon={<DismissRegular />} aria-label="Close" />
    </DialogTrigger>
  );
}
