# To do 5: README and manual test checklist (small)

"Install, how to switch sort order, troubleshoot, known limitations; a manual test checklist"

- **Problem / Goal:** spec.md deliverables 4 and 5, plus requirement 9: document what happens with one-instance mode on/off and enqueue mode on/off.
- **Read first:** spec.md; the README as the earlier to-dos left it; research/vlc-lua-api.md (one-instance).
- **Approach:**
  - README: install, sort switch, troubleshooting (Tools → Messages, verbosity 2, filter `autofolder`), known limitations, and a one-instance behaviour table filled from real tests (the headless results are in research/vlc-lua-api.md, "One-instance mode").
    - Troubleshooting must say: a double-click only reaches VLC when VLC is the default app for the video type (on the dev PC, Windows Media Player was). A VLC opened from the Start menu doesn't receive double-clicks; each starts its own VLC (measured).
  - `docs/manual-test.md`:
    - middle, first and last file
    - Unicode names
    - switching folders
    - clicking items within the playlist
    - one-instance on/off and enqueue on/off
    - opening an .m3u
    - a network share
    - a large folder
    - install, install again (update) and uninstall on the real VLC (README "Install"): vlcrc differs from the first `.bak` only in the extraintf line, and after uninstall it is byte-identical to it (tested by hand in To do 4)
- **Ask the user:** none yet.
- **Test:**
  - Claude: every README step is checked against the code.
  - The user: runs the checklist once.
