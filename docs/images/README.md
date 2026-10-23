# Images

Every picture here is taken from the SAMPLE hub (`samples/hub`) on a scratch first run -- never from
anyone's real hub, so there is no real name, address or note in any of them. The avatar says "you".

| File | What | How it was made |
| --- | --- | --- |
| `board.jpg` | the board, desktop, Seaglass | `Start` into a scratch folder, a scratch agent, Playwright at 1440x900 @2x on `/board` |
| `board-mobile.jpg` | the board on a phone (430x932) | the same, with a mobile context |
| `board-in-action.gif` | a commit and a pull request moving cards, Move to Done, and a card made from the **+** | the same run: the two card files are edited on disk (a commit bullet, a `PR URL:` line) and the board's own polling moves them |

Retake them when the board changes; a picture of a screen the product no longer has is worse than none.

## The generated picture

| File | What | How it was made |
| --- | --- | --- |
| `stage.png` | the cast's nine-seat stage, parked, light theme, reduced motion, 960 px wide at 2x | **Generated** -- `cd web && node tests/render-cast.mjs`. It mounts the cast's own components (`web/src/modules/solitaireAgile/stage/cast.tsx`, `seats.ts`) in a throwaway page and screenshots them; no hub, no agent. |

| `social-preview.png` | the landing page's banner, the page's first screen, 1280x640 -- the size GitHub shows as a repository's social preview | **Generated** -- `cd web && node tests/render-cast.mjs --preview`. It builds the landing page (`npm run build:landing`), serves it on a throwaway local port and screenshots the banner with everything below it hidden. A repository owner uploads it under Settings, Social preview; nothing in the tree can set it. |

Do not edit `stage.png` or `social-preview.png` by hand. Run the command when the cast or the seats change and commit the result; it is never run at build. The same source gives the same bytes on one machine (fixed viewport and scale, parked figures, no animation); the plates' monospace face is the machine's own, so lettering may differ slightly across machines.
