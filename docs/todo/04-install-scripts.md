# To do 4: Install and uninstall scripts (medium)

"Copies files and enables the interface in vlcrc (back up vlcrc first), plus an uninstall script that reverses it"

- **Problem / Goal:** a one-command install and uninstall in Windows PowerShell 5.1.
- **Read first:** research/vlc-lua-api.md ("This PC's VLC": vlcrc is UTF-8 with BOM and LF line endings, with sections) and To do 1's chain-syntax answer.
- **Approach:**
  - `install.ps1`:
    - Stop with a message if vlc.exe is running.
    - Copy `lua\` into `%APPDATA%\vlc\lua\`.
    - Back up vlcrc with a timestamp.
    - Add `luaintf{intf=autofolder}` (or `luaintf` + `lua-intf=autofolder`) to `extraintf` in `[core]`, keeping existing entries.
    - Keep the BOM and LF line endings.
    - If vlcrc doesn't exist yet, ask the user to start and close VLC once.
  - `uninstall.ps1`: remove our files and only our vlcrc changes.
  - Both take a `-VlcDir` parameter, so tests can run them against a copy.
- **Ask the user:**
  - Uninstall: restore the backup, or remove only our changes? *Suggested: only our changes; you may have changed other settings since.*
  - `lua-intf` already used by another script? *Suggested: use the chain syntax (To do 1 measured that it works); otherwise stop with a message.*
- **Test:**
  - Claude: install and uninstall against a copied vlcrc in a temp folder; the diff shows only our lines; encoding is unchanged; PSScriptAnalyzer is clean.
  - The user: a real install, double-click a video, then uninstall.
