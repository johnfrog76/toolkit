import { useEffect, useId, useRef, useState } from "react";
import type { ClipboardEvent, DragEvent, ReactNode, RefObject } from "react";
import {
  Button,
  Caption1,
  makeStyles,
  mergeClasses,
  shorthands,
  tokens,
} from "@fluentui/react-components";
import { DismissRegular, ImageAddRegular } from "@fluentui/react-icons";
import { ASSETS } from "../shell/consts";

// A place you can see and aim at (the owner, after walking tkCover): a
// visible drop zone with a file picker as the fallback and paste as the third
// way in. It takes ONE image and hands it to the caller as a File; the caller
// uploads it and runs the verb (docs/hub/cards.md, "A card's pictures")
// -- nothing here writes anywhere. What the verb would refuse is refused
// here first, in the verb's own terms (the type list, the size with the
// number), so the person hears it before a shell starts. The zone keeps its
// box whether or not it holds a picture: no layout jump.

const useStyles = makeStyles({
  zone: {
    position: "relative",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    gap: tokens.spacingVerticalXS,
    width: "100%",
    aspectRatio: "16 / 10",
    boxSizing: "border-box",
    padding: tokens.spacingVerticalM,
    borderRadius: tokens.borderRadiusLarge,
    border: `2px dashed ${tokens.colorNeutralStroke1}`,
    color: tokens.colorNeutralForeground3,
    backgroundColor: tokens.colorNeutralBackground2,
    cursor: "pointer",
    textAlign: "center",
  },
  over: {
    ...shorthands.borderColor(tokens.colorBrandStroke1),
    backgroundColor: tokens.colorBrandBackground2,
    color: tokens.colorBrandForeground1,
  },
  holding: {
    border: `2px solid ${tokens.colorNeutralStroke1}`,
    backgroundSize: "cover",
    backgroundPosition: "center",
    cursor: "default",
  },
  disabled: { opacity: 0.6, cursor: "not-allowed" },
  icon: { fontSize: "28px", lineHeight: 0 },
  // The chip over the picture: the file's name, and under it what happens
  // next. Absolute, so the zone keeps its box whatever the chip says.
  held: {
    position: "absolute",
    left: tokens.spacingHorizontalS,
    bottom: tokens.spacingVerticalS,
    maxWidth: `calc(100% - 2 * ${tokens.spacingHorizontalS})`,
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
    textAlign: "left",
    padding: `0 ${tokens.spacingHorizontalXS}`,
    borderRadius: tokens.borderRadiusMedium,
    backgroundColor: tokens.colorNeutralBackgroundAlpha2,
    color: tokens.colorNeutralForeground1,
  },
  name: {
    maxWidth: "100%",
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  clear: { position: "absolute", right: tokens.spacingHorizontalXS, top: tokens.spacingVerticalXS },
  input: { display: "none" },
  problem: { color: tokens.colorPaletteRedForeground1, marginTop: tokens.spacingVerticalXS },
});

/** The sentence the verb would say, or null when the file is one Cover takes. */
export function imageProblem(file: Pick<File, "name" | "size">): string | null {
  const ext = file.name.includes(".")
    ? file.name.slice(file.name.lastIndexOf(".") + 1).toLowerCase()
    : "";
  if (!ASSETS.coverExtensions.includes(ext)) {
    return `${file.name || "That file"} is not an image type Cover accepts (${ASSETS.coverExtensions.join(", ")}).`;
  }
  if (file.size > ASSETS.coverMaxBytes) {
    return `${file.name} is ${file.size.toLocaleString()} bytes; Cover copies at most ${ASSETS.coverMaxBytes.toLocaleString()}.`;
  }
  return null;
}

/** The one image among what was dropped or pasted, or null. */
export function imageFrom(items: DataTransfer | null | undefined): File | null {
  if (!items) return null;
  const files = Array.from(items.files ?? []);
  const file = files.find((f) => f.type.startsWith("image/")) ?? files[0] ?? null;
  if (file) return file;
  // A pasted screen snap arrives as an item with no file list on some browsers.
  for (const item of Array.from(items.items ?? [])) {
    if (item.kind === "file" && item.type.startsWith("image/")) {
      const f = item.getAsFile();
      if (f) return f;
    }
  }
  return null;
}

/** A pasted snap has no name; give it one the verb can take, from its type. */
export function namedFile(file: File): File {
  if (file.name && file.name.includes(".")) return file;
  const ext = (file.type.split("/")[1] || "png").replace("jpeg", "jpg");
  return new File([file], `pasted.${ext}`, { type: file.type });
}

export function ImageDropZone({
  label,
  hint,
  file,
  onFile,
  disabled = false,
  compact = false,
  next,
}: {
  /** What the zone is for: "Add cover", "A picture". Also its accessible name. */
  label: string;
  hint?: ReactNode;
  /** The image it holds, or null. The caller owns it. */
  file: File | null;
  onFile: (file: File | null) => void;
  disabled?: boolean;
  /** A shorter box for a dialog. */
  compact?: boolean;
  /** The button that acts on the file. The zone reads what to press from its
   *  own label, so the two never drift, and hands it focus once a file is in. */
  next?: RefObject<HTMLButtonElement | null>;
}) {
  const styles = useStyles();
  const inputId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  // What the zone says once it holds a file: the file it replaced, if any,
  // and the label of the button to press -- read at the take, while the button
  // shows its resting label. `taken` moves focus there after the render that
  // enables it.
  const [staged, setStaged] = useState<{ replaced: string | null; press: string } | null>(null);
  const [taken, setTaken] = useState(0);

  useEffect(() => {
    if (taken === 0) return;
    const button = next?.current;
    if (button && !button.disabled) button.focus();
  }, [taken, next]);

  const take = (candidate: File | null) => {
    if (!candidate) return;
    const named = namedFile(candidate);
    const why = imageProblem(named);
    setProblem(why);
    if (why) return;
    if (preview) URL.revokeObjectURL(preview);
    setPreview(typeof URL.createObjectURL === "function" ? URL.createObjectURL(named) : null);
    setStaged({
      replaced: file ? file.name : null,
      press: next?.current?.textContent?.trim() ?? "",
    });
    setTaken((n) => n + 1);
    onFile(named);
  };
  const clear = () => {
    if (preview) URL.revokeObjectURL(preview);
    setPreview(null);
    setProblem(null);
    setStaged(null);
    onFile(null);
    if (inputRef.current) inputRef.current.value = "";
  };
  const onDrop = (e: DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setOver(false);
    if (disabled) return;
    take(imageFrom(e.dataTransfer));
  };
  const onPaste = (e: ClipboardEvent<HTMLDivElement>) => {
    if (disabled) return;
    const pasted = imageFrom(e.clipboardData);
    if (pasted) {
      e.preventDefault();
      take(pasted);
    }
  };
  const open = () => {
    if (!disabled) inputRef.current?.click();
  };

  // ONE interactive element at a time (axe's nested-interactive): the
  // zone is a named group you drop on, and the Button inside it -- Choose a
  // file, or Remove -- is what a keyboard reaches. A paste with that Button
  // focused bubbles to the zone. A click anywhere on an empty zone still opens
  // the picker, for a pointer.
  return (
    <div>
      <div
        role="group"
        aria-label={file ? `${label}: ${file.name}` : label}
        aria-disabled={disabled || undefined}
        data-image-drop-zone=""
        className={mergeClasses(
          styles.zone,
          over && styles.over,
          !!file && styles.holding,
          disabled && styles.disabled,
        )}
        style={{
          backgroundImage: preview ? `url("${preview}")` : undefined,
          ...(compact ? { aspectRatio: "16 / 6" } : {}),
        }}
        onClick={file ? undefined : open}
        onDragOver={(e) => {
          e.preventDefault();
          if (!disabled) setOver(true);
        }}
        onDragLeave={() => setOver(false)}
        onDrop={onDrop}
        onPaste={onPaste}
      >
        {file ? (
          <>
            <div className={styles.held}>
              <Caption1 className={styles.name}>{file.name}</Caption1>
              {staged?.press ? (
                <Caption1 role="status">
                  {staged.replaced ? `Replaced ${staged.replaced}. ` : ""}
                  {`Press ${staged.press} to attach it.`}
                </Caption1>
              ) : null}
            </div>
            <Button
              className={styles.clear}
              size="small"
              appearance="subtle"
              icon={<DismissRegular />}
              aria-label={`Remove ${file.name}`}
              onClick={(e) => {
                e.stopPropagation();
                clear();
              }}
              disabled={disabled}
            />
          </>
        ) : (
          <>
            <span className={styles.icon} aria-hidden>
              <ImageAddRegular />
            </span>
            <Caption1>{over ? "Drop it here" : "Drop an image here, paste one, or"}</Caption1>
            <Button
              size="small"
              appearance="secondary"
              disabled={disabled}
              onClick={(e) => {
                e.stopPropagation();
                open();
              }}
            >
              Choose a file
            </Button>
            {hint ? <Caption1>{hint}</Caption1> : null}
          </>
        )}
      </div>
      <input
        id={inputId}
        ref={inputRef}
        className={styles.input}
        type="file"
        accept={ASSETS.coverExtensions.map((e) => `.${e}`).join(",")}
        aria-label={`${label}: choose a file`}
        onChange={(e) => take(e.target.files?.[0] ?? null)}
        disabled={disabled}
      />
      {problem ? (
        <Caption1 role="alert" className={styles.problem}>
          {problem}
        </Caption1>
      ) : null}
    </div>
  );
}
