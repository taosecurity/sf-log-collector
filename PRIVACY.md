# Privacy

sf-log-collector runs on your own computer, offline. It collects no data for its author and sends nothing
anywhere. The zip it makes stays on your PC until you send it to someone.

## What it does not do

- It makes no network connections.
- It has no telemetry, analytics, crash reporting or update checks.
- It starts no other programs.
- It changes nothing in the game folder, your settings or your mods.

## What it reads

- `Documents\My Games\Starfield`: Papyrus logs, SFSE logs, crash logs, `StarfieldCustom.ini`,
  `StarfieldPrefs.ini`, and saves only when you ask for them;
- `%LOCALAPPDATA%\Starfield\plugins.txt`;
- the game folder: `Data\SFSE` reports and settings files, and the names, sizes and dates of the plugins in
  `Data` and the DLLs in `Data\SFSE\Plugins` (their contents are never read or copied);
- to find the game folder: Steam's location in the Windows registry (`SteamPath`, `InstallPath`), Steam's
  `libraryfolders.vdf`, and whether `<drive>:\XboxGames\Starfield\Content` (or the folder named in each drive's
  `.GamingRoot` file) exists on each drive;
- Downloads: Vortex Modlist Backup exports (`vortex-starfield-*-backup-*.json`) and console transcripts
  (`sfconsole_*.txt`);
- screenshots: Steam's Starfield screenshot folders (`Steam\userdata\<id>\760\remote\1716740\screenshots`) and
  photo mode's `Documents\My Games\Starfield\Data\Textures\Photos`, or the folders you name;
- the Mod Organizer 2 instance you name with `-MO2Path` (its `ModOrganizer.ini`, the profile's text files,
  `overwrite\SFSE`, and its logs). Without `-MO2Path` it only checks whether
  `%LOCALAPPDATA%\ModOrganizer\Starfield\ModOrganizer.ini` exists;
- the Windows Application event log: Application Error, Application Hang and Windows Error Reporting events that
  mention Starfield;
- whether a process named `Starfield` is running.

## What it writes

- the zip, in `Documents\StarfieldLogs` or the `-OutDir` folder;
- `.last-run-<Windows user>` in the same folder (the time of the run);
- a staging folder in your temp folder, deleted when it finishes;
- with `-LogFile <file>`: the troubleshooting log, added to the end of that file.

## What the zip contains

Your logs, INIs, load order, mod settings, the screenshots from the window, and saves if you asked. In its own
files (`manifest.json`, `collector-log.txt`, `events.txt`) the collector writes `%USERPROFILE%` in place of your
Windows user folder and leaves out your computer and user names.

Without `-Redact`, the copied logs are not changed, and some of them (crash logs, SFSE logs, the Papyrus log)
contain folder paths with your Windows user name, and sometimes your computer name.

With `-Redact` (or `y` at the double-click question), the collector also changes the copies of every text file it
puts in the zip (logs, `plugins.txt`, INIs, crash logs, Vortex exports) and its own files: your Windows user folder
becomes `%USERPROFILE%`, your Windows user name `<user>`, your computer name `<computer>`, and your Steam account
number in `userdata\<number>` becomes `userdata\<steam-id>`. Your original files are never changed. Plugin names,
form IDs, mod names and script names stay as they are, because a mod author needs them, unless one of them is your
user name or computer name as a whole word. These are not changed even
with `-Redact`:

- saves (they contain your character's name, which is also in the save's file name in hex);
- screenshots, and any copied file that doesn't look like text;
- the names of the files inside the zip, and the zip's own name, which includes the note you typed;
- a user name under 3 letters outside `\Users\<name>` paths (so a name such as "ui" doesn't replace every "UI" in a
  log), and a name inside a file in an older Windows text encoding when the name has letters outside English.

Look inside before you post a zip in public.

## Downloading it

Downloading sf-log-collector from GitHub is covered by GitHub's own
[privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement). Its
author receives only the public download counts GitHub shows.

## Questions

Open an issue at https://github.com/taosecurity/sf-log-collector/issues.
