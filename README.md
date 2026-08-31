# Equicord Plugin Injector

A one-click Windows installer for non-technical users. It pulls your custom
Equicord plugins live from GitHub, injects them into the **latest** Equicord
source, builds Equicord locally on the user's PC, and patches their installed
Discord app.

The user needs **nothing installed**: no Git, no Node, no Bun, no command
line. They download one zip, extract it, and double-click `INSTALL.bat`.

Modeled on the GIF Blacklist Injector design, but the plugins are no longer
bundled in the package; they are fetched fresh from your GitHub repo on every
run, so you update them by pushing to GitHub and re-sharing the same package.

## How it works (under the hood)

1. **Portable Node:** downloads the official `nodejs.org` win-x64 zip into
   `%LOCALAPPDATA%\EquicordPluginInjector\tools`. Downloaded once, reused on
   future runs.
2. **Portable Git:** downloads the official **MinGit** build (Git for
   Windows, zip, no installer) into the same tools folder.
3. **pnpm:** installed locally into that tools folder via Node's bundled npm
   (`pnpm@11.22.0`, matching Equicord's pinned `packageManager`).
4. **Latest Equicord:** **cloned** (`git clone --depth 1`) with the portable
   Git into `%LOCALAPPDATA%\EquicordPluginInjector\equicord`. Because it's a
   real git checkout (a real `.git`), Equicord's built-in **Updates** tab works
; it doesn't error with `fatal: not a git repository`. Re-runs do
   `git fetch` + `git reset --hard origin/main`.
5. **Plugin injection:** downloads your plugin repo
   (`https://github.com/Unalphabetical/Equicord-Plugin`) as a zip each run,
   finds its default branch, and copies every top-level **plugin folder**
   (a folder containing `index.tsx`) into Equicord's `src/userplugins/`. That
   folder is gitignored by Equicord, so it survives `git pull`/`reset`
   untouched. Adding a new plugin to your GitHub repo automatically installs
   it on the user's next run.
6. **Updater wiring:** Equicord's Updates tab runs `git` and `node` from
   `PATH` inside Discord's main process. One line is added to
   `src/main/updater/git.ts` pointing those calls at the portable Git/Node in
   the tools folder. Applied to a pristine checkout every run (the reset above
   guarantees that).
7. **Build:** runs `pnpm install --frozen-lockfile` then `pnpm build` with
   the updater **enabled**. Because it's a real checkout, the build's own
   `git rev-parse` / `git remote` calls resolve the real commit hash and repo
   URL; no `EQUICORD_HASH` / `EQUICORD_REMOTE` overrides needed.
8. **Patch:** runs Equicord's own `scripts/runInstaller.mjs -- --install`,
   which downloads the official `EquilotlCli.exe` and patches the detected
   Discord app. No admin rights needed (Discord lives in LocalAppData).

## How users update

- **In Discord:** Settings > **Updates** shows the repo, pending commits, and
  an **Update & Rebuild** button (pulls + rebuilds `dist/`). Then restart
  Discord.
- **Or:** close Discord and re-run `INSTALL.bat`, which fetches a fresh copy
  of your plugins + Equicord, rebuilds and re-patches.

> Keep in mind: re-running `INSTALL.bat` is the only way non-tech users get
> **plugin** updates (the in-app Updates tab updates Equicord, not your
> plugins). To ship a plugin change, push to GitHub and tell them to re-run it.

## Auto-updating the installer itself

The installer also keeps **itself** current. At the very start of each run it
queries
[`Unalphabetical/Equicord-Injector`](https://github.com/Unalphabetical/Equicord-Injector),
downloads the latest copies of `install.ps1`, `INSTALL.bat`, `README.txt` and
`config.json` straight from GitHub, and — if `install.ps1` changed — re-runs
itself in the same window with the fresh version. Users never need to re-share
or re-download the zip to receive installer fixes.

Details:

- Fails gracefully: if GitHub is unreachable it just proceeds with the copy
already on disk.
- Your local `config.json` is backed up to `config.json.pre-update` before it's
replaced, so a per-machine setting is never lost silently.
- Can be disabled for development by setting `"autoUpdateInjector": false` in
`config.json`.
- The updater only needs plain PowerShell (no Git/Node), so it works on stock
Windows.

## Cleaning up the portable tools

By default the installer keeps its portable Node/Git/pnpm (and the Equicord
checkout) in `%LOCALAPPDATA%\EquicordPluginInjector` so Equicord's in-app
**Updates** tab keeps working.

If you'd rather not keep ~200 MB of tools around (and are happy getting
updates only by re-running `INSTALL.bat`), edit `config.json` in the
`EquicordInjector` folder and set `"cleanupPortableTools": true`. After a
successful install it deletes the portable tools. This is read by the
installer every run, so you can set it before zipping/sharing the folder.
**Warning:** with this on, Settings > **Updates** stops working, since that
tab calls the portable git/node.

## Developer: how to distribute

1. Push your plugin changes to
   `https://github.com/Unalphabetical/Equicord-Plugin` (any plugin folder with
   an `index.tsx` is picked up automatically).
2. Share the injector with people: zip up the whole `EquicordInjector/`
   folder (right-click → Send to → Compressed (zipped) folder) or send it
   directly.
3. They extract it (if zipped), read `README.txt`, and run `INSTALL.bat`.

## Requirements on the user's PC

- Windows 10/11 (64-bit)
- The normal Discord desktop app installed
- An internet connection

## If something breaks

- Tell the user to fully close Discord (tray icon → Quit) before running.
- Darkmode the red/blue messages in the window; they say what failed.
- Plugins must be turned on in Discord: Settings > **Plugins**.
- Windows may show SmartScreen for the unsigned `.bat`/`.ps1`; instruct them to
  click "More info" → "Run anyway".

## Notes / limitations

- The in-app **Update & Rebuild** needs the checkout plus its `node_modules`
  and the portable tools to stay in `%LOCALAPPDATA%\EquicordPluginInjector`.
  Tell users not to delete that folder.
- The updater patch is a local modification of one line in
  `src/main/updater/git.ts`. If an upstream Equicord change ever touches that
  line, the in-app `git pull` will stop with a conflict and the installer will
  throw a clear "patch anchor no longer matches" error; update the installer
  in that case. Re-running `INSTALL.bat` always resets and re-applies it.
- Re-running `INSTALL.bat` fetches + resets + rebuilds, which is how users
  recover after Discord updates, failed in-app updates, or Equicord changes.
- The plugin repo is mirrored to the installer's `install.ps1` top section
  (`$PluginRepoOwner` / `$PluginRepoName`); point it anywhere if you want to
  switch sources.