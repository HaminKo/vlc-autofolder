# Changelog

All notable changes to vlc-autofolder are listed here, newest first.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-14
The first version, for VLC 3.0 on Windows (built and tested with VLC 3.0.24 on Windows 11).

### Added
- Opening one video (by double-click, Open File, or a drop on the video picture) adds the other videos of its folder to the playlist, before and after it, so Next and Previous work. The folder goes at the end of the playlist; your own items stay.
- Sort order by date modified or by name (natural order: Episode 2 before Episode 10), either way round. The default is date modified, oldest first.
- A settings dialog, View → Auto Folder Playlist settings, for the sort order and the video file types. Save applies them without restarting VLC.
- Opening a video from another folder replaces the previous folder's videos. Opening one from the same folder again keeps one copy of each file, adds new files and removes deleted ones.
- Large folders, network paths and mapped network drives.
- Install and uninstall with a double-click (`install.cmd`, `uninstall.cmd`). Both save a copy of VLC's settings file before changing it, and repair the entry that VLC's preferences page can overwrite.
