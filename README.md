# BG Tracker

A standalone World of Warcraft **Burning Crusade Classic** addon. No libraries or dependencies are required.

## Disclaimer
One-shot with GPT-6 Astra

## Install

Copy the **BGTracker** folder into the `Interface/AddOns` directory of your TBC Classic installation. The layout must be `Interface/AddOns/BGTracker/BGTracker.toc`, without an extra nested folder. Restart the game and enable **BG Tracker** in the character selection screen's AddOns list. If your client marks it out of date, enable **Load out of date AddOns**; the manifest targets interface versions 20505 and 20504.

## Use

- Tracking starts automatically when you enter a battleground. Arenas and world PvP are excluded.
- Click the banner icon on the minimap, or type `/bgt` or `/bgtracker`, to open the history table.
- Drag the icon around the minimap. Its position is saved per character.
- Drag the history window to move it; press Escape to close it. Use Previous/Next or the mouse wheel to page through matches.
- Each row shows local BG start time, BG name, duration, HK honor, additional honor, total honor, and result. Wins are green; losses are red. A current match updates live.
- History and an active match survive UI reloads and normal logouts. The newest 1,000 completed/left matches are retained per character.

## How the numbers work

**HK honor** sums the amounts in the client's honorable-kill honor messages. The client describes these as estimated honor, so these are recorded estimates, not a guarantee of the final currency balance. **Additional honor** sums non-HK honor award messages received inside the battleground, including objective and completion awards. The scoreboard's honor column is not treated as a second source, avoiding double counting. Honor awarded outside the BG (such as quest turn-ins) is excluded.

Parsing uses the client's localized `COMBATLOG_HONORGAIN`, `COMBATLOG_HONORGAIN_NO_RANK` (when available), and `COMBATLOG_HONORAWARD` format strings. An unrecognized honor message marks the row with `*`; hover for details. Honor before the addon started or while disconnected cannot be recovered. Joining an already-running match is marked with `*` when the game timer exceeds two minutes; resuming after more than 15 seconds offline is also marked.

Start time and duration use the game's battleground runtime, including preparation time if the client includes it. The start time can precede your entry when joining mid-match. Duration freezes when a winner is reported; honor continues to collect until you leave so delayed completion rewards are included. If the runtime is temporarily unavailable, elapsed time since tracking began is used.

The result compares the winning team with your own scoreboard team, supporting same-faction battlegrounds. If your team cannot be read, the result remains **Unknown**. Leaving before the outcome is observed records **Left**; an unrecoverable session after login records **Interrupted**. Neither is counted as a loss. Draws are also separate.

## Verification

Run `lua5.1 tests/run.lua` from this project directory for the mocked event, tracking, and UI checks. Run `luac -p BGTracker/Tracker.lua BGTracker/UI.lua BGTracker/Core.lua` for syntax validation. These checks do not replace testing inside the game.

In-game smoke test: enter a BG, earn HK and objective honor, use `/reload`, finish the match, wait for completion honor, and leave. Confirm one history row, the correct result/color, unchanged duration after the result, and separate honor columns. Try dragging/clicking the minimap button and reopening the history after relogging.

API reference: [Blizzard's TBC scoreboard source mirror](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/Interface/AddOns/Blizzard_FrameXML/TBC/WorldStateFrame.lua).

## Screenshots
<img width="1487" height="838" alt="Screenshot From 2026-09-17 14-43-11" src="https://github.com/user-attachments/assets/dc975505-9e1b-4974-aae3-406d17c26bb0" />
