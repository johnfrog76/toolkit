import ReactMarkdown from "react-markdown";
import { alignRules, markdownPlugins } from "./markdownPlugins";
import { makeStyles, tokens } from "@fluentui/react-components";
import { prepareMarkdown } from "./prepareMarkdown";

const useStyles = makeStyles({
  body: {
    lineHeight: "1.6",
    "& h1": {
      fontSize: tokens.fontSizeBase500,
      fontWeight: tokens.fontWeightSemibold,
      marginTop: tokens.spacingVerticalL,
      marginBottom: tokens.spacingVerticalS,
    },
    "& h2": {
      fontSize: tokens.fontSizeBase400,
      fontWeight: tokens.fontWeightSemibold,
      marginTop: tokens.spacingVerticalL,
      marginBottom: tokens.spacingVerticalXS,
    },
    "& h3": {
      fontSize: tokens.fontSizeBase300,
      fontWeight: tokens.fontWeightSemibold,
      marginTop: tokens.spacingVerticalM,
      marginBottom: tokens.spacingVerticalXS,
    },
    "& p": { marginTop: 0, marginBottom: tokens.spacingVerticalS },
    "& ul, & ol": { paddingLeft: "1.5rem", marginBottom: tokens.spacingVerticalS },
    "& li": { marginBottom: tokens.spacingVerticalXS },
    "& hr": {
      border: "none",
      borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
      margin: `${tokens.spacingVerticalM} 0`,
    },
    "& strong": { fontWeight: tokens.fontWeightSemibold },
    "& code": {
      fontFamily: tokens.fontFamilyMonospace,
      fontSize: tokens.fontSizeBase200,
      backgroundColor: tokens.colorNeutralBackground3,
      padding: "1px 4px",
      borderRadius: tokens.borderRadiusSmall,
    },
    ...alignRules,
    "& table": {
      width: "100%",
      borderCollapse: "collapse" as const,
      marginBottom: tokens.spacingVerticalS,
    },
    "& th, & td": {
      border: `1px solid ${tokens.colorNeutralStroke2}`,
      padding: `${tokens.spacingVerticalXS} ${tokens.spacingHorizontalS}`,
      textAlign: "left" as const,
    },
    "& th": {
      backgroundColor: tokens.colorNeutralBackground3,
      fontWeight: tokens.fontWeightSemibold,
    },
  },
});

interface Props {
  children: string;
  style?: React.CSSProperties;
}

export function MarkdownBlock({ children, style }: Props) {
  const styles = useStyles();
  return (
    <div className={styles.body} style={style}>
      <ReactMarkdown {...markdownPlugins}>{prepareMarkdown(children).body}</ReactMarkdown>
    </div>
  );
}
