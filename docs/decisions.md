# Decisions

One entry per decision, newest first. Each entry has the date and the decision as its heading, then the reason, who decided, and what was rejected and why.

## 2026-11-19: README and guide say "Released" with no version number
- **Rule:** the status line in README.md ("## Status") and docs/guide.md ("## What works") says "Released; versions and what changed: CHANGELOG.md", with no version number or date. The version stays only in CHANGELOG.md and the dialog's `descriptor()`. This replaces the "In development" those lines held until the 0.1.0 release.
- **Reason:** a version number in the README goes stale at the next release unless someone remembers two more files; GitHub already shows the latest release beside the repo. The README rule also says no numbers that change often.
- **Who:** the user, taking Claude's suggestion.
- **Rejected:** "Version 0.1.0, released 2026-11-14" in both lines (the user's first wording), with README and guide added to the release steps.

## 2026-11-14: GitHub settings after going public: main is protected; secret scanning stays off
- **Rule:** a ruleset "Protect main" on the default branch blocks deleting it and force-pushing to it, with no bypass (not even the owner). Normal pushes need no pull request or review. To rewrite history on purpose (e.g. to remove a committed secret), turn the ruleset off in Settings → Rules → Rulesets, push, and turn it on again.
- **Reason:** the history is public now; a force-push would leave every clone out of step with GitHub.
- **Who:** the user, taking Claude's suggestion. Secret scanning and push protection were suggested and left off (the user moved on without turning them on).
- **Also:** the Projects tab is off (unused; the to-dos are in docs/todo.md).
- **Skipped for now:** a social preview image (GitHub's own card shows the name and description; `playlist.png` is 1122×696, not 2:1, so sites would crop it, and its text is unreadable at thumbnail size), issue templates, CONTRIBUTING and Code of Conduct (no reports yet; a bug-report template once the first vague report comes), private vulnerability reporting and Dependabot (no dependencies, no server), a CI workflow (a to-do if wanted).

## 2026-11-14: The repo is public, with version 0.1.0 as a tag and a GitHub Release
- **Rule:** the GitHub repo was switched to public on 2026-11-14, after the push of the changelog commit. Before that: the description "Open one video in VLC and the rest of its folder is added to the playlist automatically (VLC 3.0, Windows)", the topics vlc, vlc-lua, playlist, lua, windows, and an annotated tag `v0.1.0` with a GitHub Release "0.1.0" whose notes are the changelog's 0.1.0 section plus "To install, see Install in the README." Each later release does the same: tag `vX.Y.Z`, Release notes from its changelog section. The README's install steps stay on Code → Download ZIP.
- **How it was checked:** the privacy scan over every commit (decisions entry below) was run again on all 25 commits for the user folder name, the PC name, the login, the email's local part and "OneDrive": no hit in any file or commit message. After the switch, without signing in: the main zip downloaded (HTTP 200) and holds the folder `vlc-autofolder-main` (as the README's install step says) with `install.cmd` and `uninstall.cmd` in CRLF, and no docs/local.md; the release page answered 200.
- **Who:** the user ("make this public now"; Claude ran the steps), taking Claude's suggestions for the description, topics and release.
- **Rejected:** a tag without a Release (visitors look for versions on the Releases page); install steps that point to the Release's zip (its folder is `vlc-autofolder-0.1.0`, checked in the tag's zip, so the README's folder name would be wrong, and the main zip is always the newest).

## 2026-11-14: Semantic versioning from 0.1.0; CHANGELOG.md in Keep a Changelog format
- **Rule:** CHANGELOG.md in the repo root follows Keep a Changelog 1.1.0: Unreleased first, then versions newest first, each headed `## [X.Y.Z] - YYYY-MM-DD`. The first version is 0.1.0, dated 2026-11-14; if the repo goes public on another day, that date changes to it. The version number also stands in the settings dialog's `descriptor()` (`lua/extensions/autofolder_dialog.lua`, was `0.1`); a release changes both. Each change users can see gets one plain-language line under Unreleased (finish-step).
- **Reason:** 0.x fits the README's "In development" status and the dialog's earlier `0.1`. Dating it now means no extra step on release day if nothing changes before then.
- **Who:** the user (0.1.0, today's date), from Claude's suggestions; the Keep a Changelog format was already set in todo.md.
- **Rejected:** 1.0.0 (says stable while the README says in development). Keeping everything under Unreleased until release day (a step to remember later). The compare links Keep a Changelog puts at the bottom (`[0.1.0]: https://github.com/...`): the repo URL names the personal account (CLAUDE.md, "Never in tracked files"), so the version headings stay plain text.

## 2026-11-14: The pre-release manual run stops after section 2; the user reports problems from normal use
- **Rule:** for the public release, the manual checklist ran sections 0 to 2 (and 10.7, To do 8) by hand. Claude ran the automated tests and section 11 on the installed VLC from a script, plus a no-window start of the installed VLC; the rest was not run again (results: manual-test.md, "Runs"). After this, the user uses the tool as normal and reports what doesn't work.
- **Reason:** the user didn't want to run the checklist again. Since its full run on 2026-11-13 only install.ps1 changed (To do 8), and the automated install checks, 10.7 and section 11 cover that. The Lua code that sections 3 to 10 check is unchanged.
- **Who:** the user (stop the manual run); what replaces it was Claude's suggestion.
- **Rejected:** automating the checklist's GUI steps (Explorer double-clicks, drops, the Qt playlist window, the dialog, one-instance hand-over). That would be a large build for code that hasn't changed, and a screenshot GUI test was already turned down (CLAUDE.md, Decisions). The checklist stays for changes to those parts.

## 2026-11-14: Install and uninstall remove a bare `lua` from extraintf, unless a CLI host is set
- **Rule:** in the `extraintf` line install edits (the last one), a bare `lua` entry is removed and ours added; uninstall removes it from every `extraintf=` line along with ours. Kept when vlcrc has an uncommented `rc-host=` or `cli-host=` line with a value. A bare `luaintf` is always kept. Each removal prints its own line. This amends the 2026-11-12 rule "adds one extraintf entry; uninstall removes only that entry".
- **Reason:** saving Tools → Preferences → All → Interface → Main interfaces turns our entry into `lua` (measured 2026-11-14), which starts VLC's command-line interface (`cli.luac`), not autofolder: a Terminal window opens with VLC (seen by the user). Without a host, that CLI is of no use on Windows, so the `lua` is our entry as the page rewrote it; with a host, someone uses the CLI on purpose. Uninstall removes it too, or uninstalling after saving that page would leave the CLI on.
- **Who:** the user, accepting Claude's suggestions (To do 8 questions).
- **Rejected:**
  - Also replacing a bare `luaintf` (the to-do's first Approach): the page writes `lua`, not `luaintf` (measured), and `extraintf=luaintf` with `lua-intf=X` is how other Lua add-ons are set up, so replacing it could switch one off.
  - Uninstall keeping a bare `lua` (the to-do's first suggestion): it would leave the CLI on after uninstalling, for a `lua` that our entry caused.

## 2026-11-14: README pictures: made by a script with the portable VLC and a demo folder
- **Rule:** `docs/images/playlist.png` (the playlist after opening only "Lecture 4 - Loops.mkv") and `docs/images/settings.png` (the settings dialog) are made by `tests\make-screenshots.ps1` (run by hand) from the portable test VLC, never the installed one. The demo folder is 10 files "Lecture 1 - Introduction.mkv" … "Lecture 10 - Review.mkv" in `%TEMP%`, each a 2-minute solid-colour YUV4MPEG2 video, dated one day apart. How the window is set up and captured: research/vlc-lua-api.md, "Screenshots of the Qt window".
- **Reason:** no private file names on GitHub, the user's VLC settings stay untouched, and the pictures can be made again after a change.
- **Who:** the user asked Claude to script it.
- **Rejected:** screenshots by hand (the user preferred a script); the user's own videos (private names).

## 2026-11-14: The README is short; the details are in docs/guide.md
- **Rule:** README.md keeps what it does, a short Status list (one or two lines per feature, linking to the guide), Install (with a "Download ZIP → Extract All" step, Update and Uninstall), Settings in one paragraph, two troubleshooting lines plus a link, Development, Credits and License. docs/guide.md holds the rest, moved word for word: What works (the old Status list), Sort order and video types, When VLC is already open, Troubleshooting, Limitations and Install details. Only three things changed in the moved text: "see Install below" became a link to the README, "It copies" became "The install copies", and "in this folder" became "in the project folder".
- **Reason:** the README was 2,406 words, with Install at line 76 of 101 (measured); the README rule in the user's CLAUDE.md wants install near the top and details in docs/.
- **Who:** the user, taking Claude's suggestions (trim-readme skill).
- **Rejected:** a root GUIDE.md (docs/ already holds the other docs), a `<details>` block per feature (still one long page on GitHub, and harder to link), and only reordering sections (Install comes sooner, but the page stays long).

## 2026-11-14: Pre-release docs review: what was fixed and what was left
- **Rule:** a fresh subagent checked README.md and docs/manual-test.md against the code (13 findings). Fixed: the checklist's missing setup-tools step, the uninstall message order, the test-output quote and the `.dot-hidden.mkv` note in Explorer; in the README, "never change the playlist", how a wrong `extensions` value is handled and where a start-time warning shows, and the missing-`autofolder_settings.lua` entry. The `.m3u` claim now says "of several files". Left as they are: "within about two seconds" (worked out as ~1.2-2.4 s from the code, not measured), a dot-named file you open yourself staying in the playlist, and the install's "VLC is running" message not being quoted.
- **Reason:** the ones left are fair as written or edge cases, and the README should get shorter, not longer. A one-entry `.m3u` may build its file's folder (inferred, not tested); the new wording is true either way.
- **Who:** the user, taking Claude's suggestions.
- **Rejected:** changing install.ps1 to drop a bare `luaintf` before it's known that VLC's preferences write one (research/vlc-lua-api.md; manual-test step 10.7): a bare `luaintf` may be the user's own `lua-intf` setup.

## 2026-11-14: The repo goes public with its history; the commit author email stays
- **Rule:** no clean one-commit repo is needed: the privacy check (Before a public release) found no personal paths, PC name or GitHub login in any tracked file, any commit's files or any commit message. The commit author and committer (the repo's own git identity, name and email) stay as they are in all commits and will be public.
- **How it was checked:** `git grep` over every commit (`git rev-list --all`) for the user folder name, the login, the PC name, email addresses, drive and UNC paths (every hit read: all are test or example paths such as `C:\F\a.mkv`, `D:\Shows\`, `\\127.0.0.1\C$\...`), plus the commit messages and the files that were tracked once and are gone now (only to-do files, moved to docs/archive/). docs/local.md was never committed.
- **Who:** the user, taking Claude's suggestion.
- **Rejected:**
  - GitHub's noreply address for new commits: the address is the one chosen for this account, and the old commits would still show it.
  - A new repo with one clean commit to hide the email: loses the history for no real gain.

## 2026-11-14: MIT license, "Copyright (c) 2026 the vlc-autofolder authors"
- **Rule:** the repo is under the MIT license (LICENSE in the root, a License line in the README). The copyright line names "the vlc-autofolder authors", not a person. No license header in each source file.
- **Reason:** all code is the project's own (nothing copied or adapted from VLC), so any license works. MIT is the short, usual choice for a small tool and is GPL-compatible, so it doesn't clash with VLC (GPL-2.0-or-later) running the scripts. The group name keeps the GitHub login out of tracked files (CLAUDE.md "Never in tracked files"); git history still records the author.
- **Who:** the user, taking Claude's suggestions (Before a public release).
- **Rejected:**
  - GPL-2.0-or-later, to match VLC: copyleft protects little for a few small scripts, and the license text is much longer.
  - The user's real name or GitHub login in the copyright line: the login must stay out of tracked files, and the real name isn't needed.

## 2026-11-12: The manual checklist runs on the installed VLC; network paths through `\\127.0.0.1\C$` and a mapped drive
- **Rule:** docs/manual-test.md is run by the user on their own installed VLC 3.0.24 (Explorer double-clicks with VLC as the default app for `.mkv`, the real vlcrc, the install scripts without `-VlcDir`). Network paths are tested through the PC's own admin share and a drive letter mapped to it.
- **Reason:** the checklist covers what the headless tests can't reach (the Qt windows, Explorer, the one-instance settings, install on a real vlcrc), and those exist only in the installed VLC. The user has no network share.
- **Who:** the user, taking Claude's suggestions (To do 5).
- **Rejected:**
  - The portable test VLC: Explorer doesn't open files with it, it has no real vlcrc to install into, and with the same version it would hand files to the installed VLC.
  - A real network share: none available. The share on the same PC goes through the same UNC code path; a real share's speed is not measured.

## 2026-11-12: Double-click install.cmd and uninstall.cmd start the PowerShell scripts
- **Rule:** `install.cmd` runs `install.ps1` with Windows PowerShell's full path and `-ExecutionPolicy Bypass`, passes its arguments and exit code on, and `pause`s so the window shows the result; `uninstall.cmd` is `install.cmd -Uninstall`. When install.ps1 isn't next to it (double-clicked inside Explorer's zip view, which extracts only that file), it says to extract the zip first. All logic stays in the `.ps1` files. `.gitattributes` keeps `.cmd` files CRLF in checkouts and GitHub zips.
- **Reason:** typing a long PowerShell command in the right folder was the hard part of installing; a double-click is the usual way for small Windows tools.
- **Who:** the user asked for an easier install; Claude suggested the `.cmd` files and the user agreed (To do 4).
- **Rejected:**
  - An installer .exe (Inno Setup, NSIS): unsigned, SmartScreen warns even more, and a build tool for 4 files and one line.
  - A web one-liner (`irm .../install.ps1 | iex`): needs the public repo, and asks people to run a script straight from the web. Possible later, next to the zip.
  - Setting it up from inside VLC: a Lua script can't save vlcrc.
  - Install waiting for VLC to close instead of stopping: with the window open, double-clicking again is as easy, and a prompt could hang an unattended run.
- **Not checked:** whether Windows warns before running a `.cmd` from a downloaded zip (Mark of the Web); a "Before a public release" item.
  - **Checked 2026-11-14** (the user, Windows 11, GitHub's Code → Download ZIP, then Explorer's Extract All): it warns. Double-clicking `install.cmd` shows "Open File - Security Warning: The publisher could not be verified. Are you sure you want to run this software?" (Unknown Publisher); after Run the install worked (the installed scripts were the zip's copies). Extract All gives `vlc-autofolder-main\vlc-autofolder-main\`. Every extracted file carries `Zone.Identifier` ZoneId=3, and the installed scripts keep it (VLC doesn't mind). The `.cmd` files in the zip are CRLF (17 and 3 lines, no bare LF); `-ExecutionPolicy Bypass` runs the marked `.ps1` without a prompt. The README says to click Run and names the inner folder.

## 2026-11-12: install.ps1 adds one extraintf entry; uninstall removes only that entry, our files and autofolder.ini
- **Rule:**
  - install.ps1 copies `lua\` into VLC's user folder and adds `luaintf{intf=autofolder}` to `extraintf` in vlcrc (chain syntax), keeping other entries; `lua-intf` is never touched. Running it again updates the files and leaves vlcrc alone.
  - The entry goes into the last `extraintf=` line (VLC uses the last one), else replaces `#extraintf=`, else is added at the end of the file.
  - uninstall.ps1 (a wrapper for `install.ps1 -Uninstall`) removes our files, the folders they leave empty, `autofolder.ini`, and our entry; a line left empty becomes `#extraintf=` again, so a default vlcrc comes back byte for byte.
  - Amended 2026-11-14 (To do 8): both also remove a bare `lua`, see "Install and uninstall remove a bare `lua` from extraintf".
  - Both stop while any VLC runs, and install stops when vlcrc doesn't exist yet (the user starts and closes VLC once). vlcrc is backed up (`vlcrc.autofolder-YYYYMMDD-HHMMSS.bak`) before every change and edited as Latin-1 text, so every other byte stays as it was.
- **Reason:** other settings may have changed since the install, so restoring a backup could undo them. Chain syntax lets another Lua interface keep `lua-intf` (measured in To do 1). Latin-1 maps bytes to characters one to one, so the BOM, LF endings and UTF-8 or ANSI text survive without the script knowing the encoding.
- **Who:** the user, accepting Claude's suggestions (To do 4 questions).
- **Rejected:**
  - Uninstall restoring the install backup: it would also undo the user's later settings.
  - `extraintf=luaintf` with `lua-intf=autofolder`: it takes the one global `lua-intf` from any other Lua interface.
  - Writing a minimal vlcrc when there is none: one more code path, only for someone who installs before ever starting VLC.
  - Keeping `autofolder.ini` on uninstall: updating is running install again, so uninstall means "remove it all".

## 2026-11-11: Build and re-sort re-add only the items that must move; the folder goes where the playing item is
- **Rule:**
  - Build and re-sort share one function (`place` in autofolder.lua). It works out the target order first. Then it keeps the most items it can where they are, deletes the others and adds them again together with the folder's new files (one enqueue, in sort order), and then does the front moves.
  - Items that keep their id also keep their order relative to each other; only those may stay (`autofolder_core.keep_in_order`: the longest increasing run between the fixed items).
  - Never re-added: the playing item (it would restart) and items that aren't the folder's (the user's own; they can be streams or discs, whose title and options would be lost). A folder file the user added themselves is re-added when it must move, and stays theirs (not removed on a folder switch).
  - The folder goes where the playing item is, if it's one of the folder's; otherwise where the folder's first item is. In a build that is the opened file, which is always the playlist's last item, so the folder ends up after all the user's own items.
- **Reason:** VLC 3.0's playlist window inserts an added item at its index in the playlist when it handles the event, removes items by id, and never reacts to a script's move (research/vlc-lua-api.md, "Playlist", `move`). So the window is right when the items that keep their id keep their order, and the new items are added in their final order. Re-adding only what must move keeps the reading of file details small (14 items for Episode 2 of 16 re-opened, 1 for Episode 15). With the folder at the opened file's place, the user's own items never have to cross the playing item, so they are never re-added.
- **Changes:** the entries "The folder takes the place of its first item" (now: the playing item's place; the same unless the user's items sit between the folder and the re-opened file) and "A re-sort deletes and re-adds the folder's items" (now only the items that must move, and a user's own folder item too).
- **Who:** the user, accepting Claude's suggestions (To do 6 questions).
- **Rejected:**
  - Re-adding the whole folder on every build: VLC re-reads every file's details (~12 files/s on a share), for no gain in the window.
  - Keeping the folder at its first item's place: when a user's item sits between the folder and the re-opened file, that item would have to be re-added (title and options lost for a stream) or moved (the window then shows the re-added items in wrong rows too).

## 2026-11-11: The settings dialog: "Auto Folder Playlist settings", Save closes, the file is rewritten
- **Rule:**
  - The View-menu entry is "Auto Folder Playlist settings"; the dialog's title is "Auto Folder Playlist".
  - The dialog has a sort dropdown, a video-types field, Save and Cancel. Save writes the file and closes the dialog; Cancel, X and Escape close it without writing.
  - A word in the types field that isn't a file type: nothing is saved, a red note names it, and the dialog stays open. An empty field saves the default list.
  - Save rewrites the whole file in the standard layout (`settings.format`), so comments typed by hand are lost.
  - A wrong value in the file, or a file that can't be read: a note in the dialog, with the default shown in that field.
  - The dropdown is read with `get_text()`, not `get_value()` (VLC 3.0 bug: research/vlc-lua-api.md, "Extensions and dialogs").
- **Reason:** the plain name "Auto Folder Playlist" reads like a command that builds a playlist (as the "Add similar files from folder" add-on does), but the entry only opens the settings. Save-and-close is the usual settings dialog. Refusing a wrong type keeps the user's typing so it can be fixed.
- **Who:** the user, accepting Claude's suggestions (To do 3 step B questions).
- **Rejected:**
  - Keeping the user's other lines and comments when saving: ~25 more lines and tests for a rare case.
  - An Apply button that keeps the dialog open: more buttons for trying orders, which takes two clicks through the View menu anyway.
  - Saving only the valid types and dropping the wrong ones silently.

## 2026-11-11: A re-sort deletes and re-adds the folder's items instead of moving them
- **Rule:** when the sort order changes, the active folder's items that the script added are deleted and enqueued again in the new order, then placed with front moves as in a build.
  - The playing item stays, since re-adding it would restart it.
  - The user's own items stay and are moved.
  - Items the user deleted meanwhile stay out.
- **Reason:** in the step A manual test the playlist was re-sorted (log, and playback went on in the new order), but VLC 3.0's playlist window kept the old order. The window shows items added and removed, but not an item moved by a script (research/vlc-lua-api.md, "Playlist", `move`).
- **Cost:**
  - VLC reads each re-added file's details again. That took ~4 s for 500 local files and ~12 files/s on a share (measured in To do 2 step D). Playback isn't affected.
  - A user's own folder item can show in its old place in the window.
  - The window places an added item when it handles the event, which could come before the script's move. Not seen: the window was right after 5 sort changes by hand (step A tests 3–6).
- **Who:** the user, accepting Claude's suggestion (after To do 3 step A manual test 3).
- **Rejected:**
  - Keeping the moves and telling the user to refresh the window (typing in its search box and clearing it should do it, per the source; untested): the window shows a wrong order until then.
  - Applying a new order only at the next file opened: re-opening a file of the same folder also moves items, so the window problem stays.
- **Open:** the To do 2 build moves the re-opened copy of a file into the old copy's place, and the window shows it at the bottom (measured, step A test 8). Fix: To do 6.
- **Changed by To do 6 (2026-11-11):** only the items that must move are re-added, a user's own folder item too (see the entry "Build and re-sort re-add only the items that must move").

## 2026-11-11: Sort-order switch: a settings file read while VLC runs, plus a View-menu dialog
- **Rule:**
  - The settings are in `autofolder.ini` in VLC's user folder (`vlc.config.userdatadir()`, `%APPDATA%\vlc`): `sort=` one of `date-oldest` (default), `date-newest`, `name-az`, `name-za`, and `extensions=` the video types. A wrong value is logged as a warning and that line's default is used. The interface script never creates the file.
  - The interface script reads the file at start and about every second, comparing its contents. A changed text is applied when the next read gives it again (so a file read while being saved is never used); the first read is applied at once. A sort change re-sorts the active folder's items at once (reorder only, by re-adding them: see "A re-sort deletes and re-adds" above; the playing file keeps playing). A change of the video types applies at the next file opened.
  - Newest first breaks equal dates by name A→Z; name orders are natural order.
  - A companion extension (View → Auto Folder Playlist settings, To do 3 step B; see "The settings dialog" above) writes the same file. The settings code is shared in `lua\modules\autofolder_settings.lua`.
- **Reason:** a switch inside VLC without a restart, and a file that also works without the dialog (Skins interface, or editing by hand). The contents are compared rather than the file time, because `stat` times count whole seconds, so two saves within one second could be missed. The second read was added after the step A code review: the dialog and Notepad both empty the file before writing it, and a read in between would re-sort twice and warn about a cut-off value.
- **Who:** the user, accepting Claude's suggestions (To do 3 questions).
- **Rejected:**
  - The "Lua interface configuration" preference (`lua-config`): Lua syntax in a preference field shared with VLC's other Lua interfaces, a restart for each change, and a typo silently breaks it.
  - Applying a change of the video types to the current playlist: removing items of a dropped type needs more rules for a rare change.
  - Newest first as the exact reverse of oldest first (equal dates Z→A): files copied together would play last episode first.

## 2026-11-11: A build runs whole and at once; a folder that can't be read is not retried
- **Rule:**
  - The build runs in one poll, as soon as the opened file is seen, also for hundreds of files and on network shares.
  - A folder that can't be read is logged as a warning that says to open the file again; no retry.
  - The playlist is read once per poll and ~5 times per build, as before.
  - The build line in the log gives its time and the scan's share of it.
- **Reason (measured, research/vlc-lua-api.md "Large folders"):**
  - 500 local files build in 37–54 ms (499 moves: 1–2 ms), and other playlist calls never waited more than 3 ms.
  - The opened file's first picture came no later than without autofolder.
  - A playlist read with 500 items costs ~1 ms.
  - If the share is offline, the opened file can't play either, and opening the file again rebuilds anyway, since it is "just opened".
- **Who:** the user, accepting Claude's suggestions (To do 2 step D questions).
- **Rejected:**
  - Spreading the build over several polls: nothing waits on it, and the folder would come later.
  - Building only once the opened file plays: no measured gain, and a later folder.
  - A retry loop (e.g. every second for 10 s while the file plays): more state for a rare case.
  - Turning preparsing off for the added files (how, from Lua, wasn't looked into): VLC preparses a folder it opens itself the same way. Over a share it's slow (~12 files/s through a local test share), but playback wasn't affected. Without it, the playlist would probably show no durations until each file plays (not checked).
  - Passing one playlist read along through the build: it saves ~4 ms of a 45 ms build.
  - Skipping the playlist read on polls where nothing started: it saves ~1 ms per 300 ms, and the read tells when the last item changed.

## 2026-11-11: "Just opened" in detail: the last item, started within 10 s; one copy per file
Refines the two 2026-11-11 entries below ("A folder is built only for a file that was just opened" and "Folder switch, duplicates and deleted files").
- **Rule:**
  - "Plays straight away": the item starts at most 10 s (`autofolder_core.JUST_OPENED_S`) after it became the playlist's last item. The first item to play after VLC starts always counts.
  - "The newest item": the **last item by position**, not the highest id.
  - "Added after the previous file started": its id is above the highest id in the playlist when the previous item started.
  - Copies of a folder file: the playing copy stays; when none plays, the first one in the playlist. All other copies are removed, the user's own ones too. If any copy was the user's own item, the copy that stays counts as the user's, so a folder switch doesn't remove it.
  - Items whose file is gone are removed only when their folder is built, and only after `stat` confirms it.
- **Reason:** Lua can't see whether VLC was told to play an item or the user clicked it later; it only sees when an item appears and when it starts. A double-click starts its file within about a second. A slow start needs the margin: a cold VLC start loading Qt, or an old file slow to stop (6 s once in a headless test). VLC numbers the files of its command line in reverse (measured), so with "highest id" the first of several files would build.
- **Who:** the user, accepting Claude's suggestions (To do 2 step C questions); the copy-ownership part came from the step C code review.
- **Rejected:**
  - A shorter window: it could miss a real double-click.
  - No time rule ("added after the previous file started" and "last" only): an item enqueued while another plays would build when playback reaches it.
  - Removing only the copies the script added: it leaves duplicates (spec requirement 7).
- **Known gap:** an item enqueued less than 10 s before playback reaches it (by itself, Next or a click) builds its folder.

## 2026-11-11: The folder takes the place of its first item; the user's own items keep theirs
- **Rule:** after a build, the playlist is: the user's items that were before the folder's first item (normally the opened file), then the folder in sort order, then all other items in their order. The fewest moves to the front reach that order; that can move the user's items too.
- **Reason:** the user's items stay where they put them, and the folder goes where the opened file landed (at the end, since a double-click appends), as when VLC opens a folder itself (it expands the folder in place). With the folder first, VLC would play on into unrelated items after the last episode, and the user's list would be reordered.
- **Who:** the user, accepting Claude's suggestion (To do 2 step B questions).
- **Rejected:** the folder at the front of the playlist with the user's items after it (the step B plan written in step A): see Reason. It also needs a move for every folder item as soon as any user item is in the playlist.
- **Changed by To do 6 (2026-11-11):** the folder now takes the place of the playing item (in a build, the opened file: the end of the playlist), not of its first item. It differs only when the user's items sit between the folder and the re-opened file (see the entry "Build and re-sort re-add only the items that must move").

## 2026-11-11: A folder is built only for a file that was just opened
- **Rule:** the playing item triggers a build only when it was added after the previous file started playing, plays straight away, and is the newest item in the playlist. Playing an item that was already there (a click, Next/Previous, an .m3u's entries, several files opened at once) never builds.
- **Reason:** the double-click, Open File and drag-onto-window cases all add one item and play it at once; a hand-made playlist must stay as the user made it.
- **Who:** the user, accepting Claude's suggestion (To do 2 questions).
- **Rejected:**
  - "The playing item is the newest one" alone (the to-do's first suggestion): stepping with Next to the last item of a hand-made playlist would build that item's folder and rearrange the list.
  - "Added since the previous poll": racy, since VLC can add an item and start it hundreds of ms (up to ~6 s, measured in To do 1) apart.

## 2026-11-11: Folder switch, duplicates and deleted files
- **Rule:**
  - A file from another folder: remove the old folder's items the script added plus the file opened there; keep the user's own items; build the new folder.
  - A folder file already in the playlist is never added twice: one copy stays in its place (the playing one, if it's a re-opened duplicate), and files that appeared in the folder since are added.
  - Items whose file was deleted from the folder are removed when the folder is built again.
- **Reason:** VLC appends on every double-click and never clears, so without removal the playlist grows without end; spec requirement 7 asks for no duplicates. A deleted file would make VLC show a "can't open" error.
- **Who:** the user, accepting Claude's suggestions (To do 2 questions).
- **Rejected:** keeping old folders (the playlist grows; Next runs into the old folder); clearing the whole playlist (it would remove the user's own items).

## 2026-11-11: The folder logic places files only by moving them to the front of the playlist node
- **Reason:** VLC 3.0's Lua `playlist.move(id, target)` with an item as target computes the new place from item ids, not positions: wrong places, and a crash when the index falls out of range (measured; research/vlc-lua-api.md, "Playlist"). Moving into the playlist node (the item becomes first) works and keeps playback and Next/Previous right (measured).
- **How:** enqueue the files after the playing one in order (appended); enqueue the files before it, then move each to the front, last one first.
  - **Since To do 2 step B:** all missing files are enqueued in one call in sort order, then `autofolder_core.front_moves` gives the fewest moves to the front that reach the wanted order (the entry above). This also keeps the user's items before the folder, which the first "How" would have split from it.
- **Who:** Claude, forced by the To do 1 step B measurement; the user accepted it with the To do 2 plan (2026-11-11).
- **Rejected:**
  - `move` after an item: wrong place or a crash.
  - `vlc.playlist.sort`: it reorders the user's whole playlist and has no natural or date-modified order.
  - Deleting and re-adding the playing file in the right place: playback would restart.

## 2026-11-11: Test VLCs also pass `--no-crashdump` and `--no-sub-autodetect-file`
- **Reason:**
  - A crashing test VLC wrote a crash dump into the real `%APPDATA%\vlc\crashdump`, despite the portable folder, and the next VLC start would ask to send it (measured). `--no-crashdump` (read by vlc.exe itself) stops that.
  - With `Episode 1.srt` auto-loaded and no video output, the headless VLC took ~6 s to stop Episode 1.mkv, which made switch tests flaky (measured).
- **Who:** Claude, while fixing the failures in To do 1 step B; reported to the user at hand-over.
- **Rejected:**
  - Deleting new crash dumps after each run: the tests would then write into the real folder on purpose.
  - Renaming or removing `Episode 1.srt`: it's there to test that non-videos are ignored.

## 2026-11-10: The test VLC is the portable 3.0.24 zip in `tools\vlc`, with a `portable\` folder
- **Reason:**
  - With a `portable` folder next to vlc.exe, VLC 3.0 keeps its settings and Lua user folder there (measured: `vlc.config.userdatadir()` returns it, and `%APPDATA%\vlc` stays unchanged).
  - The zip is pinned by SHA-256, so anyone can recreate the same test VLC with `tests\setup-tools.ps1`.
  - Test runs pass `--no-one-instance --no-one-instance-when-started-from-file`, so they never hand files to the user's own VLC, and `--no-media-library`, so they don't write `ml.xspf`.
- **Who:** the user, accepting Claude's suggestion (To do 1).
- **Rejected:**
  - Copying the installed VLC folder: no download, but it ties the tests to whatever version is installed, and nobody else can reproduce it.
  - The installed VLC with `--config=<temp vlcrc>`: it would still read Lua scripts from the real `%APPDATA%\vlc\lua`.
  - Setting `$env:APPDATA`: VLC finds the folder through the Windows shell API, not the variable (from memory of the source; not tested, since the portable folder made it unnecessary).
- **Test videos:** a raw YUV4MPEG2 video written by PowerShell (2 min, 32x32, 1 frame/s, 185 KB), saved under every video extension. VLC plays it whatever the extension (measured as .mkv and .mp4), so no ffmpeg is needed. Rejected: recording `screen://` with VLC, which would capture the user's screen.

## 2026-11-10: Public on GitHub later
- **Done:** public since 2026-11-14 (entry above, "The repo is public").
- **Reason:** a small VLC add-on is useful to others.
- **Who:** the user, accepting Claude's suggestion.
- **Consequence:** personal paths and the GitHub login used for pushes never go in tracked files.
- **Rejected:** staying private-only, because there was no reason to.

## 2026-11-10: Tests run the real VLC 3.0.24 with no window, isolated from the real settings; no screenshot GUI test
- **Reason:**
  - The script runs inside VLC's own Lua 5.1, so only VLC itself is a faithful test runtime.
  - The behaviour is playlist state, which a test script can check exactly.
  - The few Qt parts (sort dialog, one-instance mode) are covered by the manual checklist.
- **Who:** the user, accepting Claude's suggestion.
- **Rejected:**
  - A standalone Lua interpreter with mock `vlc.*` functions: the mocks could disagree with the real 3.0 API.
  - Screenshots of the Qt window: they add little over checking the playlist directly.
- **How it's isolated:** settled in To do 1: see "The test VLC is the portable 3.0.24 zip" above.

## 2026-11-10: The core is a Lua interface script loaded at startup through the extra-interface setting
- **Reason:** it must start with VLC with no menu click.
- **Who:** the user (brief, requirement 1).
- **Rejected:**
  - A Lua extension: extensions can't auto-start in VLC 3.0.
  - A Lua playlist (demux) script: it runs when VLC probes the file and would turn the opened file into a playlist node, so the opened file wouldn't keep playing.
