# To do 8: Install repairs the entry VLC's preferences page rewrites to `lua` (small)

The user agreed to this fix as a "Bugs me" to-do, before the public release (2026-11-14, after manual-test step 10.7).

- **Problem / Goal:** saving VLC's Tools → Preferences → All → Interface → Main interfaces page turns autofolder's entry into a bare `lua`, which starts the Lua command-line interface instead of autofolder. Running the install again today keeps that interface. Goal: running the install again (the guide's advice) gives a clean `extraintf=luaintf{intf=autofolder}` again.
  - Measured 2026-11-14 (research/vlc-lua-api.md, "How VLC reads vlcrc", the struck-through "Not checked" point and what replaced it):
    - Installed VLC 3.0.24: with `extraintf=luaintf{intf=autofolder}`, the page shows "Lua interpreter" ticked and the text `lua` when it opens; after ticking and unticking Web and Save, vlcrc holds `extraintf=lua`.
    - Portable VLC: `--extraintf lua` loads `cli.luac` (the Lua CLI has the highest priority in the Lua module). Headless, VLC then didn't exit within 20 s after `vlc.misc.quit()`; without it, 3.2 s.
  - Measured on the user's VLC (step 6 of 10.7): install.cmd run again printed `vlcrc: added luaintf{intf=autofolder} to extraintf` and left `extraintf=lua:luaintf{intf=autofolder}`, so autofolder runs and the CLI stays. Uninstall would then leave `extraintf=lua` (from the code).
  - The user's VLC closed normally (no `vlc` process left); not noted whether it had been started with `extraintf=lua`, or whether a console window showed. The user's vlcrc was restored from `vlcrc.before-10-7` (line `extraintf=luaintf{intf=autofolder}` again, checked).
- **Read first:**
  - `install.ps1`: `$entry`, `Get-ExtraintfEntry`, `Get-EditedVlcrc` (add: last `extraintf=` line, or `#extraintf=`, or the end), `Save-Vlcrc`, and the install and uninstall messages.
  - `tests\InstallChecks.ps1`: `Get-InstallCheckLine`, its `$variants` table (Before / Installed / Uninstalled per vlcrc), easy to extend.
  - docs/guide.md Troubleshooting: "It stopped working after a change in VLC's preferences"; docs/manual-test.md step 10.7.
  - decisions.md: "install.ps1 adds one extraintf entry; uninstall removes only that entry, our files and autofolder.ini" (this changes that rule a little).
- **Approach:** in `Get-EditedVlcrc` (install only), a bare `lua` or `luaintf` entry in the line it edits is replaced by ours instead of kept, when vlcrc has no uncommented `rc-host=` or `cli-host=` line (with a host, someone uses the CLI on purpose). Install prints one line when it does, e.g. `vlcrc: replaced "lua" (left by VLC's preferences page) with luaintf{intf=autofolder}`. Uninstall stays as it is. New `$variants`: `extraintf=lua` and `extraintf=luaintf` (installed: ours; uninstalled: `#extraintf=`), `extraintf=http:lua` (installed: `http:luaintf{intf=autofolder}`), and `extraintf=lua` with an `rc-host=` line (kept: `lua:luaintf{intf=autofolder}`). Then the guide entry (what the page does, run the install again) and step 10.7's "See:".
- **Ask the user:**
  - Replace a bare `lua` only without a CLI host setting, as above? *Suggested: yes. Without a host, on Windows the CLI is a console nobody can type into; with one, it's deliberate.*
  - Also have uninstall remove a bare `lua` it finds? *Suggested: no. Uninstall removes only what install added; after this fix install never leaves one.*
  - Check by hand whether VLC started with `extraintf=lua` shows a console window or is slow to close? *Suggested: once, while testing step 10.7 by hand; it decides how strongly the guide words it.*
- **Test:** InstallChecks via run-tests.ps1 (`-Case install-script`); by hand: step 10.7 on the installed VLC with the new "See:" (after Save the line is `extraintf=lua`; after install.cmd it is `extraintf=luaintf{intf=autofolder}` and install says it replaced `lua`), then restore or keep the vlcrc.
