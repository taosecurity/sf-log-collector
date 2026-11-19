# AGENTS.md: sf-log-collector for AI assistants

Plain steps for an AI assistant helping someone use sf-log-collector. Every command here was run once on
sf-log-collector 2.0.0 before release. The [README](README.md) has the full description.

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

- Windows 10 or 11 with Windows PowerShell 5.1 (built in) or PowerShell 7. Tested on 5.1 and 7.5.
- No modules, no admin rights, no network.
- Starfield from Steam or Game Pass. Vortex works as is; Mod Organizer 2 needs `-MO2Path`.

## 3. Install

Download `sf-log-collector-2.0.0.zip` from https://github.com/taosecurity/sf-log-collector/releases and check it
against the `.sha256` file:

    certutil -hashfile sf-log-collector-2.0.0.zip SHA256

Unpack it anywhere. Keep `Collect-StarfieldTestLogs.cmd` and `Collect-StarfieldTestLogs.ps1` in the same folder.

## 4. Prove the install works

The bundled test builds a fake Starfield setup in the temp folder and needs no game. From the unpacked folder:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Collector.ps1

It ends with `<N> passed, 0 failed` and exit code 0 (N is 101 on 2.0.0, a little lower if a test prints `skip`;
what matters is `0 failed`). On a player's PC, a dry run is the quick check (it writes a
zip but doesn't move the "last run" marker):

    powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -DryRun

It prints `Done.` and the zip's path, and exits with code 0. Warnings (for example "No Papyrus.0.log found") are
normal on a PC where the game hasn't logged yet.

## 5. Common tasks

All commands run from the unpacked folder in PowerShell. In `cmd.exe`, pass the same options to the `.cmd`.

- Player, after quitting the game: double-click `Collect-StarfieldTestLogs.cmd` and answer the two questions.
- The same with no questions, with a note:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -Note "quest stuck at step 3"

- Include the newest save, or a before/after pair of manual saves:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -IncludeSaves
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -SavePair

- Mod Organizer 2 (the instance folder holds `ModOrganizer.ini`):

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -MO2Path "$env:LOCALAPPDATA\ModOrganizer\Starfield"

- Game in an unusual folder, or a longer window:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -GamePath "E:\Games\Starfield" -Hours 24

- Troubleshoot a run:

      powershell -NoProfile -ExecutionPolicy Bypass -File .\Collect-StarfieldTestLogs.ps1 -NoPrompt -Verbose -LogFile sf-logs.txt

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
  `downloads\`, `screenshots\`, `saves\`, `events.txt`. The README's table maps each to its source.
- `Documents\StarfieldLogs\.last-run-<Windows user>`: the time of the last run (not written with `-DryRun`).
- With `-LogFile <file>`: the troubleshooting log is appended to that file.

## 8. Exit codes

- 0: the zip was made. Warnings are printed and listed in `manifest.json`.
- 1: the player stopped it because Starfield was running (nothing collected).
- 2: an error stopped it. The message names the problem; nothing was zipped. Rerun with `-Verbose -LogFile`.

## 9. Log location

`collector-log.txt` inside every zip, plus the `-LogFile` file if given; `-Verbose` shows the same lines on screen.

## 10. Limits

- It never changes the game, its settings or any mod, and never deletes anything except its own temp staging
  folder (and an older zip of the same name in the output folder).
- It never copies `.exe .dll .pdb .dmp .esm .esp .esl .ba2` files. Report files over 50 MB are skipped unless
  `-IncludeLarge`.
- It makes no network connections and uploads nothing. Sending the zip is up to the player.
- It writes `%USERPROFILE%` in place of the Windows user folder in its own files (manifest, log, `events.txt`), but
  copies logs as they are: tell the player to look inside before posting a zip in public.
- Game Pass saves are in a container it can't read: export them first and pass `-SavesDir`.
- Windows only.
