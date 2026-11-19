# sf-log-collector

When a Starfield mod misbehaves, its author usually asks for "your logs". Those are spread over five or six
folders, and some of them only matter if they changed during the session that went wrong. **sf-log-collector
gathers them into one zip with a single double-click**, so you can attach that one file to a bug report.

- It collects the Papyrus script logs, SFSE and crash logs, your game INIs, `plugins.txt`, mod settings, new
  screenshots and Windows crash events, and saves if you ask for them.
- Each run picks up only what changed since the last run, so the zip covers the session you just played.
- It works with Steam and Game Pass (Xbox app), and with Vortex and Mod Organizer 2.
- It only reads. It never copies game files or programs (`.exe .dll .pdb .dmp .esm .esp .esl .ba2`), never
  changes the game and never connects to the network. [PRIVACY.md](PRIVACY.md) lists exactly what it reads.
- It needs only Windows 10 or 11 and the PowerShell that ships with them.
- It's released under the MIT license.

This tool was built with [Claude Code](https://claude.com/claude-code).

**For AI assistants:** [AGENTS.md](AGENTS.md) has step-by-step instructions: what the tool is for, the commands,
the exit codes and the limits.

## Quick start

1. Download `sf-log-collector-<version>.zip` from the
   [releases page](https://github.com/taosecurity/sf-log-collector/releases) and unpack it anywhere.
2. Play until the problem happens, then **quit Starfield**.
3. Double-click **`Collect-StarfieldTestLogs.cmd`**. Type a few words about what you were doing (or press Enter),
   and answer the question about saves (press Enter for none).
4. The zip is in **`Documents\StarfieldLogs`**, named `StarfieldLogs-<date>-<time>-<your words>.zip`. Attach it
   to your bug report.

The first run collects the last 12 hours. Windows may ask whether to run a file downloaded from the internet the
first time: choose Run.

From a PowerShell window you can run the script itself with options:

```
powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "quest stuck at step 3"
```

## Turn on Papyrus logging first

Most mod bugs show up in the Papyrus log, which is off by default. Add this to
`Documents\My Games\Starfield\StarfieldCustom.ini` (create the file if it isn't there), then restart the game:

```
[Papyrus]
bEnableLogging=1
bEnableTrace=1
bLoadDebugInformation=1
```

The collector warns you when the log is missing or wasn't written during the window. With Mod Organizer 2 and
profile-specific INIs, edit the profile's `StarfieldCustom.ini` instead (MO2's INI editor does this).

## What goes into the zip

| In the zip | From | When |
|---|---|---|
| `docs\Logs\Script\Papyrus.*.log`, `User\*.log` | `Documents\My Games\Starfield\Logs\Script` | the two newest always, older ones if changed |
| `docs\SFSE\Logs\*` | `Documents\My Games\Starfield\SFSE\Logs` (SFSE and its plugins) | if changed |
| `docs\SFSE\Crashlogs\*` | `Documents\My Games\Starfield\SFSE\Crashlogs` (crash loggers) | if changed |
| `docs\StarfieldCustom.ini`, `StarfieldPrefs.ini` | `Documents\My Games\Starfield` | always |
| `appdata\plugins.txt` | `%LOCALAPPDATA%\Starfield` (the load order) | always |
| `game\Data\SFSE\...` | the game's `Data\SFSE` reports and `Plugins\*.ini/.toml/.json` settings | settings always, reports if changed |
| `mo2\...` | the MO2 profile (`plugins.txt`, `loadorder.txt`, `modlist.txt`, INIs), `overwrite\SFSE`, MO2's logs | only with `-MO2Path` |
| `vortex\` | Vortex Modlist Backup exports in Downloads | if new |
| `downloads\` | console transcripts (`sfconsole_*.txt`) in Downloads | if new |
| `screenshots\` | Steam's Starfield screenshots and photo-mode pictures (newest 40) | if new |
| `saves\` | the newest save, or a before/after pair | only when you ask |
| `events.txt` | Windows Application Error / Hang / WER events that mention Starfield | if any |
| `manifest.json` | versions of Starfield, SFSE and Engine Fixes; names, sizes and dates of the SFSE DLLs and plugins in Data; a SHA-256 for every file; warnings; skipped files | always |
| `collector-log.txt` | what the collector read and decided | always |

Report files over 50 MB are skipped unless you add `-IncludeLarge`. Saves are never skipped for size.

**Saves:** answer `y` for the newest save, or `p` for a before/after pair. The pair is the two newest *manual*
saves (`Save<N>_...`; autosaves, quicksaves and exit saves are ignored) of the character in your newest manual
save, stored as `before-...` and `after-...`. Make one hard save before you test and one after.

## Your setup

| Setup | What to do |
|---|---|
| Steam, default library | nothing |
| Steam, another library | nothing: it reads Steam's library list |
| Game Pass / Xbox app | nothing: it checks `<drive>:\XboxGames\Starfield\Content` on every drive (and the folder named in each drive's `.GamingRoot`). Game Pass's `Starfield.exe` has no version number, so the manifest shows its size and date. |
| Game installed somewhere else | `-GamePath "E:\Games\Starfield"` (the folder with `Starfield.exe`; its `Data` folder also works) |
| Vortex | nothing: Vortex deploys into the game's Data folder |
| Mod Organizer 2 | `-MO2Path "<instance folder>"` (the folder with `ModOrganizer.ini`; a global instance is `%LOCALAPPDATA%\ModOrganizer\Starfield`). `-MO2Profile <name>` picks a profile other than the selected one. Without `-MO2Path` it only says that it found MO2. It reads the folders in `ModOrganizer.ini` with the same rules as MO2 (Qt 5), so custom profiles and overwrite folders are found. Qt's binary `@Variant(...)` and `@DateTime(...)` values aren't decoded (MO2 doesn't write them for folders). |
| Game Pass saves | Game Pass keeps saves in a container, not as `.sfs` files. Export them first (for example with [XGP-save-extractor](https://github.com/Z1ni/XGP-save-extractor)) and pass `-SavesDir`. |
| Documents moved (OneDrive) | nothing: it asks Windows where Documents is. `-MyGamesDir` overrides it. |

## Options

| Option | What it does |
|---|---|
| `-Note "text"` | what you tested (asked for if not given) |
| `-Hours 24` | collect the last 24 hours instead of "since the last run" |
| `-IncludeSaves` (`-SaveCount 3`) | add the newest save (or three) |
| `-SavePair` | add the before/after pair of manual saves |
| `-SavesDir <dir>` | read saves from another folder |
| `-IncludeLarge` | include report files over 50 MB |
| `-GamePath <dir>` | the game folder |
| `-MO2Path <dir>`, `-MO2Profile <name>` | Mod Organizer 2 instance and profile |
| `-ScreenshotDir "<dir>;<dir>"` | where to look for screenshots instead of Steam's and photo mode's |
| `-VortexExportDir <dir>`, `-DownloadsDir <dir>` | where Vortex exports and console transcripts are |
| `-MyGamesDir <dir>`, `-PluginsTxtDir <dir>` | non-standard Documents or `plugins.txt` folders |
| `-OutDir <dir>` | where the zip goes (default `Documents\StarfieldLogs`) |
| `-LogFile <file>` | also write the troubleshooting log to this file |
| `-Verbose` | show the troubleshooting log on screen as it runs |
| `-NoPrompt` | ask nothing (for scripts) |
| `-DryRun` | build the zip but don't move the "last run" marker, so the next run covers the same window |

The "last run" marker is `Documents\StarfieldLogs\.last-run-<Windows user>` (in `-OutDir`). Delete it to start
over from 12 hours.

## Troubleshooting

Every zip holds `collector-log.txt`: each folder it looked in, each file it copied or skipped and why, and every
warning. To see it as it runs, or to keep it when something fails before the zip is made:

```
powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Verbose -LogFile sf-logs.txt
```

| Message | What to do |
|---|---|
| `Starfield is still running` | quit the game first, so the logs are complete |
| `No Papyrus.0.log found` / `does not turn on Papyrus logging` | see [Turn on Papyrus logging first](#turn-on-papyrus-logging-first) |
| `Starfield install folder not found` | pass `-GamePath` |
| `No ModOrganizer.ini in -MO2Path` | pass the instance folder (MO2: Settings > Paths shows it) |
| `Could not copy <file>` | another program holds it, or you're running as another Windows user: run it as the user who plays |
| `Crash log found!` | nothing to fix here: the crash log is in the zip |

**Exit codes:** 0 = zip made (warnings are in the manifest), 1 = you stopped it because the game was running,
2 = an error stopped it (the message names it; nothing was zipped).

## For mod authors: reading a package

1. Read `manifest.json` first: the game, SFSE and Engine Fixes versions, and the warnings.
2. `docs\Logs\Script\Papyrus.0.log` and `Papyrus.1.log` hold the session (quitting to the main menu starts a new
   `Papyrus.0.log`, so the session you want may be `.1`). Search for your mod's log prefix.
3. `appdata\plugins.txt` (or `mo2\profile\plugins.txt`) is the load order; `listing.dataPlugins` in the manifest
   shows which plugin files were in Data.
4. A crash log is in `docs\SFSE\Crashlogs` or `game\Data\SFSE\Plugins`.

[papyrus-log-check](https://github.com/taosecurity/papyrus-log-check) summarizes a Papyrus log's errors.

## Privacy

The zip holds your logs, settings and load order, and saves if you ask. The collector writes `%USERPROFILE%` in
place of your Windows user folder in the manifest, the log and `events.txt`, and leaves out your computer and
user names. The logs themselves are copied as they are, and some of them (crash logs, SFSE logs) contain your
folder paths. Look inside before you post a zip in public. Details: [PRIVACY.md](PRIVACY.md).

## Tests

`tests\Test-Collector.ps1` builds a fake Starfield setup (Steam-style game folder, MO2 instance, saves,
screenshots) in a temp folder, runs the collector against it and checks the zip. It needs no game:

```
powershell -ExecutionPolicy Bypass -File .\tests\Test-Collector.ps1
```

## License

MIT. See [LICENSE](LICENSE).
