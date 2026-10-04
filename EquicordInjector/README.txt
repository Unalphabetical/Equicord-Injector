=================================
  Equicord Plugin Injector
=================================

This installs your custom Equicord plugins (currently: gifBlacklist)
into Discord for you.
You do NOT need to install Git, Node, or anything else.
(It quietly brings its own portable copies.)

LOOK AT ME FIRST
----------------
1) Make sure Discord is installed on this computer.
   (The normal Discord app - download it from discord.com if you don't have it.)

2) MAKE SURE DISCORD IS CLOSED (not minimized - fully closed,
   by right-clicking the Discord icon in the taskbar tray and choosing Quit).

HOW TO INSTALL
--------------
1) Right-click "INSTALL.bat" and choose "Run".
   (If Windows shows a blue "Windows protected your PC" box, click
   "More info" then "Run anyway" - it's safe, it's just unsigned.)

2) A black window opens. Just follow the on-screen messages and
   press Enter when asked.

3) Wait. It downloads the newest Discord plugins + Equicord, builds,
   and patches for a few minutes. Leave it alone until it says "All done!"

4) When it finishes, open Discord normally.

5) Go to Settings (gear icon, bottom-left) > Plugins, find the plugin
   (e.g. "gifBlacklist") and turn it ON.

KEEPING IT UPDATED
------------------
Every time you run INSTALL.bat the installer quickly checks GitHub and, if a
newer version of itself exists, downloads it and re-runs automatically. So the
tool is always current without you downloading a new copy.
(For technical users: this can be turned off by setting "autoUpdateInjector":
false in config.json.)

You have two easy ways to update Discord/plugins:

1) IN DISCORD: Settings (gear icon) > Updates. Click "Check for Updates"
   and, if there's something new, "Update & Rebuild". Wait for it to
   finish, then fully quit and reopen Discord.

2) OR: close Discord and double-click INSTALL.bat again. It grabs the
   newest plugins + Equicord and rebuilds everything.

IMPORTANT: the installer keeps everything it needs in
%LOCALAPPDATA%\EquicordPluginInjector (the Equicord checkout, the plugins,
and its portable tools). Do NOT delete that folder, or the Updates tab
and future installs will break. (CLEANUP.bat below removes just the
portable tools if you want the space back.)

HOW TO FREE UP SPACE (REMOVE THE PORTABLE TOOLS)
------------------------------------------------
The installer carries its own copies of Node.js, Git and pnpm, kept in
%LOCALAPPDATA%\EquicordPluginInjector\tools - roughly 200 MB in total.

1) Right-click "CLEANUP.bat" and choose "Run".

2) It asks you to confirm, then deletes just those portable copies.

3) That is all. Discord does NOT need to be closed, and Equicord and your
   plugins stay installed and keep working exactly as before.

THE ONE TRADE-OFF
------------------
Discord's Settings > Updates tab calls that portable Git & Node, so it
stops working once they are gone. When you want to update again, just
re-run INSTALL.bat - it re-downloads them automatically (only the first
time you do this).

(To remove Equicord from Discord altogether, reinstall Discord from
discord.com - that restores its original files.)

(If whoever gave you this enabled "cleanup" in config.json, the portable
tools are deleted after install to save space - then you update by re-running
INSTALL.bat.)

PLEASE DO NOT
-------------
- Do not delete %LOCALAPPDATA%\EquicordPluginInjector.
- Do not run INSTALL.bat while Discord is open.

TROUBLESHOOTING
---------------
- "Something went wrong": read the red message. Usually it means Discord
  wasn't fully closed, or your internet was down. Try again.
- Antivirus warning: this installer downloads and runs files, so some
  antivirus programs get nervous. If it blocks it, allow it once.
- Plugin doesn't show up: make sure it's toggled ON in Settings > Plugins.