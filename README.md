# Equicord Plugin Injector

One double-click installs your custom Discord plugins. No Git, no Node, no
command line needed.

[Equicord](https://github.com/Equicord/Equicord) is a modification of the
Discord desktop app, and your plugins live in a GitHub repo. This installer is
the bridge between the two: it pulls the latest plugins, builds Equicord on the
user's own PC, and patches Discord so the plugins appear.

Someone receiving it does exactly three things: extract the zip, make sure
Discord is closed, double-click `INSTALL.bat`. Then they wait a few minutes and
open Discord. That's it.

## What happens when they run it

The installer gets everything it needs on its own, including its own copies of
Node.js and Git. Those land in a folder on the user's PC instead of being
installed system-wide, so nothing touches their existing setup.

It fetches the newest version of the plugin repo, downloads the newest
Equicord, builds them together, and patches Discord. No admin rights are needed.
Discord installs to a per-user location, so there's nothing to elevate for.

Every run starts fresh: the Equicord copy is reset to match upstream and the
plugins are re-downloaded. Nothing carries over from last time except the
already-downloaded tools, which get reused to save time.

## How people update

There are two different updates, and it's worth keeping them straight.

**Equicord itself**: Settings (gear icon) → **Updates** shows what's pending
with an **Update & Rebuild** button. It pulls, rebuilds, and the user restarts
Discord. This works because the installer leaves a real Git checkout in place
with the tools still on disk.

**Your plugins**: Discord's Updates tab doesn't know these exist. The only way
to pick up a plugin change is to close Discord and run `INSTALL.bat` again.

That second one is the thing to keep in mind when you ship plugin work: push to
GitHub, then tell people to re-run the installer.

## Distributing it

1. Push your plugin changes to
   [`Unalphabetical/Equicord-Plugin`](https://github.com/Unalphabetical/Equicord-Plugin).
   Any top-level folder containing an `index.tsx` is picked up automatically.
2. Zip up the whole `EquicordInjector/` folder and share it, or send the folder
   directly.
3. They extract it, read `README.txt`, and run `INSTALL.bat`.

The plugins aren't bundled into the zip. They're fetched from GitHub on every
run, so the same package keeps working as you update.

## What they need

- Windows 10 or 11, 64-bit
- The regular Discord desktop app
- An internet connection

## When something goes wrong

- **Tell them to fully quit Discord first**: right-click the tray icon →
  Quit. A minimized Discord is still running, and the patch will fail.
- **The window already tells them what failed.** The red and blue lines are the
  reason; everything else is progress noise.
- **SmartScreen may appear** on the unsigned `.bat`/`.ps1`. More info → Run
  anyway. Some antivirus software flags it too; allow it once.
- **Plugins need to be switched on**: Settings → **Plugins**. Installing
  doesn't enable them.

## Reclaiming space

The installer's private copies of Node, Git, and pnpm take up roughly 200 MB.
They live in `%LOCALAPPDATA%\EquicordPluginInjector` and need to stay put for
Discord's Updates tab to keep working.

Users can drop just those tools whenever they like with `CLEANUP.bat` in the
`EquicordInjector` folder. Discord, Equicord, and the plugins all stay
untouched, Discord doesn't even need to be closed, and it reports how much space
it freed. To update afterwards they just run `INSTALL.bat` again; the tools come
back on the first such run.

You can also set `"cleanupPortableTools": true` in `config.json` to delete the
tools automatically after a successful install. Worth doing before you zip the
folder if you want the smallest possible package. The trade-off is the same:
Discord's Updates tab stops working, and updates happen by re-running
`INSTALL.bat`.

## The installer keeps itself current

At the very start of each run it checks
[`Unalphabetical/Equicord-Injector`](https://github.com/Unalphabetical/Equicord-Injector)
for newer copies of `install.ps1`, `INSTALL.bat`, `cleanup.ps1`, `cleanup.bat`,
`README.txt`, and `config.json`. If `install.ps1` changed, it re-runs itself in
the same window with the fresh version, so installer fixes reach people
without you re-sharing anything.

- If GitHub is unreachable it just carries on with the copy on disk.
- A local `config.json` is backed up to `config.json.pre-update` before being
  replaced, so a per-machine setting is never lost silently.
- Set `"autoUpdateInjector": false` in `config.json` to turn this off while
  you're developing.
- It only needs plain PowerShell, so it works on a stock Windows machine.

---

## Under the hood

The rest of this document is for whoever maintains the installer.

### Install sequence

1. **Portable Node**: downloads the official `nodejs.org` win-x64 zip into
   `%LOCALAPPDATA%\EquicordPluginInjector\tools`. Downloaded once, reused
   afterwards.
2. **Portable Git**: downloads the official **MinGit** build (Git for Windows,
   zip, no installer) into the same tools folder.
3. **pnpm**: installed locally into that tools folder via Node's bundled npm
   (`pnpm@11.22.0`, matching Equicord's pinned `packageManager`).
4. **Latest Equicord**: cloned with `git clone --depth 1` into
   `%LOCALAPPDATA%\EquicordPluginInjector\equicord`. Because it's a real git
   checkout with a real `.git`, Equicord's built-in **Updates** tab works
   instead of erroring with `fatal: not a git repository`. Re-runs do
   `git fetch` + `git reset --hard origin/main`.
5. **Plugin injection**: downloads the plugin repo
   (`https://github.com/Unalphabetical/Equicord-Plugin`) as a zip each run,
   finds its default branch, and copies every top-level **plugin folder** (a
   folder containing `index.tsx`) into Equicord's `src/userplugins/`. That
   folder is gitignored by Equicord, so it survives `git pull` and `reset`
   untouched. Adding a plugin upstream installs it on the user's next run.
6. **Updater wiring**: Equicord's Updates tab runs `git` and `node` from `PATH`
   inside Discord's main process. One line is added to
   `src/main/updater/git.ts` pointing those calls at the portable Git and Node.
   Applied to a pristine checkout every run, since the reset above guarantees
   one.
7. **Build**: runs `pnpm install --frozen-lockfile` then `pnpm build` with the
   updater **enabled**. Because it's a real checkout, the build's own
   `git rev-parse` / `git remote` calls resolve the real commit hash and repo
   URL, so no `EQUICORD_HASH` / `EQUICORD_REMOTE` overrides are needed.
8. **Patch**: runs Equicord's own `scripts/runInstaller.mjs -- --install`,
   which downloads the official `EquilotlCli.exe` and patches the detected
   Discord app.

### Settings

Both live in `EquicordInjector/config.json`:

| Setting | Default | Effect |
| --- | --- | --- |
| `cleanupPortableTools` | `false` | Deletes the portable Node/Git/pnpm after a successful install, saving ~200 MB. Breaks Discord's Updates tab. |
| `autoUpdateInjector` | `true` | Checks GitHub for a newer installer at the start of each run. |

Both are read on every run, so you can set them before zipping the folder.

### Repository layout

```
EquicordInjector/
├── INSTALL.bat        # what users double-click
├── install.ps1        # the installer itself
├── README.txt         # plain-language guide shipped inside the zip
├── cleanup.bat(.ps1)  # on-demand portable tools cleanup
└── config.json        # the two settings above
```

### Limitations

- The in-app **Update & Rebuild** needs the checkout, its `node_modules`, and
  the portable tools to stay in `%LOCALAPPDATA%\EquicordPluginInjector`. Tell
  users not to delete that folder.
- The updater patch modifies one line in `src/main/updater/git.ts`. If an
  upstream Equicord change ever touches that line, the in-app `git pull` stops
  with a conflict and the installer throws a clear "patch anchor no longer
  matches" error. Update the installer in that case. Re-running `INSTALL.bat`
  always resets and re-applies it.
- Re-running `INSTALL.bat` is the universal recovery: it fetches, resets, and
  rebuilds, which is how users recover after a Discord update, a failed in-app
  update, or any change to Equicord itself.
- The plugin repo is mirrored at the top of `install.ps1` as
  `$PluginRepoOwner` / `$PluginRepoName`. Point them anywhere to switch sources.