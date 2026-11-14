# To do 7: Playlist window sometimes shows a new folder in the wrong order (medium)

The user agreed to a Someday to-do for this (2026-11-14), found while making the README pictures.

- **Problem / Goal:** with VLC's playlist window open while a folder is built, the window sometimes shows the items before the opened file in the wrong order. Playback order is right; only the window is wrong. Goal: the window shows the real order, or the README says when it may not.
  - Seen (2026-11-14, portable test VLC, tests\make-screenshots.ps1 setup: docked playlist visible from the start, `--no-video`, 10-file demo folder, "Lecture 4 - Loops.mkv" opened; build `3 before and 6 after`, `3 moves`): in 1 of 7 captures the window showed 4, 2, 3, 1, 5 … 10 instead of 1 … 10. The other 6 were right.
  - Real order: 1 … 10 in the 4 runs where a second Lua interface logged it 4 s after start. The wrong run had no such log, so its real order is inferred, not measured.
  - Already known from the source (research/vlc-lua-api.md, "Playlist", `move`): the window places an added item at its index **when it handles the event**, and never shows a later move of an item it already shows. So an item enqueued and then moved before the opened file shows in the right place only if the window handles the add after the move. The build has to move the "before" items: enqueue only appends, and the opened (playing) item can't be added again without restarting it.
  - Not known: how often it happens on the installed VLC; whether it happens with the playlist hidden (the window's model may exist then too); whether hiding and showing the playlist, or typing in its search box (`filter` rebuilds the model), fixes the view.
- **Read first:**
  - research/vlc-lua-api.md, "Playlist": the `move` points, including "The race does show (measured 2026-11-14)".
  - `autofolder.lua`: `place` (enqueue, then `arrange`'s front moves), `arrange`; `autofolder_core.lua`: `target_order`, `keep_in_order`, `front_moves`.
  - docs/archive/06-reopen-at-bottom.md: the same window limit for a re-opened file, solved by deleting and re-adding.
  - tests\make-screenshots.ps1: a ready way to start the windowed portable VLC with the docked playlist and capture the window.
- **Approach (suggested, research first):**
  1. Measure: a script like make-screenshots.ps1 that runs the build ~20 times with the playlist visible and logs the real order (a scratch Lua interface) next to each capture; count the wrong views. Then by hand on the installed VLC: open a file with the docked playlist visible, a few times.
  2. Check the cheap fixes by hand when the view is wrong: hide and show the playlist (Ctrl+L twice), type and clear a letter in its search box.
  3. Then decide: a Limitations line in docs/guide.md (with the fix from step 2, if one works), or a code change. Code ideas, none tested: wait in the build until the window has handled the adds before moving (no API tells when); re-add the opened file at the build (it would restart; the build runs within ~0.3 s of the start).
- **Ask the user:**
  - If it's rare (under 1 in 10) and Ctrl+L twice fixes the view: only a Limitations line? *Suggested: yes; a code change that restarts the opened file is worse than a rare wrong view.*
  - Measure on the installed VLC too, by hand? *Suggested: yes, 5 tries with the docked playlist open; the portable VLC may differ in timing.*
- **Test:** the measuring script's counts (before and after any change); by hand, the steps of the chosen fix on the installed VLC, added to docs/manual-test.md.
