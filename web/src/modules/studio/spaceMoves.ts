import {
  ArrowEnterRegular,
  HistoryRegular,
  LinkRegular,
  SubtractCircleRegular,
} from "@fluentui/react-icons";
import { defineRowMoves } from "../../shared/CardActions";

/** A Space's own moves, on no other record. Retire and Remove read like the
 *  vocabulary's Archive and Delete and are neither: Retire writes the Space's
 *  `status: archive` through Config and moves no file; Remove un-declares the
 *  Space and deletes nothing -- its folder and cards stay in the hub. */
export const SPACE_MOVES = defineRowMoves("space", {
  enter: { word: "Go into", icon: ArrowEnterRegular },
  connect: { word: "Connect", icon: LinkRegular },
  retire: {
    word: "Retire",
    icon: HistoryRegular,
    differentMove:
      "RetireSpace writes the Space's status through Config; no file moves and nothing is stamped closed.",
  },
  remove: {
    word: "Remove",
    icon: SubtractCircleRegular,
    differentMove:
      "RemoveSpace un-declares the Space; its folder and every card in it stay in the hub.",
  },
});
