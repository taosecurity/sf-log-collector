# AGENTS.md: sf-log-collector for AI assistants

Plain steps for an AI assistant helping someone use sf-log-collector. Every command here was run once on
sf-log-collector 2.1.0 before release. The [README](README.md) has the full description.

## 1. What it is for

One PowerShell script, `Collect-StarfieldTestLogs.ps1` (with a double-click launcher,
`Collect-StarfieldTestLogs.cmd`), that gathers a Starfield player's logs into one zip for a bug report: Papyrus
logs, SFSE and crash logs, game INIs, `plugins.txt`, SFSE plugin settings, Mod Organizer 2 profile files, new
screenshots, Windows crash events, and saves when asked. It collects only files changed since its last run (12
hours on the first run), and always the two newest Papyrus logs, the INIs and `plugins.txt`.

Use it when a player needs to send logs to a mod author, or when you need to read their logs yourself. Don't use
it to analyze logs (it only collects; for Papyrus errors see papyrus-log-check), and don't use it while Starfield
is running.

## 2. Prerequisites

- Windows 10 or 11 with Windows PowerShell 5.1 (built in) or PowerShell 7. Tested on 5.1, 7.5 and 7.7.
- No modules, no admin rights, no network.
- Starfield from Steam or Game Pass. Vortex works as is; Mod Organizer 2 needs `-MO2Path`.

## 3. Install

Download `sf-log-collector-2.1.0.zip` from https://github.com/taosecurity/sf-log-collector/releases and check it
against the `.sha256` file:

    certutil -hashfile sf-log-collector-2.1.0.zip SHA256

