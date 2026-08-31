$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

function Step([string]$msg) {
    Write-Host ""
    Write-Host "=================================="
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "=================================="
}
function Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}
function Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}

# Self-update: replaces this installer (plus INSTALL.bat / README.txt / config.json)
# with the latest versions straight from the GitHub repo, then the script re-runs
# itself. Users therefore never need to re-download or re-share the zip to get
# installer fixes. Purely additive - if GitHub is unreachable it just carries on
# with the copy they already have.
# Returns $true if install.ps1 itself was updated (caller should re-run the new
# script), otherwise $false (INSTALL.bat / README / config may still have been
# refreshed in place).
function Update-InjectorFiles {
    $owner = "Unalphabetical"
    $name  = "Equicord-Injector"
    # Files, relative to the 'EquicordInjector' folder in the repo, that get
    # autorefreshed. config.json is included too, but your local copy is first
    # backed up to config.json.pre-update so no per-machine setting is lost.
    $files = @("install.ps1", "INSTALL.bat", "README.txt", "config.json")
    $relaunch = $false
    try {
        $info = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$name" -Headers @{ "User-Agent" = "Equicord-Plugin-Injector" }
        $branch = $info.default_branch
    }
    catch {
        Warn("Could not check for an installer update (GitHub unreachable?). Using the version you already have.")
        return $relaunch
    }

    $tmpRoot = Join-Path $env:TEMP "EquicordInjector_update"
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $updated = @()
    try {
        foreach ($f in $files) {
            $rawPath = "EquicordInjector/$f"
            $local   = Join-Path $PSScriptRoot $f
            $tmp     = Join-Path $tmpRoot $f
            $url     = "https://raw.githubusercontent.com/$owner/$name/$branch/$rawPath"
            try {
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
            }
            catch {
                Warn("Could not download the latest '$f' - keeping your current copy.")
                continue
            }
            if (Test-Path $local) {
                $same = (Get-FileHash -Path $local -Algorithm SHA256).Hash -eq (Get-FileHash -Path $tmp -Algorithm SHA256).Hash
                if ($same) { continue }
            }
            if ($f -eq "config.json" -and (Test-Path $local)) {
                Copy-Item -LiteralPath $local -Destination "$local.pre-update" -Force
                Ok("Backed up your old config to 'config.json.pre-update'")
            }
            Copy-Item -LiteralPath $tmp -Destination $local -Force
            $updated += $f
            if ($f -eq "install.ps1") { $relaunch = $true }
        }
    }
    finally {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($updated.Count -gt 0) {
        Ok("Updated installer files: $($updated -join ', ').")
    }
    return $relaunch
}

$host.UI.RawUI.WindowTitle = "Equicord Plugin Injector"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "        Equicord Plugin Injector" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

try {

    # ---------- USER CONFIGURATION ----------
    # Settings are read from config.json (in the same folder as this script),
    # so you can change them without editing the script. See that file.
    #   "cleanupPortableTools": true/false
    #     When true, the downloaded portable tools (Node, Git and pnpm) are
    #     deleted from %LOCALAPPDATA%\EquicordPluginInjector after a successful
    #     install. This frees ~200 MB of disk space but ALSO breaks Equicord's
    #     in-app "Updates" tab (Settings > Updates), because that tab calls the
    #     portable git and node stored here; users must re-run INSTALL.bat to
    #     update instead. Defaults to false so the Updates tab keeps working.
    $ConfigFile = Join-Path $PSScriptRoot "config.json"
    $CleanupPortableTools = $false
    $AutoUpdateInjector    = $true
    if (Test-Path $ConfigFile) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
            $val = $cfg.cleanupPortableTools
            if ($null -ne $val) { $CleanupPortableTools = ($val -eq $true) }
            $val = $cfg.autoUpdateInjector
            if ($null -ne $val) { $AutoUpdateInjector = ($val -eq $true) }
        }
        catch {
            Warn("config.json could not be read (invalid JSON?). Using default settings.")
        }
    }

    # ---------- Locations, versions, sources ----------
    $PluginRepoOwner   = "Unalphabetical"
    $PluginRepoName    = "Equicord-Plugin"
    $PluginRepoUrl     = "https://github.com/$PluginRepoOwner/$PluginRepoName.git"
    $PluginRepoZipUrl  = "https://codeload.github.com/$PluginRepoOwner/$PluginRepoName/zip/refs/heads/{0}"
    $PluginRepoApiUrl  = "https://api.github.com/repos/$PluginRepoOwner/$PluginRepoName"

    $EquicordUrl  = "https://github.com/Equicord/Equicord.git"

    $WorkRoot     = Join-Path $env:LOCALAPPDATA "EquicordPluginInjector"
    $ToolsDir     = Join-Path $WorkRoot "tools"
    $ZipDir       = Join-Path $WorkRoot "ziptmp"
    $RepoDir      = Join-Path $WorkRoot "equicord"

    # Keep >= v22.13: Equicord's pinned pnpm 11.22.0 requires Node >= 22.13.
    $NodeVersion  = "22.14.0"
    $NodeFolder   = "node-v$NodeVersion-win-x64"
    $NodeExe      = Join-Path $ToolsDir "$NodeFolder\node.exe"
    $nodeBinDir   = Split-Path -Parent $NodeExe
    $NodeZipPath  = Join-Path $ZipDir "node.zip"
    $NodeUrl      = "https://nodejs.org/dist/v$NodeVersion/$NodeFolder.zip"

    # MinGit - the official portable build of Git, no installer.
    $GitVersion  = "2.54.0"
    $GitFolder   = "MinGit-$GitVersion-64-bit"
    $GitCmdDir   = Join-Path $ToolsDir "$GitFolder\cmd"
    $GitExe      = Join-Path $GitCmdDir "git.exe"
    $GitZipPath  = Join-Path $ZipDir "mingit.zip"
    $GitUrl      = "https://github.com/git-for-windows/git/releases/download/v$GitVersion.windows.1/MinGit-$GitVersion-64-bit.zip"

    $PnpmVersion  = "11.22.0"
    $PnpmCjs      = Join-Path $ToolsDir "node_modules\pnpm\bin\pnpm.cjs"
    $NpmCli       = Join-Path $ToolsDir "$NodeFolder\node_modules\npm\bin\npm-cli.js"

    New-Item -ItemType Directory -Force -Path $WorkRoot, $ToolsDir, $ZipDir | Out-Null

    # ---------- 0. Self-update the installer itself ----------
    # Pulls the newest installer from GitHub and, if install.ps1 changed,
    # re-runs the fresh copy in this same window. Safe to disable with
    # "autoUpdateInjector": false in config.json (e.g. while developing).
    if ($AutoUpdateInjector -and (Update-InjectorFiles)) {
        Ok("The installer updated to the latest version - running it now...")
        & (Join-Path $PSScriptRoot "install.ps1")
        exit 0
    }

    # ---------- 1. Checks ----------
    Step "1/10  Checking things first"

    $discordDirs = Get-ChildItem $env:LOCALAPPDATA -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Discord*" }

    if (-not $discordDirs) {
        Warn("No Discord app was detected. Proceeding anyway - the patcher will report a clear error, but you'll likely need Discord installed first.")
    } else {
        Ok("Discord app detected")
    }

    Write-Host ""
    Write-Host "IMPORTANT: You need to close Discord completely before we patch it." -ForegroundColor Yellow
    $resp = Read-Host "When Discord is fully closed, press Enter"
    Write-Host ""

    # ---------- 2. Portable Node ----------
    Step "2/10  Getting a self-contained copy of Node.js"
    if (-not (Test-Path $NodeExe)) {
        Write-Host "  Downloading Node.js v$NodeVersion (first run only, ~30 MB)..."
        Invoke-WebRequest -Uri $NodeUrl -OutFile $NodeZipPath
        Expand-Archive -Path $NodeZipPath -DestinationPath $ToolsDir -Force
        Remove-Item -LiteralPath $NodeZipPath -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $NodeExe)) { throw "Could not set up Node.js. Check your internet connection and try again." }
    }
    Ok("Node.js ready (kept for future runs)")

    # ---------- 3. Portable Git ----------
    Step "3/10  Getting a self-contained copy of Git"
    if (-not (Test-Path $GitExe)) {
        Write-Host "  Downloading Git $GitVersion (first run only, ~40 MB)..."
        Invoke-WebRequest -Uri $GitUrl -OutFile $GitZipPath
        $gitTmp = Join-Path $ZipDir "mingit-extract"
        if (Test-Path $gitTmp) { Remove-Item $gitTmp -Recurse -Force }
        Expand-Archive -Path $GitZipPath -DestinationPath $gitTmp -Force
        Remove-Item -LiteralPath $GitZipPath -Force -ErrorAction SilentlyContinue
        # MinGit zips contain a top-level folder; find cmd\git.exe wherever it landed
        $gitExeFound = Get-ChildItem -Path $gitTmp -Recurse -Filter "git.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName.EndsWith("\cmd") } | Select-Object -First 1
        if (-not $gitExeFound) { throw "Could not set up Git. Check your internet connection and try again." }
        $dest = Join-Path $ToolsDir $GitFolder
        if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        Move-Item -LiteralPath $gitExeFound.Directory.Parent.FullName -Destination $dest
        Remove-Item -LiteralPath $gitTmp -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $GitExe)) { throw "Could not set up Git. Check your internet connection and try again." }
    }
    Ok("Git ready (kept for future runs)")

    # ---------- 4. pnpm ----------
    Step "4/10  Preparing the package manager (pnpm)"
    if (-not (Test-Path $PnpmCjs)) {
        Write-Host "  Installing pnpm $PnpmVersion into the local tools folder..."
        & $NodeExe $NpmCli install -g --prefix $ToolsDir "pnpm@$PnpmVersion" | Out-Null
        if (-not (Test-Path $PnpmCjs)) { throw "Could not install pnpm. Check your internet connection and try again." }
    }
    Ok("pnpm ready")

    # ---------- 5. Latest Equicord (real git clone) ----------
    Step "5/10  Getting the latest Equicord"
    # Remove leftovers from old zip-based installs of this tool
    $oldExtract = Join-Path $WorkRoot "extract"
    if (Test-Path (Join-Path $oldExtract "Equicord-main")) {
        Write-Host "  Removing leftover files from an older install..."
        Remove-Item (Join-Path $oldExtract "Equicord-main") -Recurse -Force
    }

    if (Test-Path (Join-Path $RepoDir ".git")) {
        Write-Host "  Updating your existing Equicord checkout..."
        Push-Location $RepoDir
        try {
            & $GitExe fetch --depth 1 origin main
            if ($LASTEXITCODE -ne 0) { throw "Could not fetch the latest Equicord. Check your internet connection and try again." }
            & $GitExe reset --hard origin/main
            if ($LASTEXITCODE -ne 0) { throw "Could not update the Equicord checkout." }
        }
        finally {
            Pop-Location
        }
    } else {
        if (Test-Path $RepoDir) { Remove-Item $RepoDir -Recurse -Force }
        Write-Host "  Cloning the latest Equicord (a few seconds)..."
        & $GitExe clone --depth 1 --branch main $EquicordUrl $RepoDir
        if ($LASTEXITCODE -ne 0) { throw "Could not clone Equicord. Check your internet connection and try again." }
    }
    if (-not (Test-Path (Join-Path $RepoDir ".git"))) { throw "The Equicord checkout has no .git folder - something went wrong." }
    Ok("Latest Equicord ready")

    # ---------- 6. Pull your plugins from GitHub and drop them in ----------
    Step "6/10  Pulling the plugins from GitHub"
    try {
        $info = Invoke-RestMethod -Uri $PluginRepoApiUrl -Headers @{ "User-Agent" = "Equicord-Plugin-Injector" }
        $branch = $info.default_branch
    }
    catch {
        $branch = "master"
    }
    Write-Host "  Downloading plugins from $PluginRepoOwner/$PluginRepoName ($branch)..."
    $pluginZip  = Join-Path $ZipDir "plugins.zip"
    $pluginTmp  = Join-Path $ZipDir "plugins-extract"
    if (Test-Path $pluginZip) { Remove-Item $pluginZip -Force }
    if (Test-Path $pluginTmp) { Remove-Item $pluginTmp -Recurse -Force }
    Invoke-WebRequest -Uri ([string]::Format($PluginRepoZipUrl, $branch)) -OutFile $pluginZip
    Expand-Archive -Path $pluginZip -DestinationPath $pluginTmp -Force
    # codeload zips wrap in a single top-level folder; find it
    $repoRoot = Get-ChildItem -Path $pluginTmp -Directory | Select-Object -First 1
    if (-not $repoRoot) { throw "Could not read the plugin repository after downloading it." }

    $userPlugins = Join-Path $RepoDir "src\userplugins"
    New-Item -ItemType Directory -Force -Path $userPlugins | Out-Null

    $installed = @()
    $pluginFolders = Get-ChildItem -Path $repoRoot.FullName -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "index.tsx") }

    if (-not $pluginFolders) { throw "No plugin (a folder with index.tsx) was found in the GitHub repo." }

    foreach ($folder in $pluginFolders) {
        $dest = Join-Path $userPlugins $folder.Name
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Copy-Item -Recurse -Force -Path $folder.FullName -Destination $dest
        $installed += $folder.Name
    }
    Remove-Item -LiteralPath $pluginZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pluginTmp -Recurse -Force -ErrorAction SilentlyContinue
    Ok("Plugins added to Equicord: $($installed -join ', ')")

    # ---------- 7. Wire Equicord's in-app updater to the portable tools ----------
    Step "7/10  Wiring the in-app updater to the portable tools"
    $updaterFile = Join-Path $RepoDir "src\main\updater\git.ts"
    $anchor = 'const VENCORD_SRC_DIR = join(__dirname, "..");'
    if (-not (Test-Path $updaterFile)) {
        throw "Equicord's source layout changed - cannot find src/main/updater/git.ts. Update the installer."
    }
    $content = [IO.File]::ReadAllText($updaterFile)
    if ($content -notmatch "EquicordPluginInjector") {
        if (-not $content.Contains($anchor)) {
            throw "Equicord's updater changed - the installer's patch anchor no longer matches. Update the installer."
        }
        $gitCmdDirJs  = ConvertTo-Json -Compress $GitCmdDir
        $nodeDirJs    = ConvertTo-Json -Compress $nodeBinDir
        $pathLine = "process.env.PATH = $gitCmdDirJs + ';' + $nodeDirJs + ';' + (process.env.PATH ?? ''); // EquicordPluginInjector"
        $content = $content.Replace($anchor, "$pathLine`n$anchor")
        [IO.File]::WriteAllText($updaterFile, $content)
    }
    Ok("Updater wired to the portable Git & Node")

    # ---------- 8. Install deps + build ----------
    $origPath = $env:PATH
    $env:PATH = "$GitCmdDir;$nodeBinDir;$origPath"

    Push-Location $RepoDir
    try {
        Step "8/10  Installing dependencies (first time can take a few minutes)"
        & $NodeExe $PnpmCjs install --frozen-lockfile
        if ($LASTEXITCODE -ne 0) { throw "Installing dependencies failed. Check your internet connection and try again." }
        Ok("Dependencies installed")

        Step "9/10  Building Equicord with your plugins (a minute or two)"
        & $NodeExe $PnpmCjs build
        if ($LASTEXITCODE -ne 0) { throw "Building failed. The build log above shows the reason (often a plugin error)." }
        Ok("Build complete!")

        Step "10/10  Patching your Discord"
        Write-Host "  Running Equicord's official patcher (downloads a small tool)..."
        & $NodeExe (Join-Path $RepoDir "scripts\runInstaller.mjs") -- --install
        if ($LASTEXITCODE -ne 0) { throw "Patching Discord failed. Make sure Discord is fully closed, then re-run INSTALL.bat." }
        Ok("Discord patched!")
    }
    finally {
        Pop-Location
        if ($null -ne $origPath) { $env:PATH = $origPath }
    }

    # ---------- 11. Optional cleanup of the portable tools ----------
    if ($CleanupPortableTools) {
        Step "Cleaning up the portable tools (only if you opted in)"
        if (Test-Path $ToolsDir) {
            Remove-Item -LiteralPath $ToolsDir -Recurse -Force
            Ok("Removed the portable tools (Node, Git, pnpm) - ~200 MB freed")
            Warn("The in-app Updates tab will no longer work. Re-run INSTALL.bat to update instead.")
        } else {
            Ok("Portable tools already removed")
        }
    }

    # ---------- Done ----------
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  All done!" -ForegroundColor Green
    Write-Host "  Open Discord and go to Settings > Plugins." -ForegroundColor Green
    Write-Host "  Turn on your plugins and enjoy! ($($installed -join ', '))" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Updates:" -ForegroundColor Cyan
    Write-Host "  - In Discord: Settings > Updates > Update & Rebuild (then restart Discord)."
    Write-Host "  - Or just re-run INSTALL.bat anytime."
    Write-Host "  Keep the '%LOCALAPPDATA%\EquicordPluginInjector' folder - it holds the"
    Write-Host "  Equicord checkout and tools that the Updates tab needs." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 0

}
catch {
    Write-Host ""
    Write-Host "Something went wrong:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Tips:" -ForegroundColor Yellow
    Write-Host "  - Close Discord completely and try again."
    Write-Host "  - Check your internet connection."
    Write-Host "  - Make sure the whole 'EquicordPluginInjector' folder is intact."
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}