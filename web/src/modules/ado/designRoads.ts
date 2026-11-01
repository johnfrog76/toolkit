import { HatGraduationRegular } from "@fluentui/react-icons";
import { ROW, defineRowMoves } from "../../shared/CardActions";
import type { RowMove } from "../../shared/CardActions";
import type { MoveDesignFields } from "./cliBridge";
import type { Design } from "./api.ado";

// The roads a design can be moved along, and the checkout a product's move runs
// in: the vocabulary of MoveDesignDialog, kept here so the Design tab's rows
// (ado, which loads with the app) can offer a road without importing the
// dialog and its API module (studio, which loads with the Studio page).
// Nothing in this file may import from ../studio.

/** What a road asks for before it runs: the drop its reason, the completion
 *  the path the docs landed in; a graduation and a shipped archive nothing. */
export type MoveRoad = "spec" | "shipped" | "dropped" | "complete";

/** A hub design's own move: a graduation is on no other record. Its archives
 *  and its completion are the vocabulary's (shared/CardActions ROW). */
export const DESIGN_MOVES = defineRowMoves("design", {
  graduate: { word: "Graduate to a spec", icon: HatGraduationRegular },
});

function road(move: RowMove, detail?: string) {
  return { move, detail, label: move.label(detail) };
}

export const ROADS: Record<
  MoveRoad,
  {
    /** The row-menu move this road is, and the detail its word takes. */
    move: RowMove;
    detail?: string;
    label: string;
    to: MoveDesignFields["to"];
    dropped?: boolean;
    needs?: "reason" | "doc";
    what: string;
  }
> = {
  spec: {
    ...road(DESIGN_MOVES.graduate),
    to: "Spec",
    what: "Scaffold the spec beside the note, with the note's id, description and thread. The note stays in design/.",
  },
  shipped: {
    ...road(ROW.archive, "as shipped"),
    to: "Archive",
    what: "Move the note to design/archive/ and stamp it Closed and shipped -- a design that shipped as written.",
  },
  dropped: {
    ...road(ROW.archive, "as dropped"),
    to: "Archive",
    dropped: true,
    needs: "reason",
    what: "Move the note to design/archive/ and stamp it Closed and dropped. An idea that never made it is only worth keeping with why.",
  },
  complete: {
    ...road(ROW.complete),
    to: "Complete",
    needs: "doc",
    what: "Move the spec to spec/archive/ and the note to design/archive/, stamp both Closed, and write where the docs landed into the spec.",
  },
};

/** The roads a row offers, by what the design has and where it is (4.4). */
export function roadsFor(d: Pick<Design, "state" | "note" | "spec">): MoveRoad[] {
  const liveNote = !!d.note && !d.note.archived;
  const liveSpec = !!d.spec && !d.spec.archived;
  if (liveSpec) return ["complete"];
  if (liveNote) return ["spec", "shipped", "dropped"];
  return [];
}

/** The file name the verb is given: the note's, else the spec's. */
export function moveName(d: Pick<Design, "note" | "spec">): string {
  return d.note?.name ?? d.spec?.name ?? "";
}

/** Where a product's design is moved: the Space's clone on this machine. */
export interface ProductCheckout {
  /** The Space's slug, which the verb's -Space takes. */
  space: string;
  /** owner/name, as the Design tab reads it. */
  repo: string;
  /** The clone's top level. */
  root: string;
}
