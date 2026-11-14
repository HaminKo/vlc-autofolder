# Why VLC is sometimes slow to open a video

Question (2026-11-12, asked during the To do 5 manual test): why does VLC take so long to open a video? Short answer: the first start after VLC's DLLs were last checked is slow because Microsoft Defender scans each DLL as VLC loads it. A warm start takes ~0.4 s. autofolder makes no measurable difference, cold or warm.

This replaces the guesses in vlc-lua-api.md ("cause not checked; probably Windows scanning the plugin DLLs again", under auto-preparse, Test isolation and To do 1 step B).

## Method (2026-11-12)
- The windowed portable test VLC (`tools\vlc`, Qt interface, normal video and audio output), with `--no-one-instance --no-one-instance-when-started-from-file --no-crashdump --no-media-library --no-qt-privacy-ask --no-qt-updates-notif --metadata-network-access` (the last one as in the dev PC's vlcrc).
- A throwaway Lua interface logged `vlc.misc.mdate()` at each stage every 10 ms: script start, input created, state playing, video output (`vlc.object.vout()`), playback time > 0 and >= 1 s. A PowerShell script started VLC, read `timeGetTime()` at the start (the same clock as `mdate` on Windows: VLC 3.0's default clock source is "multimedia", ms steps) and polled the process for its main window. All times below are ms after `Start-Process`.
- Files: the test media's `Episode 1.mkv` (YUV4MPEG2, 1 frame/s) and a real 2.5 MB recording from the Videos folder (25 videos in that folder, so autofolder builds 24).
- With autofolder: `--extraintf luaintf{intf=autofolder}:luaintf{intf=<timing script>}`; without: only the timing script.

## Measured
- **Warm, 15 runs (3 rounds of 4 cases, plus one round):** main window 0.14–0.31 s, playing 0.20–1.12 s, video output 0.40–1.09 s, for both files, with and without autofolder. No difference from autofolder beyond run-to-run spread.
- **Cold, a fresh copy of `tools\vlc` (just copied, so the files were in the RAM cache):** first start: Lua interfaces 1.7 s, window 4.9 s, video output **10.2–10.7 s**; the starts right after: video output 0.37–0.46 s. Two copies: one started first without autofolder (10.7 s), one with it (10.2 s).
- **The cost is the on-access scan:** a third fresh copy, with every DLL and EXE read once first (`Get-FileHash` of 365 files, 190 MB from the RAM cache, took **55.5 s**), then started: video output 1.0 s, then 0.38 s.
- Windows Defender is the only antivirus (Security Center), real-time protection on; Smart App Control off (`VerifiedAndReputablePolicyState` = 0).
- The first run of the warm batch was also slow (window 2.0 s, video output 2.7 s), after the test VLC had been idle for a few minutes.

## Estimated, not measured
- The installed VLC's DLLs aren't new, so their slow first start needs Defender to check them again. Defender most likely rescans after its security intelligence updates (one was installed at 18:11 on 2026-11-12, before the slow manual-test start at 19:45) and after a reboot. This fits the earlier slow "first run of the day" (7.9 s and 3.5 s, To do 1; no first picture within 15 s, To do 2 step D), but Defender's cache rules were not checked.
- The installed VLC was not timed (that needs the real `%APPDATA%\vlc`); it runs the same 3.0.24 files, so the numbers should carry over.
  - **Confirmed by the user (2026-11-12):** later opens in the installed VLC were fast again, so only the first start was slow. That fits the cold-start explanation; the trigger (the Defender update) is still a guess.

## What can be done
- Nothing in autofolder: it isn't the cause.
- A Defender folder exclusion for `C:\Program Files\VideoLAN\VLC` (`Add-MpPreference -ExclusionPath`, admin) would remove the cold cost, at the price of Defender never scanning those files. Not recommended for a once-in-a-while delay; not tried.