(In PowerShell, `(Get-FileHash sf-log-collector-2.1.0.zip).Hash` prints the same hash in capitals; compare without
case.) Unpack it anywhere: everything is inside one folder, `sf-log-collector-2.1.0\`, and every command below runs
from there. Keep `Collect-StarfieldTestLogs.cmd` and `Collect-StarfieldTestLogs.ps1` in the same folder.

## 4. Prove the install works

The bundled test builds a fake Starfield setup in the temp folder and needs no game. From the unpacked folder:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Collector.ps1

It ends with `<N> passed, 0 failed` and exit code 0 (N is 197 on 2.1.0, a little lower if a test prints `skip`;
what matters is `0 failed`). The test works in a new `%TEMP%\sflc-test-<random>` folder and deletes it at the end;
it writes nothing else. On a player's PC, a dry run is the quick check (it writes a zip but doesn't move the
"last run" marker):

    powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -DryRun

It prints `Done.` and the zip's path, and exits with code 0. Warnings are normal when the game hasn't logged
anything yet: "No Papyrus.0.log found" (Papyrus logging is off), and "Documents\My Games\Starfield not found"
(the game was never started by this Windows user, for example when you run it from another account than the
player's: run it as the player). "Starfield is still running" is only a warning with `-NoPrompt`; the collector
goes on.

## 5. Common tasks

All commands run from the unpacked folder in PowerShell. In `cmd.exe`, pass the same options to the `.cmd`.

- Player, after quitting the game: double-click `Collect-StarfieldTestLogs.cmd` and answer the three questions
  (what was tested, saves, and whether to hide the Windows user name; Enter means no for the last two).
- The same with no questions, with a note:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -Note "quest stuck at step 3"

- Include the newest save, or a before/after pair of manual saves:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -IncludeSaves
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -SavePair

- Before the player sends the zip to someone else or hands it to you: add `-Redact`, which replaces the Windows
  user folder, user name, computer name and Steam account number in every copied text file with `%USERPROFILE%`,
  `<user>`, `<computer>` and `userdata\<steam-id>`. Saves (which hold the character's name) and screenshots are
  copied as they are, also with `-SavePair`:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -Redact -SavePair

- Mod Organizer 2 (the instance folder holds `ModOrganizer.ini`):

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -MO2Path "$env:LOCALAPPDATA\ModOrganizer\Starfield"

- Game in an unusual folder, or a longer window:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -GamePath "E:\Games\Starfield" -Hours 24

- Troubleshoot a run:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -Verbose -LogFile sf-logs.txt

  `-Verbose` (PowerShell's common switch) prints each log line on screen as `VERBOSE: ...`. `-LogFile sf-logs.txt`
  (short form `-Log sf-logs.txt`) also writes the log to that file, which is the only copy when a run stops with
  exit code 2 before the zip is made.

## 6. Inputs

Only files on the local PC. It reads `Documents\My Games\Starfield` (logs, INIs, saves), `%LOCALAPPDATA%\Starfield`
(`plugins.txt`), the game folder (found through Steam's registry keys and `libraryfolders.vdf`, then
`<drive>:\XboxGames\Starfield\Content`), Downloads (Vortex Modlist Backup exports, `sfconsole_*.txt`), Steam's
Starfield screenshot folders and photo-mode pictures, the MO2 instance given with `-MO2Path`, and the Windows
Application event log. Every path can be overridden; `Get-Help .\Collect-StarfieldTestLogs.ps1 -Detailed` lists
the options.

## 7. Outputs

- `Documents\StarfieldLogs\StarfieldLogs-<yyyyMMdd-HHmmss>-<note>.zip` (`-OutDir` moves it). Inside:
  `manifest.json` (versions, counts, warnings, skipped files, every file's SHA-256, a listing of Data plugins and
  SFSE DLLs by name), `collector-log.txt`, and the folders `docs\`, `appdata\`, `game\`, `mo2\`, `vortex\`,
  `downloads\`, `screenshots\`, `saves\`, `events.txt`. The README's table maps each to its source. With
  `-Redact`, `manifest.json` has `"redact": true`, and each file that redaction changed has `"redacted": true`,
  `size` and `sha256` of the copy in the zip, and `sourceSize` (the original's size).
- `.last-run-<Windows user>` in the same folder as the zip (`Documents\StarfieldLogs`, or the `-OutDir` folder): the
  time of the last run (not written with `-DryRun`). Each output folder has its own marker, so a different
  `-OutDir` starts again with the 12-hour window.
- With `-LogFile <file>` (or its short form `-Log <file>`): the troubleshooting log is appended to that file (a
  relative path is taken from the current folder). The summary's `Log :` line names it.

## 8. Exit codes

- 0: the zip was made. Warnings are printed and listed in `manifest.json`.
- 1: Starfield was running and the player answered "no" to "Collect anyway?" (nothing collected). With
  `-NoPrompt` there is no question: the run warns and goes on, so this code never happens.
- 2: an error stopped it. The message names the problem; nothing was zipped. Rerun with `-Verbose -LogFile`.

## 9. Log location

`collector-log.txt` inside every zip (always on, nothing to turn on), plus the `-LogFile <file>` (or `-Log <file>`)
file if given; `-Verbose` shows the same lines on screen. The log hides the Windows user folder as `%USERPROFILE%`.

## 10. Limits

- It never changes the game, its settings or any mod, and never deletes anything except its own temp staging
  folder (and an older zip of the same name in the output folder).
- It never copies `.exe .dll .pdb .dmp .esm .esp .esl .ba2` files. Report files over 50 MB are skipped unless
  `-IncludeLarge`.
- It makes no network connections and uploads nothing. Sending the zip is up to the player.
- It writes `%USERPROFILE%` in place of the Windows user folder in its own files (manifest, log, `events.txt`).
  Without `-Redact` it copies logs as they are. With `-Redact` the copied text files are redacted too, but saves,
  screenshots, files that don't look like text and the zip's entry names are not, a user name under 3 letters is
  hidden only in `\Users\<name>` paths, and the zip's file name comes from the note as typed. Tell the player to
  look inside before posting a zip in public.
- Game Pass saves are in a container it can't read: export them first and pass `-SavesDir`.
- Windows only.
- The test script's `-Shell` takes `powershell`, `pwsh` or the full path of `powershell.exe` or `pwsh.exe`; a
  `\\?\` prefix is dropped first, because Windows PowerShell 5.1 can't start when launched through a `\\?\` path.
