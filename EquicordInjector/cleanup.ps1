param(
    # Skip every confirmation prompt (for CLEANUP.bat -Yes).
    [switch]$Yes
)

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

function Step([string]$msg) {
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
}
function Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}
function Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
}

# Asks a yes/no question. Only an explicit yes returns $true, so a stray Enter
# (or a closed window) never deletes anything.
function Confirm([string]$msg, [bool]$default = $true) {
    if ($Yes) { return $default }
    $hint = if ($default) { "[Y/n]" } else { "[y/N]" }
    $ans = Read-Host "  $msg $hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
    $a = $ans.Trim().ToLower()
    return ($a -eq "y" -or $a -eq "yes")
}

# Size of a folder in whole MB (rounded).
function Get-SizeMB($dir) {
    if (-not (Test-Path $dir)) { return 0 }
    try {
        $bytes = (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        if ($bytes) { return [math]::Round($bytes / 1MB) }
    }
    catch { }
    return 0
}

# ---------- Where things live ----------
# Must stay in sync with install.ps1. Everything the installer downloads is
# kept under one "tools" folder, so this is all we ever delete.
$WorkRoot = Join-Path $env:LOCALAPPDATA "EquicordPluginInjector"
$ToolsDir = Join-Path $WorkRoot "tools"
$RepoDir  = Join-Path $WorkRoot "equicord"

$host.UI.RawUI.WindowTitle = "Equicord Plugin Injector - Remove portable tools"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   Equicord Plugin Injector - CLEANUP" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

try {

    # ---------- 1. What is there ----------
    Step "1/3  Looking at what is installed"

    if (-not (Test-Path $ToolsDir)) {
        Write-Host ""
        Write-Host "Nothing to clean up - the portable tools are already gone." -ForegroundColor Green
        Write-Host "Equicord and your plugins are untouched." -ForegroundColor Green
        Write-Host ""
        Write-Host "(If you ever want to remove Equicord from Discord itself," -ForegroundColor DarkGray
        Write-Host " use Settings > Plugins, or Discord's own installer.)" -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    $sizeMb = Get-SizeMB $ToolsDir
    Ok("Found the portable tools in $ToolsDir (about $sizeMb MB)")

    # Name what is actually in there, so the message is not a mystery.
    $found = @()
    if (Test-Path (Join-Path $ToolsDir "node_modules")) { $found += "pnpm" }
    Get-ChildItem -LiteralPath $ToolsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -like "node-v*-win-*") { $found += "Node.js" }
        elseif ($_.Name -like "MinGit-*")   { $found += "Git" }
    }
    if ($found.Count -gt 0) {
        Ok("It contains: $(($found | Select-Object -Unique) -join ', ')")
    }

    if (Test-Path $RepoDir) {
        Ok("Leaving your Equicord install and plugins alone (in $RepoDir)")
    }

    Write-Host ""
    Write-Host "This will:" -ForegroundColor White
    Write-Host "  1. Delete the portable Node.js, Git and pnpm copies (~$sizeMb MB)."
    Write-Host "  2. NOT touch Discord, Equicord, or your plugins - they keep"
    Write-Host "     working exactly as they do now. You do not need to close Discord."
    Write-Host ""
    Write-Host "The one trade-off:" -ForegroundColor Yellow
    Write-Host "  Discord's Settings > Updates tab calls that portable Git & Node," -ForegroundColor Yellow
    Write-Host "  so it will stop working. To update Equicord or your plugins again," -ForegroundColor Yellow
    Write-Host "  just re-run INSTALL.bat - it re-downloads what it needs." -ForegroundColor Yellow
    Write-Host ""
    if (-not (Confirm("Delete the portable tools?", $true))) {
        Write-Host ""
        Ok("Cancelled. Nothing was changed.")
        Read-Host "Press Enter to close"
        exit 0
    }

    # ---------- 2. Make sure nothing is using them ----------
    Step "2/3  Checking nothing is using them"

    # Discord can leave a node.exe running from this folder (e.g. mid-update).
    # Those files would be locked and the delete would fail halfway through.
    $busy = @()
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $p = $_
        try {
            if ($p.Path -and $p.Path.StartsWith($ToolsDir, [StringComparison]::OrdinalIgnoreCase)) {
                $busy += $p
            }
        }
        catch { }
    }

    if ($busy.Count -gt 0) {
        Warn("$($busy.Count) process(es) from the tools folder are still running:")
        foreach ($p in $busy) { Write-Host "        $($p.ProcessName) (pid $($p.Id))" -ForegroundColor Yellow }
        if (Confirm("Close them now?", $true)) {
            foreach ($p in $busy) {
                try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
            }
            Start-Sleep -Seconds 2
            Ok("Closed")
        } else {
            Warn("Continuing - if a file is locked, close Discord and try again.")
        }
    } else {
        Ok("Nothing is using them")
    }

    # ---------- 3. Delete ----------
    Step "3/3  Removing the portable tools"
    try {
        Remove-Item -LiteralPath $ToolsDir -Recurse -Force
    }
    catch {
        throw ("Could not delete the tools folder - a file is probably still in use. " +
               "Close Discord (and anything else running Equicord) and try again.`n" +
               "  Details: " + $_.Exception.Message)
    }

    if (Test-Path $ToolsDir) {
        throw "Could not fully delete '$ToolsDir'. Close Discord and any running Equicord, then try again."
    }
    Ok("Removed the portable tools - about $sizeMb MB freed")

    # ---------- Done ----------
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  Done!" -ForegroundColor Green
    Write-Host "  Equicord and your plugins are still installed and working." -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To update again:" -ForegroundColor Cyan
    Write-Host "  - Run INSTALL.bat in this folder. It re-downloads Node, Git and" -ForegroundColor DarkGray
    Write-Host "    pnpm automatically (only the first time you do this)." -ForegroundColor DarkGray
    Write-Host "  - The Settings > Updates tab inside Discord will not work" -ForegroundColor DarkGray
    Write-Host "    until you have done that once." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 0

}
catch {
    Write-Host ""
    Write-Host "Something went wrong:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Equicord and your plugins were not changed." -ForegroundColor Yellow
    Write-Host "  - Close Discord completely (right-click the tray icon > Quit)"
    Write-Host "    and any other app that might be running Equicord."
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}
