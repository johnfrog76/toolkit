import { OfficeDoor, Plate, SeatCell } from "./OrgParts";
import { VACANT_WORD, levelWall } from "./orgChart";

// A seat nobody sits in: the office is there, its door and its plate, and
// nobody in it. The plate reads `POSITION · vacant`, and the card is the same
// size as a staffed one, so a row of seats does not move when a seat empties.
//
// What stands in the door today is a PLACEHOLDER: the wall dimmed, and the
// outline of the bust that is not there, dashed. The empty desk scene the
// standup draws for a worker with nothing (a tinted room, an office chair and
// a steaming mug) replaces the inside of this door when it lands; this
// component is the one place it goes, and nothing else on the page changes.

const DASH = "#e6ebf5";

/** The outline of an absent bust, in the door's own pixels (124 by 104). */
function Placeholder() {
  return (
    <g
      data-testid="org-vacant-placeholder"
      fill="none"
      stroke={DASH}
      strokeOpacity="0.55"
      strokeWidth="1.6"
      strokeDasharray="4 4"
      strokeLinecap="round"
    >
      <ellipse cx="62" cy="40" rx="17.6" ry="19.2" />
      <path d="M 26.8 97 C 26.8 75.6 36.4 66.4 51.6 63.6 L 72.4 63.6 C 87.6 66.4 97.2 75.6 97.2 97" />
    </g>
  );
}

export function VacantSeat({
  position,
  level,
  where,
}: {
  position: string;
  level: number;
  where?: string;
}) {
  const { wall, shade } = levelWall(level);
  return (
    <SeatCell state="vacant">
      <OfficeDoor wall={wall} shade={shade} dim>
        <Placeholder />
      </OfficeDoor>
      <Plate position={position} who={VACANT_WORD} where={where} />
    </SeatCell>
  );
}
