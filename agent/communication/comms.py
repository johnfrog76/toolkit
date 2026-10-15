"""
Communication Engine — the toolkit's single outbound channel to Teams.

Callers build a message object and hand it to send(); the engine owns
formatting, recipient resolution, transport, and fail-soft failure handling. It
is stateless about dedup and never raises into the caller's workflow.

Public entry point:
    from .comms import send
    send({ "caller": "...", "recipient": "...", "subject": "...",
           "sections": [...], "tone": "broadcast" })  ->  { "status", "detail", ... }

Status values: ok | dry-run | disabled | rejected | skipped | error.

The single HTTP POST is isolated in _post_to_webhook so the connector-vs-Workflows
payload envelope can change without touching the rest of the engine.
"""

import json
import os
import urllib.error
import urllib.request

from ..core import log_writer
from ..core.config import DEFAULT_CONFIG_PATH, LOCAL_CONFIG_PATH, _deep_merge, load_config
from ..core.consts import env_teams_webhook_prefix, env_test_run_marker

_VALID_TONES = ("broadcast", "alert", "personal")
# sections is intentionally NOT required: a subject-only post -- the SendTeams
# one-liner -- is valid. When present it must be a list of {heading, body}.
_REQUIRED_FIELDS = ("caller", "recipient", "subject", "tone")

# Bound the POST so a hung Teams endpoint can't freeze the agent's request worker.
_POST_TIMEOUT_SECONDS = 10


# ---------------------------------------------------------------------------
# Config -- the recipients registry, and the flag that gates the whole engine.
#
# Two places hold recipients, for one reason. The manager recipient is not an
# org concern: it does not change when the active Space changes, the way a team
# channel does. So it lives in a top-level ``managerWorkflow.communication``
# block and is merged in regardless of ``activeOrg``; every other recipient
# comes from the active Space's own ``communication`` block, and wins on a key
# collision.
#
# ``features.communication`` is read from the MERGED features map, not from the
# org. The flag is the engineer's: it holds across orgs, and an org cannot turn
# the module off underneath the person who switched it on. That is a deliberate
# change from the package this was carved from, where the master switch was
# per-org -- see docs/modules/communication.md.
#
# The tests hand ``send()`` a config object directly, so this loader is only
# exercised in production. It reads through ``core.config`` rather than parsing
# the JSON itself: one merge implementation, already parity-tested against
# PowerShell's.
# ---------------------------------------------------------------------------
def manager_workflow() -> dict:
    """The top-level ``managerWorkflow`` block, merged across the two config
    files. Read here rather than through ``load_config()``: that function
    resolves the ACTIVE ORG's view of config, and this block is deliberately
    outside any org."""
    merged: dict = {}
    for path in (DEFAULT_CONFIG_PATH, LOCAL_CONFIG_PATH):
        if not path.exists():
            continue
        try:
            raw = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):  # an unreadable or malformed file declares no block
            continue
        block = raw.get("managerWorkflow")
        if isinstance(block, dict):
            _deep_merge(merged, block)
    return merged


def _load_config() -> dict:
    cfg = load_config()

    mw = dict(manager_workflow())
    manager_recipients = (mw.pop("communication", {}) or {}).get("recipients", {}) or {}

    active_slug = cfg.get("activeSpace", "")
    active_space = next((o for o in cfg.get("spaces", []) if o.get("slug") == active_slug), {}) or {}

    communication = dict(active_space.get("communication", {}) or {})
    communication["recipients"] = {**manager_recipients, **communication.get("recipients", {})}

    return {
        "activeSpace": active_slug,
        "features": cfg.get("features", {}) or {},
        "communication": communication,
        "managerWorkflow": mw,
    }


# ---------------------------------------------------------------------------
# Formatting — the SINGLE normalization point.
#
# Teams accepts a small, undocumented markdown subset, so we keep section bodies
# dumb (plain text + links) and normalize here rather than pulling a converter
# library against a moving target. Every caller's text flows through _to_teams_md;
# nothing else in the engine touches message wording.
# ---------------------------------------------------------------------------
def _to_teams_md(text: str) -> str:
    """Normalize a caller string to the safe Teams-MD subset."""
    if text is None:
        return ""
    s = str(text)
    # Unicode dashes -> ASCII (PR titles / Teams messages carry em/en dashes).
    s = s.replace("—", "--").replace("–", "-").replace("−", "-")
    # Normalize line endings; Teams renders \n\n as a paragraph break.
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    return s.strip()


