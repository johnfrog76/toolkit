/**
 * Retire or Remove a Space from its row on the Studio's Spaces card:
 * `RetireSpace <slug>` or `RemoveSpace <slug> -Force` through the bridge, behind
 * the house's one confirm (`shared/ConfirmDialog`). The verbs are the one
 * implementation -- Config writes, nothing here does.
 *
 * Before Submit can be pressed the dialog runs the verb's own `-WhatIf` and shows
 * its lines: the keys that would go and the folder that STAYS, with its cards
 * counted -- for a Remove, that is the confirmation that names the count of cards
 * in current/, so the confirmed run carries `-Force` (the bridge cannot answer the
 * verb's own question). A refusal -- the preview's or the run's -- stays in the
 * dialog in the verb's words, and Submit stays shut after a refused preview.
 */
import { useEffect, useState } from "react";
import { Caption1, tokens } from "@fluentui/react-components";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import type { SpaceInfo } from "../../shell/api";
import { buildSpaceLifecycleParams, commandResultMessage } from "../ado/cliBridge";
import { usePreviewSpaceLifecycleMutation, useRunSpaceLifecycleMutation } from "./api.studio";
import type { SpaceLifecycleVerb } from "./api.studio";

interface Props {
  /** The Space and the verb, or null when the dialog is closed. */
  target: { space: SpaceInfo; verb: SpaceLifecycleVerb } | null;
  onClose: () => void;
  /** Success: the card says it. */
  onDone: (message: string) => void;
}

export function SpaceLifecycleDialog({ target, onClose, onDone }: Props) {
  const [preview, { isLoading: previewing }] = usePreviewSpaceLifecycleMutation();
  const [run, { isLoading: running }] = useRunSpaceLifecycleMutation();
  const [lines, setLines] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [blocked, setBlocked] = useState(false);

  const slug = target?.space.slug ?? "";
  const verb = target?.verb;
  // A new Space or verb clears the last answer while rendering, against the pair
  // the last render saw; the effect below only asks for the new preview.
  const [shownFor, setShownFor] = useState({ slug, verb });
  if (shownFor.slug !== slug || shownFor.verb !== verb) {
    setShownFor({ slug, verb });
    setLines(null);
    setMessage(null);
    setBlocked(false);
  }
  useEffect(() => {
    if (!slug || !verb) return;
    let live = true;
    preview({ verb, params: buildSpaceLifecycleParams({ slug, whatIf: true }) })
      .unwrap()
      .then((result) => {
        if (!live) return;
        if (result.status === "success") setLines((result.output ?? "").trim());
        else {
          setBlocked(true);
          setMessage(commandResultMessage(result, ""));
        }
      })
      .catch(() => {
        if (!live) return;
        setBlocked(true);
        setMessage("Could not reach the agent. Nothing was changed.");
      });
    return () => {
      live = false;
    };
  }, [slug, verb, preview]);

  if (!target) return null;
  const name = target.space.name || target.space.slug;
  const removing = target.verb === "RemoveSpace";

  const confirm = async () => {
    setMessage(null);
    try {
      const result = await run({
        verb: target.verb,
        params: buildSpaceLifecycleParams({ slug: target.space.slug, force: removing }),
      }).unwrap();
      if (result.status === "success") {
        onDone(
          removing
            ? `Removed ${name}. Its folder and every card in it stay in the hub.`
            : `Retired ${name}. It is under Archive, its cards kept.`,
        );
        return;
      }
      setMessage(commandResultMessage(result, ""));
    } catch {
      setMessage("Could not reach the agent. Nothing was changed.");
    }
  };

  return (
    <ConfirmDialog
      open
      confirmLabel={removing ? "Remove" : "Retire"}
      what={
        <>
          {removing ? (
            <>
              Remove <strong>{name}</strong>. It is no longer a Space: its entry leaves the
              hub&apos;s <code>hub.json</code>. Its folder and every card in it stay in the hub, and
              adding a Space with that folder brings them back.
            </>
          ) : (
            <>
              Retire <strong>{name}</strong>. It stays a Space, archived: its cards stay where they
              are and stay readable, and nothing asks its tracker again.
            </>
          )}
          {lines ? (
            <Caption1
              data-testid="space-lifecycle-preview"
              style={{
                display: "block",
                marginTop: tokens.spacingVerticalS,
                whiteSpace: "pre-wrap",
                color: tokens.colorNeutralForeground2,
              }}
            >
              {lines}
            </Caption1>
          ) : null}
        </>
      }
      busy={running}
      confirmDisabled={previewing || blocked || lines === null}
      message={message}
      onCancel={onClose}
      onConfirm={confirm}
    />
  );
}
