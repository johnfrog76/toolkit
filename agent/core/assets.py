"""A card's pictures: the reader of its ``**Cover:**`` / ``**Before:**`` lines,
and ``GET /api/assets/{space}/{card key}/{file}``, the route that serves them.

docs/hub/cards.md, "A card's pictures". A card names its picture with
one footer line, relative to the card's own folder::

    **Cover:** ../assets/<card key>/cover.png

so the line is right from ``current/`` and ``archive/`` alike. The CLI's
``Cover`` verb is the one writer (``Scripts/Set-CardCover.ps1``); this module
only reads, and the route writes nothing.

**The line is the truth.** ``card_image`` keeps the rule
``Resolve-P20CardImage`` in ``Scripts/Add-CardImage.ps1`` keeps, row for row --
``Tests/fixtures/parsers/covers.json`` is the one table both suites assert: the
file the line names, only when it resolves INSIDE that Space's ``assets/``,
exactly ``<card key>/<file>``, is an image type, and is there. Anything else is
no picture, and the model serves ``null``.

Core, no flag: cards cannot be turned off, and neither can their cover.
"""

import os
import re
import shutil
import tempfile
import time
from pathlib import Path
from urllib.parse import quote

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .config import API_PREFIX, hub_root, load_config
from .consts import cover_extensions, cover_max_bytes, folder_assets, stamp_before, stamp_cover

api = APIRouter()

# The content type is the extension's, and only an image type is ever served.
_CONTENT_TYPES = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "webp": "image/webp",
    "gif": "image/gif",
}


def _image_line(content: str, stamp: str) -> str | None:
    """The value of the card's line for ``stamp`` as written, or None."""
    m = re.search(r"(?m)^" + re.escape(stamp) + r"[ \t]*(\S[^\r\n]*?)[ \t]*\r?$", content or "")
    return m.group(1) if m else None


def _inside(child: str, parent: str) -> str | None:
    """``child`` relative to ``parent`` when it lies strictly inside it, else None.
    Both are already resolved; the comparison is the path's own, segment-wise."""
    try:
        rel = os.path.relpath(child, parent)
    except ValueError:  # another drive, on Windows
        return None
    if rel == os.curdir or rel == os.pardir or rel.startswith(os.pardir + os.sep) or os.path.isabs(rel):
        return None
    return rel


def card_image(content: str, card_path: Path, stamp: str) -> str | None:
    """The picture the card's ``stamp`` line names, as ``'<card key>/<file>'``
    inside its Space's ``assets/``, or None.

    The Space is the card's folder's parent: a card in ``<space>/current/`` or
    ``<space>/archive/`` keeps its pictures in ``<space>/assets/``.
    """
    value = _image_line(content, stamp)
    if not value:
        return None
    value = value.replace("\\", "/")
    if value.startswith("/") or re.match(r"^[A-Za-z]:", value) or "://" in value:
        return None
    card_dir = Path(card_path).parent
    assets = os.path.realpath(card_dir.parent / folder_assets())
    full = os.path.realpath(os.path.join(str(card_dir), value))
    rel = _inside(full, assets)
    if rel is None:
        return None
    segments = rel.replace("\\", "/").split("/")
    if len(segments) != 2 or not all(segments):
        return None
    ext = os.path.splitext(segments[1])[1].lstrip(".").lower()
    if ext not in cover_extensions():
        return None
    if not os.path.isfile(full):
        return None
    return "/".join(segments)


def image_url(space: str, rel: str | None) -> str | None:
    """The route's URL for a picture ``card_image`` found, or None."""
    if not rel or not space:
        return None
    key, name = rel.split("/", 1)
    return f"{API_PREFIX}/assets/{quote(space, safe='')}/{quote(key, safe='')}/{quote(name, safe='')}"


def card_images(content: str, card_path: Path, space: str) -> dict:
    """``{"cover": url|None, "before": url|None}`` -- the two fields the card
    model serves (docs/hub/cards.md, "The model, as the agent serves it")."""
    return {
        "cover": image_url(space, card_image(content, card_path, stamp_cover())),
        "before": image_url(space, card_image(content, card_path, stamp_before())),
    }


def _space_assets_dir(slug: str) -> Path | None:
    """``<promptsRoot>/<promptsFolder>/assets`` for the Space named ``slug``."""
    for space in load_config().get("spaces", []) or []:
        if space.get("slug") == slug:
            folder = space.get("promptsFolder") or ""
            base = hub_root() / folder if folder else hub_root()
            return base / folder_assets()
    return None


# GET /api/assets/{space}/{key}/{file}
class UploadResponse(BaseModel):
    path: str = ""  # the temp file the browser's bytes landed in, for `Cover <card> <path>`
    name: str = ""  # the file's name as it will be copied in (sanitised)
    bytes: int = 0


UPLOAD_PREFIX = "p20-upload-"
# A name the verb can take: the basename only, letters, digits, dot, dash and
# underscore. Anything else in what the browser sent is dropped, never written.
_SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")


