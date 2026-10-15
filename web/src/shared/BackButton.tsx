import { Button } from "@fluentui/react-components";
import { ArrowLeftRegular } from "@fluentui/react-icons";
import { useLocation, useNavigate } from "react-router";

interface BackButtonProps {
  title?: string;
}

export function BackButton({ title = "Back" }: BackButtonProps) {
  const navigate = useNavigate();
  const location = useLocation();

  // A "default" location key means this route was the first entry in the tab's
  // history (deep link, search result, shared URL), so there is no in-app entry
  // to pop back to and -1 would dead-end or leave the app entirely.
  const onBack = () => {
    if (location.key === "default") {
      navigate("/");
    } else {
      navigate(-1);
    }
  };

  return (
    <Button
      icon={<ArrowLeftRegular />}
      size="small"
      appearance="subtle"
      onClick={onBack}
      title={title}
    />
  );
}
