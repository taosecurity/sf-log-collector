# Changelog

## 2.0.0 (unreleased)

First public release. Versions 1.0.0 to 1.1.1 were private builds.

- The zip now goes to `Documents\StarfieldLogs` by default (`-OutDir` moves it).
- Finds Game Pass installs (`<drive>:\XboxGames\Starfield\Content`, and the folder in each drive's `.GamingRoot`)
  as well as every Steam library. `-GamePath` also takes the `Data` folder.
- Mod Organizer 2: `-MO2Path` and `-MO2Profile` add the profile's `plugins.txt`, `loadorder.txt`, `modlist.txt`
  and INIs, MO2's `overwrite\SFSE` reports and settings, and MO2's logs.
- Screenshots default to Steam's Starfield screenshots and photo mode's folder; `-ScreenshotDir` takes several
  folders (`"dir1;dir2"`).
- New `-DownloadsDir`, `-MyGamesDir` and `-PluginsTxtDir` for non-standard folders.
- Troubleshooting log: `collector-log.txt` in every zip, `-LogFile <file>`, and `-Verbose`.
- The manifest, log and `events.txt` show `%USERPROFILE%` in place of the Windows user folder and no longer record
  the computer or user name.
- Errors stop with exit code 2 and a message naming the problem; the launcher passes the exit code on.
- A Game Pass save container (not `.sfs` files) gets a warning saying how to export the saves.
- SHA-256 is computed with .NET, so Windows PowerShell 5.1 started from PowerShell 7 no longer fails to copy.

## 1.1.1 (private)

- Don't stop when another Windows user can't read the default game folder.

## 1.1.0 (private)

- Before/after save pair (`-SavePair`).

## 1.0.1 (private)

- Always include `Papyrus.1.log`.

## 1.0.0 (private)

- First version.
