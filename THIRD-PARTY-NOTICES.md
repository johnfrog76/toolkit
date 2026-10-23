# Third-party notices

ToolKit is released under the [MIT License](LICENSE). It depends on open-source packages, each under
its own license, and it ships some pictures, scenes and sound; this page records what the license scans
found and where every font, picture and clip came from, so a reader can see what is in the web bundle,
the agent and the repository without running anything. Nothing copyleft is bundled into the web build.

The scans, so they can be repeated:

```bash
cd web && npx license-checker@25.0.1 --production --summary    # the web bundle's packages
npm run license:check                                          # the same scan, failing on any license not listed below
python -m venv .venv && .venv/bin/pip install -r agent/requirements.txt pip-licenses && .venv/bin/pip-licenses
```

(On Windows the interpreter is `python` and the venv's scripts are under `.venv\Scripts\`.)

This page is held true by `python Scripts/third_party_notices.py --check` (and `Tests/test_third_party_notices.py`,
which runs it): the web list below is generated from `web/package-lock.json` and `--write` rewrites it; the agent's
requirements must all be named; and every font, picture or sound file in the repository, and every file
served from `web/public/`, must be covered by an entry under "Fonts, artwork and audio".

## Web UI (`web/`), production dependencies

The list below is generated; do not edit it by hand. It is what `npm run license:check` scans: the packages the
lockfile does not mark as development-only.

<!-- markdownlint-disable MD001 -- the generator below names each license group a level-four heading under this level-two one -->
<!-- notices:npm begin -->

What ships in the browser bundle: 250 packages, besides the web package itself (`toolkit-web`, MIT). Every one is under a permissive license.

| License | Packages |
| --- | --- |
| MIT | 232 |
| ISC | 12 |
| 0BSD | 1 |
| Apache-2.0 | 1 |
| BSD | 1 |
| BSD-2-Clause | 1 |
| BSD-3-Clause | 1 |
| MIT AND ISC | 1 |

#### MIT (232)

| Package | Version |
| --- | --- |
| `@babel/runtime` | 7.29.2 |
| `@emotion/hash` | 0.9.2 |
| `@floating-ui/core` | 1.8.0 |
| `@floating-ui/devtools` | 0.2.3 |
| `@floating-ui/dom` | 1.8.0 |
| `@floating-ui/utils` | 0.2.12 |
| `@fluentui/keyboard-keys` | 9.0.9 |
| `@fluentui/priority-overflow` | 9.4.3 |
| `@fluentui/react-accordion` | 9.12.5 |
| `@fluentui/react-alert` | 9.0.2-beta.1 |
| `@fluentui/react-aria` | 9.17.16 |
| `@fluentui/react-avatar` | 9.11.9 |
| `@fluentui/react-badge` | 9.5.7 |
| `@fluentui/react-breadcrumb` | 9.4.7 |
| `@fluentui/react-button` | 9.11.2 |
| `@fluentui/react-card` | 9.7.4 |
| `@fluentui/react-carousel` | 9.9.15 |
| `@fluentui/react-checkbox` | 9.6.6 |
| `@fluentui/react-color-picker` | 9.3.2 |
| `@fluentui/react-combobox` | 9.17.8 |
| `@fluentui/react-components` | 9.74.10 |
| `@fluentui/react-context-selector` | 9.2.21 |
| `@fluentui/react-dialog` | 9.18.6 |
| `@fluentui/react-divider` | 9.7.6 |
| `@fluentui/react-drawer` | 9.13.5 |
| `@fluentui/react-field` | 9.5.6 |
| `@fluentui/react-icons` | 2.0.344 |
| `@fluentui/react-image` | 9.4.6 |
| `@fluentui/react-infobutton` | 9.0.1-beta.1 |
| `@fluentui/react-infolabel` | 9.4.28 |
| `@fluentui/react-input` | 9.8.8 |
| `@fluentui/react-jsx-runtime` | 9.4.7 |
| `@fluentui/react-label` | 9.4.6 |
| `@fluentui/react-link` | 9.8.6 |
| `@fluentui/react-list` | 9.7.0 |
| `@fluentui/react-menu` | 9.25.7 |
| `@fluentui/react-message-bar` | 9.7.8 |
| `@fluentui/react-motion` | 9.16.5 |
| `@fluentui/react-motion-components-preview` | 0.15.10 |
| `@fluentui/react-nav` | 9.4.8 |
| `@fluentui/react-overflow` | 9.9.5 |
| `@fluentui/react-persona` | 9.7.11 |
| `@fluentui/react-popover` | 9.14.10 |
| `@fluentui/react-portal` | 9.8.17 |
| `@fluentui/react-positioning` | 9.23.4 |
| `@fluentui/react-progress` | 9.5.7 |
| `@fluentui/react-provider` | 9.22.22 |
| `@fluentui/react-radio` | 9.6.7 |
| `@fluentui/react-rating` | 9.4.7 |
| `@fluentui/react-search` | 9.4.8 |
| `@fluentui/react-select` | 9.5.7 |
| `@fluentui/react-shared-contexts` | 9.26.4 |
| `@fluentui/react-skeleton` | 9.7.7 |
| `@fluentui/react-slider` | 9.6.7 |
| `@fluentui/react-spinbutton` | 9.6.8 |
| `@fluentui/react-spinner` | 9.8.7 |
| `@fluentui/react-swatch-picker` | 9.6.3 |
| `@fluentui/react-switch` | 9.7.7 |
| `@fluentui/react-table` | 9.19.23 |
| `@fluentui/react-tabs` | 9.12.6 |
| `@fluentui/react-tabster` | 9.26.19 |
| `@fluentui/react-tag-picker` | 9.10.6 |
| `@fluentui/react-tags` | 9.9.8 |
| `@fluentui/react-teaching-popover` | 9.7.8 |
| `@fluentui/react-text` | 9.6.21 |
| `@fluentui/react-textarea` | 9.7.8 |
| `@fluentui/react-theme` | 9.2.2 |
| `@fluentui/react-toast` | 9.8.5 |
| `@fluentui/react-toolbar` | 9.8.6 |
| `@fluentui/react-tooltip` | 9.10.8 |
| `@fluentui/react-tree` | 9.16.9 |
| `@fluentui/react-utilities` | 9.27.0 |
| `@fluentui/react-virtualizer` | 9.0.0-alpha.116 |
| `@fluentui/tokens` | 1.0.0-alpha.24 |
| `@griffel/core` | 1.21.4 |
| `@griffel/react` | 1.7.8 |
| `@griffel/style-types` | 1.4.3 |
| `@reduxjs/toolkit` | 2.13.0 |
| `@remix-run/route-pattern` | 0.22.1 |
| `@standard-schema/spec` | 1.1.0 |
| `@standard-schema/utils` | 0.3.0 |
| `@types/d3-array` | 3.2.2 |
| `@types/d3-color` | 3.1.3 |
| `@types/d3-ease` | 3.0.2 |
| `@types/d3-interpolate` | 3.0.4 |
| `@types/d3-path` | 3.1.1 |
| `@types/d3-scale` | 4.0.9 |
| `@types/d3-shape` | 3.1.8 |
| `@types/d3-time` | 3.0.4 |
| `@types/d3-timer` | 3.0.2 |
| `@types/debug` | 4.1.13 |
| `@types/estree` | 1.0.8 |
| `@types/estree-jsx` | 1.0.5 |
| `@types/hast` | 3.0.4 |
| `@types/mdast` | 4.0.4 |
| `@types/ms` | 2.1.0 |
| `@types/react` | 19.3.0 |
| `@types/react-dom` | 19.3.0 |
| `@types/unist` | 2.0.11 |
| `@types/unist` | 3.0.3 |
| `@types/use-sync-external-store` | 0.0.6 |
| `bail` | 2.0.2 |
| `ccount` | 2.0.1 |
| `character-entities` | 2.0.2 |
| `character-entities-html4` | 2.1.0 |
| `character-entities-legacy` | 3.0.0 |
| `character-reference-invalid` | 2.0.1 |
| `clsx` | 2.1.1 |
| `comma-separated-tokens` | 2.0.3 |
| `cookie-es` | 3.1.1 |
| `csstype` | 3.2.3 |
| `debug` | 4.4.3 |
| `decimal.js-light` | 2.5.1 |
| `decode-named-character-reference` | 1.3.0 |
| `dequal` | 2.0.3 |
| `devlop` | 1.1.0 |
| `embla-carousel` | 8.6.0 |
| `embla-carousel-autoplay` | 8.6.0 |
| `embla-carousel-fade` | 8.6.0 |
| `es-toolkit` | 1.46.1 |
| `escape-string-regexp` | 5.0.0 |
| `estree-util-is-identifier-name` | 3.0.0 |
| `eventemitter3` | 5.0.4 |
| `extend` | 3.0.2 |
| `hast-util-from-parse5` | 8.0.3 |
| `hast-util-parse-selector` | 4.0.0 |
| `hast-util-raw` | 9.1.0 |
| `hast-util-sanitize` | 5.0.2 |
| `hast-util-to-jsx-runtime` | 2.3.6 |
| `hast-util-to-parse5` | 8.0.1 |
| `hast-util-whitespace` | 3.0.0 |
| `hastscript` | 9.0.1 |
| `html-url-attributes` | 3.0.1 |
| `html-void-elements` | 3.0.0 |
| `immer` | 11.1.21 |
| `inline-style-parser` | 0.2.7 |
| `is-alphabetical` | 2.0.1 |
| `is-alphanumerical` | 2.0.1 |
| `is-decimal` | 2.0.1 |
| `is-hexadecimal` | 2.0.1 |
| `is-plain-obj` | 4.1.0 |
| `keyborg` | 3.498.0 |
| `longest-streak` | 3.1.0 |
| `luxon` | 3.7.2 |
| `markdown-table` | 3.0.4 |
| `mdast-util-find-and-replace` | 3.0.2 |
| `mdast-util-from-markdown` | 2.0.3 |
| `mdast-util-gfm` | 3.1.0 |
| `mdast-util-gfm-autolink-literal` | 2.0.1 |
| `mdast-util-gfm-footnote` | 2.1.0 |
| `mdast-util-gfm-strikethrough` | 2.0.0 |
| `mdast-util-gfm-table` | 2.0.0 |
| `mdast-util-gfm-task-list-item` | 2.0.0 |
| `mdast-util-mdx-expression` | 2.0.1 |
| `mdast-util-mdx-jsx` | 3.2.0 |
| `mdast-util-mdxjs-esm` | 2.0.1 |
| `mdast-util-phrasing` | 4.1.0 |
| `mdast-util-to-hast` | 13.2.1 |
| `mdast-util-to-markdown` | 2.1.2 |
| `mdast-util-to-string` | 4.0.0 |
| `micromark` | 4.0.2 |
| `micromark-core-commonmark` | 2.0.3 |
| `micromark-extension-gfm` | 3.0.0 |
| `micromark-extension-gfm-autolink-literal` | 2.1.0 |
| `micromark-extension-gfm-footnote` | 2.1.0 |
| `micromark-extension-gfm-strikethrough` | 2.1.0 |
| `micromark-extension-gfm-table` | 2.1.1 |
| `micromark-extension-gfm-tagfilter` | 2.0.0 |
| `micromark-extension-gfm-task-list-item` | 2.1.0 |
| `micromark-factory-destination` | 2.0.1 |
| `micromark-factory-label` | 2.0.1 |
| `micromark-factory-space` | 2.0.1 |
| `micromark-factory-title` | 2.0.1 |
| `micromark-factory-whitespace` | 2.0.1 |
| `micromark-util-character` | 2.1.1 |
| `micromark-util-chunked` | 2.0.1 |
| `micromark-util-classify-character` | 2.0.1 |
| `micromark-util-combine-extensions` | 2.0.1 |
| `micromark-util-decode-numeric-character-reference` | 2.0.2 |
| `micromark-util-decode-string` | 2.0.1 |
| `micromark-util-encode` | 2.0.1 |
| `micromark-util-html-tag-name` | 2.0.1 |
| `micromark-util-normalize-identifier` | 2.0.1 |
| `micromark-util-resolve-all` | 2.0.1 |
| `micromark-util-sanitize-uri` | 2.0.1 |
| `micromark-util-subtokenize` | 2.1.0 |
| `micromark-util-symbol` | 2.0.1 |
| `micromark-util-types` | 2.0.2 |
| `ms` | 2.1.3 |
| `parse-entities` | 4.0.2 |
| `parse5` | 7.3.0 |
| `property-information` | 7.1.0 |
| `react` | 19.3.1 |
| `react-confetti` | 6.4.0 |
| `react-dom` | 19.3.1 |
| `react-is` | 19.2.6 |
| `react-markdown` | 10.1.0 |
| `react-redux` | 9.3.0 |
| `react-router` | 8.5.0 |
| `recharts` | 3.10.1 |
| `redux` | 5.0.1 |
| `redux-thunk` | 3.1.0 |
| `rehype-raw` | 7.0.0 |
| `rehype-sanitize` | 6.0.0 |
| `remark-gfm` | 4.0.1 |
| `remark-parse` | 11.0.0 |
| `remark-rehype` | 11.1.2 |
| `remark-stringify` | 11.0.0 |
| `reselect` | 5.2.0 |
| `rtl-css-js` | 1.16.1 |
| `scheduler` | 0.28.0 |
| `space-separated-tokens` | 2.0.2 |
| `stringify-entities` | 4.0.4 |
| `style-to-js` | 1.1.21 |
| `style-to-object` | 1.0.14 |
| `stylis` | 4.4.0 |
| `tabster` | 8.8.1 |
| `tiny-invariant` | 1.3.3 |
| `trim-lines` | 3.0.1 |
| `trough` | 2.2.0 |
| `unified` | 11.0.5 |
| `unist-util-is` | 6.0.1 |
| `unist-util-position` | 5.0.0 |
| `unist-util-stringify-position` | 4.0.0 |
| `unist-util-visit` | 5.1.0 |
| `unist-util-visit-parents` | 6.0.2 |
| `use-sync-external-store` | 1.6.0 |
| `vfile` | 6.0.3 |
| `vfile-location` | 5.0.3 |
| `vfile-message` | 4.0.3 |
| `web-namespaces` | 2.0.1 |
| `zwitch` | 2.0.4 |

#### ISC (12)

| Package | Version |
| --- | --- |
| `@ungap/structured-clone` | 1.3.0 |
| `d3-array` | 3.2.4 |
| `d3-color` | 3.1.0 |
| `d3-format` | 3.1.2 |
| `d3-interpolate` | 3.0.1 |
| `d3-path` | 3.1.0 |
| `d3-scale` | 4.0.2 |
| `d3-shape` | 3.2.0 |
| `d3-time` | 3.1.0 |
| `d3-time-format` | 4.1.0 |
| `d3-timer` | 3.0.1 |
| `internmap` | 2.0.3 |

#### 0BSD (1)

| Package | Version |
| --- | --- |
| `tslib` | 2.8.1 |

#### Apache-2.0 (1)

| Package | Version |
| --- | --- |
| `@swc/helpers` | 0.5.21 |

#### BSD (1)

| Package | Version |
| --- | --- |
| `tween-functions` | 1.2.0 |

#### BSD-2-Clause (1)

| Package | Version |
| --- | --- |
| `entities` | 6.0.1 |

#### BSD-3-Clause (1)

| Package | Version |
| --- | --- |
| `d3-ease` | 3.0.1 |

#### MIT AND ISC (1)

| Package | Version |
| --- | --- |
| `victory-vendor` | 37.3.6 |

<!-- notices:npm end -->
<!-- markdownlint-enable MD001 -->

The check `npm run license:check` (run from `web/`) fails if a production dependency arrives under a
license outside MIT, ISC, Apache-2.0, BSD-2-Clause, BSD-3-Clause, 0BSD or MIT AND ISC.

### Web UI, development dependencies (not bundled)

The build and test tooling adds licenses that are not in the bundle and are not distributed with it:
MPL-2.0 (`lightningcss` and its platform binary, used by the build), CC-BY-4.0 (`caniuse-lite`, browser
data), Python-2.0 (`argparse`), BlueOak-1.0.0 (`minimatch`) and `(MIT OR CC0-1.0)` (`type-fest`). They run
on a developer's machine or in CI and never reach a user's browser.

## Agent (`agent/`), runtime dependencies

From `agent/requirements.txt`, with the packages they pull in, as resolved by `pip-licenses` on Python 3.12
on 2026-10-10 (the requirements are lower bounds, so a later install may resolve newer versions):

| License | Package | Version |
| --- | --- | --- |
| MIT | `fastapi` | 0.143.0 |
| MIT | `pydantic` | 2.14.0 |
| MIT | `pydantic_core` | 2.50.0 |
| MIT | `anyio` | 4.15.1 |
| MIT | `annotated-doc` | 0.0.5 |
| MIT | `annotated-types` | 0.8.0 |
| MIT | `typing-inspection` | 0.4.4 |
| MIT | `httptools` | 0.9.0 |
| MIT | `jiter` | 0.17.0 |
| MIT | `anthropic` | 1.13.0 |
| MIT | `docstring_parser` | 0.18.0 |
| MIT | `h11` | 0.16.0 |
| MIT | `PyYAML` | 6.0.3 |
| MIT | `watchfiles` | 1.3.0 |
| BSD-3-Clause | `uvicorn` | 0.54.0 |
| BSD-3-Clause | `starlette` | 1.7.0 |
| BSD-3-Clause | `click` | 8.5.0 |
| BSD-3-Clause | `httpx2` | 2.13.1 |
| BSD-3-Clause | `httpcore2` | 2.13.1 |
| BSD-3-Clause | `idna` | 3.20 |
| BSD-3-Clause | `python-dotenv` | 1.2.4 |
| BSD-3-Clause | `websockets` | 17.2 |
| Apache-2.0 | `opentelemetry-api` | 1.45.1 |
| Apache-2.0 and MIT (dual) | `sniffio` | 1.3.1 |
| PSF-2.0 | `typing_extensions` | 4.16.0 |

The agent's test dependencies (`agent/requirements-dev.txt`) are not installed for a user: `pytest`, `pluggy`,
`iniconfig` and `colorama` (MIT or BSD), `packaging` (Apache-2.0 or BSD-2-Clause), `Pygments` (BSD-2-Clause),
`httpx` and `httpcore` (BSD-3-Clause), and `certifi` (MPL-2.0, which is used unmodified and is not
redistributed with the project).

## Fonts, artwork and audio

### Fonts

No font file is bundled, and nothing is fetched from a font service. The web UI names fonts in CSS stacks and
the reader's system answers with whatever it has: Fluent's token stacks (Segoe UI, system-ui and the platform's
own faces), Helvetica Neue, Cascadia Code, Fira Code, Consolas and, in the Lounge's aquarium scenes, IBM Plex Sans
as a first choice that falls back to Segoe UI. None of them is loaded, so there is nothing here to license; a font
file added to the repository must be listed in this section, or the check above fails.

One font's outlines are in the tree without the font: the wordmark (`web/src/shared/Wordmark.tsx`) draws
"ToolKit" and its faces as SVG paths in `web/src/shared/wordmarkPaths.ts`, set in **Inter** Bold by the
Inter Project Authors under the SIL Open Font License 1.1 and outlined by `web/tests/outline-wordmark.mjs`
from a font file that is not committed. The OFL permits outlines embedded this way; the font itself is
neither bundled nor named in any CSS stack.

### The project's own artwork

Released under the same MIT License as the code.

| Where | What | Source |
| --- | --- | --- |
| `samples/covers/` | The twenty sample covers: the `.webp` files, the `svg/` sources and `make-covers.mjs` | Drawn as SVG by `make-covers.mjs` and sliced to WebP; no outside image is used |
| `samples/hub/*/assets/*/cover.webp` | The covers the sample hub's cards wear (ten files) | Byte-for-byte copies of the covers above, attached with the `Cover` verb |
| `docs/images/board.jpg`, `docs/images/board-mobile.jpg`, `docs/images/board-in-action.gif` | The board in the README and the guides | Screenshots of this product running on the sample hub (`docs/images/README.md`) |
| `docs/images/lounge-zen-temple-skin.png`, `docs/images/team-agile-stage-reference.png` | Two design references | Screenshots of a zen-temple scene and of the Remote Standup grid, from the project owner's CSS Wasteland studio; kept in the docs and not part of the web build |
| `docs/images/stage.png` | The cast's nine-seat stage, for the README | Rendered from the project's own cast source by `web/tests/render-cast.mjs` (`docs/images/README.md`) |
| `docs/logo.txt`, `docs/logo-faces-preview.html` | The ToolKit mark, as ASCII, and a page that draws its faces | Drawn for the project |
| `web/index.html` | The browser-tab icon, three bars inline as an SVG | Drawn for the project |
| `web/src/modules/solitaireAgile/stage/cast.tsx` | The Team Agile stage's cast: the nine tiles, tints and webcam scenes | Quoted by copy from the Remote Standup in the project owner's CSS Wasteland studio, which the file's header states; the studio's bios and lines are not carried over |
| `web/public/lounge/temple.html` | The Lounge's zen temple scene | Ported from the zen-development deck in the same studio |
| `web/public/lounge/aquarium/` | The Lounge's seven aquarium scenes | Ported by `web/tools/port-aquarium.mjs` from aquarium-saver (MIT, the same licence as this repository's `LICENSE`, by the same owner), as each file's header says |
| `web/src/modules/deck/decks/cat-dev.tsx`, `web/src/modules/deck/decks/connected-deck-trailer.tsx` | The trailer and its Cat Dev figure | Copied from Connected Deck (MIT, github.com/johnfrog76/connected-deck), by the same owner |
| `web/src/modules/deck/decks/the-toolkit.tsx`, `web/src/modules/deck/decks/toolkit-figures.tsx` | The deck "Introducing ToolKit" and its figures | Built in the project owner's CSS Wasteland studio and carried here byte-identical |

### Audio

| Where | What | Source |
| --- | --- | --- |
| `web/src/modules/deck/voices/` | The decks' baked narration: one clip per slide in two voices, Jenny (`en-US-JennyNeural`) and Brian (`en-US-BrianNeural`) | Synthetic speech from Azure neural text-to-speech voices, spoken from the decks' own `Say` text and baked in the studio; the trailer's clips were copied from Connected Deck. Microsoft's guidance for the service is that audio generated from your own text may be used and distributed without a license or royalty back to Microsoft, with three conditions this repository meets: the input text is the project's own (the decks' Say lines), the voices are the standard neural voices rather than branded or custom ones, and synthetic audio is disclosed, which this row is. The Microsoft Product Terms for Azure are the governing text |

### Third-party artwork

| Where | What | License |
| --- | --- | --- |
| `web/src/modules/deck/engine/CopyLinkButton.tsx`, `web/src/modules/deck/engine/GiveawayButton.tsx` | The GitHub mark, as an inline SVG path (Octicons `mark-github`) | MIT, from GitHub's Octicons |

The icons the web UI draws from `@fluentui/react-icons` are that package's, covered by its MIT license in the list
above. No other third-party image, icon set, sound or scene is copied into the repository.
