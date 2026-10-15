"""The provider profile: the one place the agent calls a model from.

Two routes ask a model for text -- ``POST /pr-comments/{filename}/suggest``
(a draft reply to a review thread) and ``POST /rewrite`` (tidy a notes box).
Each used to carry its own copy of the transport, its own model id as a
literal and its own idea of what a missing key looked like (a 502 from a
failed call). This module is the profile they share:

* the MODEL is ``ai.model`` in config -- ``config.default.json`` ships a
  value, ``config.local.json`` overrides it, and ``AddPRReview`` reads the
  same key for its default, so one setting names the model for every half;
* the KEY is ``ANTHROPIC_API_KEY`` in the environment, or ``CLAUDE_API_KEY``
  as the fallback name ``.env.example`` documents and the CLI already honours;
* the TRANSPORT is the official SDK, imported lazily so an agent on a machine
  that never installed it still starts and still serves every other route.

A route that cannot call the model says so BEFORE it builds anything, as a
``ModelUnavailable`` with a sentence a person can act on; the routes answer
**412** with that sentence. 412 is "the route exists and the request was fine;
a precondition on this machine is not met" -- not a 502, which would say the
model failed.
"""

from __future__ import annotations

from .config import anthropic_api_key, load_config

# The shipped fallback when neither config file names a model. The same string
# is in config.default.json, so a reader of either sees the same answer; this
# copy exists for an agent run against a config.default.json that predates the
# key.
DEFAULT_MODEL = "claude-opus-5-5"

# How hard the model thinks before answering. Both callers want a short,
# well-formed reply, not a plan: low effort is the cheap end of the dial and
# plenty for forty words of JSON.
EFFORT = "low"

NO_MODEL_KEY_DETAIL = (
    "No model key: set ANTHROPIC_API_KEY in the agent's environment (see .env.example). "
    "GET /api/env reports anthropicConfigured."
)
NO_SDK_DETAIL = (
    "The anthropic package is not installed in the agent's Python: run pip install -r agent/requirements.txt."
)


class ModelUnavailable(RuntimeError):
    """A precondition for calling the model is not met on this machine.

    The message is the sentence the route serves as its 412 detail.
    """


def model_id() -> str:
    """The model every model-assisted route calls: ``ai.model`` in config."""
    ai = load_config().get("ai") or {}
    value = ai.get("model") if isinstance(ai, dict) else None
    if isinstance(value, str) and value.strip():
        return value.strip()
    return DEFAULT_MODEL


def _client():
    """The SDK client, or a stated reason there is none.

    The import is inside the function on purpose: ``anthropic`` is a runtime
    dependency of two routes, not of the agent, and an agent that cannot
    import it still has to serve the other forty.
    """
    key = anthropic_api_key()
    if not key:
        raise ModelUnavailable(NO_MODEL_KEY_DETAIL)
    try:
        import anthropic  # noqa: WPS433 -- deliberately lazy, see above
    except ImportError as exc:  # pragma: no cover -- exercised by stubbing the import
        raise ModelUnavailable(NO_SDK_DETAIL) from exc
    return anthropic.AsyncAnthropic(api_key=key, timeout=60.0, max_retries=2)


async def complete(prompt: str, *, system: str, max_tokens: int = 1024) -> str:
    """One user turn in, the model's text out.

    Raises ``ModelUnavailable`` before any network call when there is no key or
    no SDK. Anything the SDK raises after that (a 4xx from the API, a timeout)
    propagates; the route maps it to a 502, because by then the model really
    did fail.
    """
    client = _client()
    response = await client.messages.create(
        model=model_id(),
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": prompt}],
        output_config={"effort": EFFORT},
    )
    return "".join(block.text for block in response.content if getattr(block, "type", "") == "text").strip()


def describe() -> dict:
    """What ``/env`` can say about the profile: the model, and whether a key is set."""
    return {"model": model_id(), "configured": bool(anthropic_api_key()), "sdk": _sdk_installed()}


def _sdk_installed() -> bool:
    try:
        import anthropic  # noqa: F401
    except ImportError:
        return False
    return True


__all__ = [
    "DEFAULT_MODEL",
    "EFFORT",
    "NO_MODEL_KEY_DETAIL",
    "NO_SDK_DETAIL",
    "ModelUnavailable",
    "complete",
    "describe",
    "model_id",
]
