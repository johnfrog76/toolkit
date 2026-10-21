import { useGetEnvQuery } from "../../shell/api";
import { STATUS } from "../../shell/consts";

/**
 * The camelCase field name `spaces.<slug>.laneNames.<key>` is written and read
 * under -- the schema's own spelling (`Scripts/Get-ConfigSchema.ps1`) -- keyed
 * by the CONTRACT word `/env`'s `laneNames` map uses (`agent/core/config.py`
 * `lane_names()` does the same translation the other way). One table, so an
 * editor that writes a lane's label never has to know both spellings itself.
 */
export const LANE_FIELD_KEY: Record<string, string> = {
  [STATUS.backlog]: "backlog",
  [STATUS.active]: "active",
  [STATUS.inProgress]: "inProgress",
  [STATUS.codeReview]: "codeReview",
  [STATUS.done]: "done",
};

/** The dotted config key `Config -Set` (and `PUT /api/config`) take for one
 *  org's one lane label: `spaces.<slug>.laneNames.<key>`. */
export function laneConfigKey(orgSlug: string, status: string): string {
  return `spaces.${orgSlug}.laneNames.${LANE_FIELD_KEY[status] ?? status}`;
}

/**
 * What a lane is CALLED, for this org. The contract's words (consts.json
 * `status`) are what a card's state IS -- stored, compared, served -- and they
 * never change; an org may give each one a display name, and the sample hub's
 * Demo does: To do / Doing / Waiting / Done, for someone with no team and no
 * tracker. An org that says nothing is called by the
 * contract's words, so nothing an ADO user sees changes.
 */
export function laneLabel(names: Record<string, string> | undefined, status: string): string {
  return names?.[status] ?? status;
}

/** `(status) => label` for the active org, from `/env`. */
export function useLaneLabel(): (status: string) => string {
  const { data: env } = useGetEnvQuery();
  const names = env?.config?.laneNames;
  return (status: string) => laneLabel(names, status);
}