def safe_upload_name(name: str) -> str:
    base = (name or "").replace("\\", "/").rsplit("/", 1)[-1]
    base = _SAFE_NAME.sub("-", base).strip(".-")
    return base or "image"


def upload_dir() -> Path:
    """A fresh temp folder per upload, under the system temp: never the hub."""
    return Path(tempfile.mkdtemp(prefix=UPLOAD_PREFIX))


# A folder this old is from an upload nobody attached (a cancelled dialog, a
# crashed agent); the sweep at agent start removes it.
STALE_UPLOAD_SECONDS = 24 * 60 * 60


def remove_upload(path: str) -> bool:
    """Remove the upload folder ``path`` lives in, once the verb that copied it is done.

    Only a real upload is ever touched: ``path`` must be a file directly inside a
    folder named ``p20-upload-*`` whose parent is the system temp directory. Anything
    else -- a card, a file in the hub, a flag, a link -- is left alone and False comes
    back."""
    try:
        folder = Path(path).parent
        temp = Path(tempfile.gettempdir())
        if not folder.name.startswith(UPLOAD_PREFIX) or folder.is_symlink() or not folder.is_dir():
            return False
        if os.path.normcase(os.path.realpath(folder.parent)) != os.path.normcase(os.path.realpath(temp)):
            return False
        shutil.rmtree(folder, ignore_errors=True)
        return not folder.exists()
    except (OSError, ValueError):
        return False


def sweep_stale_uploads(max_age: float = STALE_UPLOAD_SECONDS) -> int:
    """Remove ``p20-upload-*`` folders in the system temp older than ``max_age``
    seconds; returns how many went. Nothing else in the temp folder is touched."""
    removed = 0
    try:
        entries = list(os.scandir(tempfile.gettempdir()))
    except OSError:
        return 0
    now = time.time()
    for e in entries:
        try:
            if not e.name.startswith(UPLOAD_PREFIX) or e.is_symlink() or not e.is_dir(follow_symlinks=False):
                continue
            if now - e.stat(follow_symlinks=False).st_mtime < max_age:
                continue
            shutil.rmtree(e.path, ignore_errors=True)
            removed += not os.path.exists(e.path)
        except OSError:
            continue
    return removed


@api.post("/assets/upload", response_model=UploadResponse)
async def upload_asset(request: Request, name: str = ""):
    """The browser's door to a picture (spec 4.8, C2): the bytes land in a
    temp file and the path comes back (the bridge removes its folder when the
    verb that was handed the path has finished); the web then runs ``Cover <card> <path>``
    (or ``NewPrompt -Cover <path>``) through the bridge. The route writes NOTHING
    into the hub -- the verb is the one writer, and it is the verb that checks the
    card, picks the name in ``assets/<card key>/`` and writes the line. Refused
    here only for what the verb would refuse anyway, so the browser hears it
    before a shell starts: a type not in the list, a size over the limit, no bytes.
    The body is the raw file (no multipart: one fewer dependency, and a picture
    is one blob); ``name`` carries the file's name for its extension."""
    clean = safe_upload_name(name)
    ext = clean.rsplit(".", 1)[-1].lower() if "." in clean else ""
    allowed = cover_extensions()
    if ext not in allowed:
        raise HTTPException(
            status_code=400, detail=f"{clean or 'The file'} is not an image type Cover accepts ({', '.join(allowed)})."
        )
    body = await request.body()
    limit = cover_max_bytes()
    if len(body) == 0:
        raise HTTPException(status_code=400, detail="No bytes were sent.")
    if len(body) > limit:
        raise HTTPException(status_code=413, detail=f"{clean} is {len(body):,} bytes; Cover copies at most {limit:,}.")
    target = upload_dir() / clean
    target.write_bytes(body)
    return UploadResponse(path=str(target), name=clean, bytes=len(body))


@api.get("/assets/{space}/{key}/{file}")
async def get_asset(space: str, key: str, file: str):
    """One picture from a Space's ``assets/``. Resolved FIRST, then checked to lie
    inside that Space's ``assets/`` exactly one folder deep -- so no spelling of
    ``..`` reaches anything else -- and served only for an image type, with the
    content type from its extension. 404 for anything that is not that."""
    assets = _space_assets_dir(space)
    if assets is None:
        raise HTTPException(status_code=404, detail=f"No Space '{space}'")
    root = os.path.realpath(assets)
    full = os.path.realpath(os.path.join(root, key, file))
    rel = _inside(full, root)
    if rel is None or len(rel.replace("\\", "/").split("/")) != 2:
        raise HTTPException(status_code=404, detail="Not a picture in this Space's assets/")
    ext = os.path.splitext(full)[1].lstrip(".").lower()
    if ext not in cover_extensions() or ext not in _CONTENT_TYPES:
        raise HTTPException(status_code=404, detail="Not a picture in this Space's assets/")
    if not os.path.isfile(full):
        raise HTTPException(status_code=404, detail="No such picture")
    return FileResponse(full, media_type=_CONTENT_TYPES[ext])