def _render(message: dict) -> str:
    """Message object -> Teams-MD string, per tone."""
    tone = message.get("tone", "broadcast")
    subject = _to_teams_md(message.get("subject", ""))
    sections = message.get("sections") or []

    lines: list[str] = []
    if tone == "alert":
        lines.append(f"**⚠ {subject}**")
    else:
        lines.append(f"**{subject}**")

    for section in sections:
        heading = _to_teams_md(section.get("heading", ""))
        body = _to_teams_md(section.get("body", ""))
        if tone == "personal":
            # Softer formatting: drop headings, render bodies as prose paragraphs.
            if body:
                lines.append(body)
        else:
            if heading:
                lines.append(f"**{heading}**: {body}")
            elif body:
                lines.append(body)

    return "\n\n".join(line for line in lines if line)


# ---------------------------------------------------------------------------
# Recipient resolution.
# ---------------------------------------------------------------------------
# The catch-all every recipient falls back to. Named once: the engine, /env and
# the CLI all have to agree about it, and a second copy is how one of them ends
# up refusing a send another would have made.
FALLBACK_WEBHOOK_ENV = "TEAMS_WEBHOOK_URL"


def _env_key(recipient_key: str) -> str:
    """recipient key -> TEAMS_WEBHOOK_{KEY} convention. The prefix is the contract's."""
    upper = "".join(ch if ch.isalnum() else "_" for ch in recipient_key.upper())
    return f"{env_teams_webhook_prefix()}{upper}"


def webhook_env_name(recipient_key: str, entry: dict | None) -> str:
    """Which environment variable holds this recipient's webhook. Config names
    the variable; the environment holds the URL, always."""
    return (entry or {}).get("webhookEnv") or _env_key(recipient_key)


def webhook_configured(recipient_key: str, entry: dict | None) -> bool:
    """Gate 2, asked without sending anything. This is what /env reports so the
    UI can disable a button rather than discover the problem on click."""
    name = webhook_env_name(recipient_key, entry)
    return bool(os.environ.get(name) or os.environ.get(FALLBACK_WEBHOOK_ENV))


def _resolve_recipient(recipient_key: str, communication: dict) -> dict:
    """Resolve a logical recipient key to a transport target.

    Returns a dict:
        {"ok": True,  "type": "channel", "url": <webhook>, "display": ...}
      or
        {"ok": False, "reason": <human detail for the skipped status>}
    """
    recipients = communication.get("recipients", {}) or {}
    entry = recipients.get(recipient_key)
    if not entry:
        return {"ok": False, "reason": f"unknown recipient key '{recipient_key}'"}

    rtype = entry.get("type")
    display = entry.get("display", recipient_key)

    if rtype == "person":
        # Graph DM path is deferred to v2 -> skipped, never posts.
        return {"ok": False, "reason": f"person recipient '{recipient_key}' (DM deferred to v2)"}

    if rtype != "channel":
        return {"ok": False, "reason": f"recipient '{recipient_key}' has unsupported type '{rtype}'"}

    # The secret webhook URL lives only in env; config names the var, never the URL.
    env_name = webhook_env_name(recipient_key, entry)
    url = os.environ.get(env_name) or os.environ.get(FALLBACK_WEBHOOK_ENV)
    if not url:
        return {"ok": False, "reason": f"webhook env var '{env_name}' (and {FALLBACK_WEBHOOK_ENV}) unset"}

    return {"ok": True, "type": "channel", "url": url, "display": display, "envName": env_name}


# ---------------------------------------------------------------------------
# Transport — the single HTTP POST. Only this function (and _build_payload)
# changes if the payload envelope must change.
#
# Decision, taken at build time against a provisioned webhook: the target is a Power
# Automate **Workflows** webhook, which expects
# an Adaptive Card envelope, NOT the classic connector's {"text": ...}. A
# classic "Incoming Webhook" connector ack'd {"text": ...} but Workflows returns
# HTTP 202 and silently posts nothing. The rendered Teams markdown goes in a
# TextBlock (wrap on); TextBlock supports the same MD subset (**bold**, [links]).
# ---------------------------------------------------------------------------
def _build_payload(text: str) -> dict:
    """Wrap the rendered markdown in the Workflows Adaptive Card envelope."""
    return {
        "type": "message",
        "attachments": [
            {
                "contentType": "application/vnd.microsoft.card.adaptive",
                "content": {
                    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.4",
                    "body": [{"type": "TextBlock", "text": text, "wrap": True}],
                },
            }
        ],
    }


