# sf-log-collector

sf-log-collector gathers your Starfield logs into one zip with a single double-click, so you can attach that one
file to a bug report. When a mod misbehaves, its author usually asks for "your logs". Those are spread over five or
six folders, and some of them only matter if they changed during the session that went wrong.

Download the latest zip from [Releases](https://github.com/taosecurity/sf-log-collector/releases), unzip it, quit
Starfield after playing, and double-click:

```
Collect-StarfieldTestLogs.cmd
```

For AI assistants: step-by-step instructions are in [AGENTS.md](AGENTS.md).

## Example

This is a real run on a made-up test setup with two made-up mods and a crash log. Only the zip's folder is changed,
to the default one on your PC:

```
> powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "quest stuck at step 3" -Hours 2 -IncludeSaves

Starfield log collector 2.1.0

Collecting files changed last 2 hours (2026-11-20 13:36)
  ! Crash log found! (1 new log(s) in SFSE\Crashlogs)

Done.
  Package : C:\Users\<you>\Documents\StarfieldLogs\StarfieldLogs-20261120-153652-quest-stuck-at-step-3.zip
  Size    : 0.0 MB, 12 files
  Contents: papyrus 3, gameIni 2, sfseLogs 1, crashLogger 1, pluginsTxt 1, pluginIni 1, consoleTranscripts 1, screenshots 1, saves 1

Warnings:
  - Crash log found! (1 new log(s) in SFSE\Crashlogs)

Send this zip to whoever asked for your logs. Look inside first if you share it in public.
```

The zip from that run holds these files:

```
collector-log.txt
manifest.json
appdata\plugins.txt
docs\StarfieldCustom.ini
docs\StarfieldPrefs.ini
docs\Logs\Script\Papyrus.0.log
docs\Logs\Script\Papyrus.1.log
docs\Logs\Script\User\MyMod.0.log
docs\SFSE\Crashlogs\crash-2026-11-20.log
docs\SFSE\Logs\sfse.txt
downloads\sfconsole_20261120.txt
game\Data\SFSE\Plugins\NewModA.ini
saves\Save1_ABCD1234_000102_20261120100000_1_2.sfs
screenshots\a.png
```

`manifest.json` and `collector-log.txt` describe the run and aren't counted in the 12 files. When you double-click
the `.cmd` file instead, it asks what you tested, whether to add saves, and whether to hide your Windows user name
(see [Hide your user name](#hide-your-user-name--redact)), and it waits for a key press at the end so you can read
the result.

The same kind of run with `-Redact` adds one line to the summary, and the copied logs show placeholders instead of
your user folder and computer name:

```
> powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "quest stuck at step 3" -Hours 2 -Redact
...
  Contents: papyrus 1, gameIni 1, sfseLogs 1, crashLogger 1, pluginsTxt 1
  Redacted: 2 file(s) changed; saves and screenshots left as they are
...

docs\SFSE\Logs\sfse.txt in the zip:
config path = %USERPROFILE%\Documents\My Games\Starfield\SFSE\sfse.ini

docs\SFSE\Crashlogs\crash-2026-11-24.log in the zip:
Computer: <computer>
```

What it does and doesn't do:

- It collects the Papyrus script logs, SFSE and crash logs, your game INIs, `plugins.txt`, mod settings, new
  screenshots and Windows crash events, and saves if you ask for them.
- Each run picks up only what changed since the last run, so the zip covers the session you just played.
- It works with Steam and Game Pass (Xbox app), and with Vortex and Mod Organizer 2.
- It only reads. It never copies game files or programs (`.exe .dll .pdb .dmp .esm .esp .esl .ba2`), never
  changes the game and never connects to the network. [PRIVACY.md](PRIVACY.md) lists exactly what it reads.
- It needs only Windows 10 or 11 and the PowerShell that ships with them.

This tool was built with [Claude Code](https://claude.com/claude-code).

## Quick start

1. Download `sf-log-collector-2.1.0.zip` from the
   [releases page](https://github.com/taosecurity/sf-log-collector/releases) and unzip it anywhere.
2. Play until the problem happens, then **quit Starfield**.
3. Double-click **`Collect-StarfieldTestLogs.cmd`**. Type a few words about what you were doing (or press Enter),
   answer the question about saves (press Enter for none), and the question about hiding your Windows user name,
   computer name and user folder (`y` to hide them, Enter to leave the files as they are).
4. The zip is in **`Documents\StarfieldLogs`**, named `StarfieldLogs-<date>-<time>-<your words>.zip`. Attach it
   to your bug report.

The first run collects the last 12 hours. The first time, Windows may ask whether to run a file downloaded from the
internet: choose Run.

## Run it with options

To use the options below, run the script from a PowerShell window:

1. Open the unzipped folder in File Explorer.
2. Click the address bar at the top, type `powershell` and press Enter. A PowerShell window opens in that folder.
   (Or open the Start menu, type **PowerShell**, open it, and type `cd ` followed by the folder's path.)
3. Type the command, with the options you want, and press Enter:

```
powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Note "quest stuck at step 3"
```

The `-ExecutionPolicy Bypass` part lets Windows run this one script without changing your settings.

## Words used here

- **Papyrus:** Starfield's scripting language. Mods use it for quests, menus and most other things they do. The game
  can write what scripts do, and the errors they hit, to a text file: the Papyrus log.
- **SFSE:** the Starfield Script Extender, which loads `.dll` plugins that add features the game lacks. SFSE and its
  plugins write their own logs, and crash loggers for SFSE write a crash log when the game crashes.
- **Plugin:** a mod's data file (`.esm`, `.esp` or `.esl`). It adds or changes records in the game.
- **`plugins.txt`:** the game's list of plugins, with `*` before each active one. It is your load order.
- **INI file:** a small text file of settings, such as `StarfieldCustom.ini`.
- **Mod Organizer 2 (MO2) and Vortex:** the two common mod managers. MO2 keeps its own copy of `plugins.txt` and the
  INIs for each profile.

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

## Hide your user name (-Redact)

Logs often contain your Windows user name, your computer name and the path of your user folder, for example
`C:\Users\<your name>\Documents\My Games\Starfield`. If you send the zip to a mod author, post it in public or hand
it to an AI assistant, add `-Redact` (or answer `y` to the question when you double-click):

```
powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Redact
powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Redact -SavePair
```

In every text file it copies (logs, `plugins.txt`, INIs, crash logs, SFSE reports, Vortex exports, console
transcripts) and in its own `manifest.json`, `collector-log.txt` and `events.txt`, the collector then replaces:

| What | Becomes |
|---|---|
| your user folder (`C:\Users\<name>`, also written with `/`, with `\\` as in JSON, or in the short `C:\Users\NAME~1` form) | `%USERPROFILE%` |
| your Windows user name, as a whole word | `<user>` |
| your computer name, as a whole word | `<computer>` |
| your Steam account number in `userdata\<number>` | `userdata\<steam-id>` |

Only the copies in the zip change; your own files are never touched. Plugin names, form IDs, mod, quest and script
names stay as they are, because they are what a mod author needs, unless one of them is your user name or computer
name as a whole word (a plugin named after you becomes `<user>.esm`). The summary's `Redacted:` line says how many files
were changed, and `collector-log.txt` lists each one with the number of replacements (never the values).

What `-Redact` does not hide:

- **Saves.** They are copied as they are, also with `-SavePair` or `-IncludeSaves`. A save holds your character's
  name, and its file name holds that name in hex. Leave saves out if that matters to you.
- **Screenshots**, and any copied file that doesn't look like text (a zero byte in its first 64 KB). Files named
  `.log`, `.txt`, `.ini`, `.json`, `.toml`, `.xml`, `.csv`, `.cfg`, `.yaml` or `.yml` are always treated as text, so a log cut off by a crash, which can end in
  zero bytes, is still redacted.
- **File names.** The names of the files inside the zip are not changed, and the zip's own name is built from the
  note you typed.
- **Short names.** A user name under 3 letters is hidden only in `\Users\<name>` paths, so a name such as `ui`
  doesn't turn every "UI" in a log into `<user>`; a computer name under 3 letters is not replaced. A longer name
  that is also an ordinary word (such as `Player`) is replaced wherever that word appears.
- **Some old text files.** In a file saved in an older Windows text encoding rather than UTF-8 or UTF-16, a name
  with letters outside English may not be found. Everything else in such a file is kept byte for byte.

If a text file can't be redacted (it can't be read, or it isn't valid text in its encoding), it is left out of the
zip with a warning rather than sent unredacted. Without `-Redact`, every file is copied byte for byte, as in earlier versions.

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
| `-LogFile <file>` (short form `-Log <file>`) | also write the troubleshooting log to this file (added to the end if it exists) |
| `-Verbose` | show the troubleshooting log on screen as it runs (PowerShell's own switch; lines start with `VERBOSE:`) |
| `-Redact` | hide your user folder, user name, computer name and Steam account number in the copied text files (asked for if not given; see [Hide your user name](#hide-your-user-name--redact)) |
| `-NoPrompt` | ask nothing (for scripts); without `-Redact` that means no redaction |
| `-DryRun` | build the zip but don't move the "last run" marker, so the next run covers the same window |

The "last run" marker is `Documents\StarfieldLogs\.last-run-<Windows user>` (in `-OutDir`). Delete it to start
over from 12 hours.

## Troubleshooting

Every zip holds `collector-log.txt`: each folder it looked in, each file it copied or skipped and why, and every
warning. To see it as it runs, or to keep it when something fails before the zip is made:

```
powershell -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -Verbose -LogFile sf-logs.txt
```

Where the log goes: it is always inside the zip as `collector-log.txt`, so there is nothing to turn on. `-LogFile`
(or its short form `-Log`) also writes it to the file you name, in the folder you run the command from unless you
give a full path, and the summary's `Log :` line shows where. That file is the only copy when a run stops with an
error before the zip is made. `-Verbose` shows the same lines on screen. The log shows `%USERPROFILE%` in place of
your Windows user folder.

| Message | What to do |
|---|---|
| `Starfield is still running` | quit the game first, so the logs are complete |
| `No Papyrus.0.log found` / `does not turn on Papyrus logging` | see [Turn on Papyrus logging first](#turn-on-papyrus-logging-first) |
| `Starfield install folder not found` | pass `-GamePath` |
| `No ModOrganizer.ini in -MO2Path` | pass the instance folder (MO2: Settings > Paths shows it) |
| `Could not copy <file>` | another program holds it, or you're running as another Windows user: run it as the user who plays |
| `Crash log found!` | nothing to fix here: the crash log is in the zip |
| `Left out <file> because it could not be redacted` | with `-Redact`, that file couldn't be read as text; send it by hand after looking inside, or run without `-Redact` |

Exit codes:

- **0:** the zip was made. Any warnings are in the manifest.
- **1:** the game was running and you answered "no" to "Collect anyway?". With `-NoPrompt` it only warns and goes on.
- **2:** an error stopped it. The message names it, and nothing was zipped.

## For mod authors: reading a package

1. Read `manifest.json` first: the game, SFSE and Engine Fixes versions, and the warnings.
2. `docs\Logs\Script\Papyrus.0.log` and `Papyrus.1.log` hold the session (quitting to the main menu starts a new
   `Papyrus.0.log`, so the session you want may be `.1`). Search for your mod's log prefix.
3. `appdata\plugins.txt` (or `mo2\profile\plugins.txt`) is the load order; `listing.dataPlugins` in the manifest
   shows which plugin files were in Data.
4. A crash log is in `docs\SFSE\Crashlogs` or `game\Data\SFSE\Plugins`.
5. If `manifest.json` has `"redact": true`, the player used `-Redact`: `%USERPROFILE%`, `<user>`, `<computer>` and
   `<steam-id>` are placeholders. Each changed file has `"redacted": true`; its `size` and `sha256` describe the copy
   in the zip, and `sourceSize` is the original's size.

[papyrus-log-check](https://github.com/taosecurity/papyrus-log-check) summarizes a Papyrus log's errors.

## Privacy

The zip holds your logs, settings and load order, and saves if you ask. The collector writes `%USERPROFILE%` in
place of your Windows user folder in the manifest, the log and `events.txt`, and leaves out your computer and
user names. Without `-Redact` the logs themselves are copied as they are, and some of them (crash logs, SFSE logs)
contain your folder paths. With `-Redact` those are hidden too, except in saves, screenshots and file names (see
[Hide your user name](#hide-your-user-name--redact)). Look inside before you post a zip in public. Details:
[PRIVACY.md](PRIVACY.md).

## Tests

`tests\Test-Collector.ps1` builds a fake Starfield setup (Steam-style game folder, MO2 instance, saves,
screenshots) in a temp folder, runs the collector against it and checks the zip. It needs no game:

```
powershell -ExecutionPolicy Bypass -File .\tests\Test-Collector.ps1
```

It runs the collector with the PowerShell that started it. `-Shell powershell` or `-Shell pwsh` (or the full path
of `powershell.exe` or `pwsh.exe`) picks another one, and the `Shell` line at the top says which one ran. A `\\?\`
prefix on that path is dropped first, because Windows PowerShell 5.1 can't start when launched through a `\\?\`
path.

## Found a mistake?

Open an issue: https://github.com/taosecurity/sf-log-collector/issues. Changes are listed in
[CHANGELOG.md](CHANGELOG.md).

## Credits and license

sf-log-collector was made by Richard Bejtlich. It uses only Windows PowerShell and .NET, which ship with Windows.
For Game Pass saves, the README points to [XGP-save-extractor](https://github.com/Z1ni/XGP-save-extractor) by Z1ni,
which isn't included. Starfield belongs to Bethesda Softworks, and the collector copies no game files.

sf-log-collector is released under the MIT license (see [LICENSE](LICENSE)).
