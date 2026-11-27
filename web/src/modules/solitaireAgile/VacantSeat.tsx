import type { ReactNode } from "react";
import { OfficeDoor, Plate, SeatCell } from "./OrgParts";
import { SIZE, VACANT_WORD, levelWall, vacantMug } from "./orgChart";
import { EmptyDesk } from "./stage/EmptyDesk";

// A seat nobody sits in: the office is there, its door and its plate, and
// nobody in it. The plate reads `vacant`, with Assign beside it on a saved org,
// and the card is the same size as a staffed one, so a row of seats does not
// move when a seat empties.
//
// What stands in the door is the standup's empty desk -- an office chair
// pushed back, a desk and a steaming mug -- on the level's wall, dimmed. It
// fills the door's opening (inside the frame, under the arch's clip), so the
// door keeps its size. The desk mounts its own steam CSS, as it does on the
// stage. The mug comes from the seat's id (vacantMug).

/** The door's opening: inside the 7px frame on every side. */
const FRAME_INSET = 7;

export function VacantSeat({
  seatId,
  position,
  level,
  where,
  session,
  action,
}: {
  seatId: string;
  position: string;
  level: number;
  where?: string;
  session?: string;
  /** Assign, on a saved org. */
  action?: ReactNode;
}) {
  const { wall, shade } = levelWall(level);
  return (
    <SeatCell state="vacant">
      <OfficeDoor wall={wall} shade={shade} dim>
        <foreignObject
          data-testid="org-vacant-desk"
          x={FRAME_INSET}
          y={FRAME_INSET}
          width={SIZE.door.width - 2 * FRAME_INSET}
          height={SIZE.door.height - 2 * FRAME_INSET}
        >
          <div style={{ position: "relative", width: "100%", height: "100%" }}>
            <EmptyDesk look={vacantMug(seatId)} tint={wall} />
          </div>
        </foreignObject>
      </OfficeDoor>
      <Plate position={position} who={VACANT_WORD} where={where} session={session} action={action} />
    </SeatCell>
  );
}