def _post_to_webhook(url: str, text: str) -> tuple[bool, str]:
    # The one place a message leaves the machine. While a test run is in
    # progress -- the runners set the marker for their own process tree and
    # nothing else -- nothing posts, whatever variable a suite found.
    # An
    # engineer's own shell has no marker, so a real send beside a running suite
    # still works: that is the normal state of a working day.
    if os.environ.get(env_test_run_marker()):
        return False, "refused: a test run does not post to a webhook"
    """POST the rendered markdown to a Teams webhook. Returns (ok, detail)."""
    payload = json.dumps(_build_payload(text)).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=_POST_TIMEOUT_SECONDS) as resp:
            code = resp.getcode()
            if 200 <= code < 300:
                return True, f"HTTP {code}"
            return False, f"HTTP {code}"
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}: {str(e.reason)[:120]}"
    except Exception as e:  # noqa: BLE001 -- network error, timeout, malformed URL: a failed send, never a raise
        return False, f"{type(e).__name__}: {str(e)[:120]}"


# ---------------------------------------------------------------------------
# Public entry point — send.
# ---------------------------------------------------------------------------
def send(message: dict, config: dict | None = None) -> dict:
    """Send a message object to Teams. Never raises into the caller.

    Returns { "status", "detail", ... } where status is one of
    ok | dry-run | disabled | rejected | skipped | error.
    """
    caller = (message or {}).get("caller", "unknown") if isinstance(message, dict) else "unknown"
    source = f"comms/{caller}"

    try:
        cfg = config if config is not None else _load_config()
        communication = cfg.get("communication", {}) or {}

        # Step 1 -- the master switch. Checked first, before anything else.
        if not cfg.get("features", {}).get("communication", False):
            detail = f"features.communication off for org '{cfg.get('activeOrg', '?')}'"
            log_writer.write_log("WARN", source, f"disabled -- {detail}")
            return {"status": "disabled", "detail": detail}

        # Step 2 — validate the message object.
        if not isinstance(message, dict):
            log_writer.write_log("WARN", source, "rejected -- message is not an object")
            return {"status": "rejected", "detail": "message must be an object"}
        missing = [f for f in _REQUIRED_FIELDS if not message.get(f)]
        if missing:
            detail = f"missing required field(s): {', '.join(missing)}"
            log_writer.write_log("WARN", source, f"rejected -- {detail}")
            return {"status": "rejected", "detail": detail}
        if message.get("tone") not in _VALID_TONES:
            detail = f"invalid tone '{message.get('tone')}' (expected {'|'.join(_VALID_TONES)})"
            log_writer.write_log("WARN", source, f"rejected -- {detail}")
            return {"status": "rejected", "detail": detail}
        if "sections" in message and not isinstance(message["sections"], list):
            log_writer.write_log("WARN", source, "rejected -- sections must be a list")
            return {"status": "rejected", "detail": "sections must be a list"}

        # Step 3 — resolve recipient.
        resolved = _resolve_recipient(message["recipient"], communication)
        if not resolved["ok"]:
            log_writer.write_log("WARN", source, f"skipped -- {resolved['reason']}")
            return {"status": "skipped", "detail": resolved["reason"]}

        rendered = _render(message)
        target = {"recipient": message["recipient"], "display": resolved["display"]}

        # Step 4 — dry run: honor steps 1-3, then skip the POST.
        if message.get("dryRun"):
            log_writer.write_log("CMD", source, f"dry-run -- would post to '{message['recipient']}'")
            return {"status": "dry-run", "detail": "would post (not sent)", "target": target, "payload": rendered}

        # Step 5 — POST (no automatic retry).
        ok, post_detail = _post_to_webhook(resolved["url"], rendered)
        if not ok:
            log_writer.write_log("ERR", source, f"error -- {post_detail}")
            return {"status": "error", "detail": post_detail, "target": target}

        # Step 6 — success.
        log_writer.write_log("CMD", source, f"ok -- posted to '{message['recipient']}' ({post_detail})")
        return {"status": "ok", "detail": post_detail, "target": target}

    except Exception as e:  # noqa: BLE001 -- the engine never raises out to the caller's workflow
        log_writer.write_log("ERR", source, f"error -- unexpected: {type(e).__name__}: {str(e)[:160]}")
        return {"status": "error", "detail": f"unexpected: {type(e).__name__}"}
