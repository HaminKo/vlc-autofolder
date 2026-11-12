# To do 6: Playlist window shows a re-opened file at the bottom (medium)

"it appeared on the bottom"

- **Problem / Goal:** in the built test folder (16 videos, date order), Ctrl+O on Episode 2.mkv again (To do 3 step A, manual test 8, 2026-11-11):
  - Episode 2 plays, once, and in VLC's own playlist it is 2nd. The rules-refresh case checks this order.
  - The playlist window shows it **at the bottom**.
  - Cause (known): the build moves the new copy into the old copy's place, and VLC 3.0's window doesn't show a script's moves (research/vlc-lua-api.md, "Playlist", `move`).
  - A re-sort had the same problem. It now deletes and re-adds the items instead, and the window was right in 5 sort changes by hand (decisions.md, "A re-sort deletes and re-adds").
- **Read first:**
  - `autofolder.lua`: `build`, `arrange`, `reorder`, `resort` (the re-add pattern, with the target worked out before deleting).
  - `autofolder_core.lua`: `match_items`, `target_order`, `front_moves`.
  - test_settings.lua `live` (how a re-add is checked: new ids).
- **Approach:** in a build, an item the window already shows is never moved. The items that would have to move are deleted and re-added in place, as `resort` does, with the target worked out first.
  - Kept: the playing item (it would restart) and the items already in the right order relative to it. The longest such run stays; `front_moves` already finds it for moves.
  - Probably one shared function for build and re-sort.
- **Ask the user:**
  - Re-add only the items that must move, or the whole folder on every build? *Suggested: only those that must move. On a share VLC re-reads ~12 files/s, so a re-add isn't free.*
  - A folder file the user had added themselves elsewhere in the playlist is moved into the folder by a build (same window problem). Re-add it too, and keep it as the user's? *Suggested: yes. Only item options set when it was added would be lost, which is rare for a local file.*
- **Test:**
  - Claude: rules-refresh, plus checks that every item whose place changed has a new id while the playing copy keeps its id.
  - The user: To do 3 step A manual test 8 again. The window shows Episode 2 2nd.
