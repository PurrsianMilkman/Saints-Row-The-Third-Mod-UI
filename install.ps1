# Installs (or with -Uninstall removes) the Saints Row The Third UI API Mod (SR3ModUI) into your game folder.
#
#   Easiest: double-click install.bat. It finds the game, asks before downloading anything, and installs.
#   Or:  powershell -ExecutionPolicy Bypass -File install.ps1 [-Game "C:\Games\Saints Row 3"] [-Examples] [-Uninstall]
#
# Needs the DX11 executable (SaintsRowTheThird_DX11.exe) and an ASI loader (dinput8.dll). If the loader is
# missing the installer offers to download Ultimate ASI Loader 9.7.2 (MIT) from its official GitHub release and
# checks the download against a pinned SHA-256 before using it. An existing dinput8.dll is never replaced.
# The game must be closed. Nothing in the game folder is overwritten except SR3ModUI's own files.
param(
    [string]$Game,
    [switch]$Examples,       # also install example_mod.lua (a demo page under Pause > MODS)
    [switch]$Uninstall,
    [switch]$Yes,            # do not ask before downloading the ASI loader
    [switch]$NoLoader        # never download the ASI loader
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exeName = 'SaintsRowTheThird_DX11.exe'

# Pinned third-party download (official release asset; hash taken from the GitHub release page).
$loaderUrl  = 'https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.2/Ultimate-ASI-Loader.zip'
$loaderHash = '0f34758b30eaa0efb59f7ae04100db789914e1a08891b89878b8fdb189c2a7c5'

function Stop-Install($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }
function Test-GameDir($d) { $d -and (Test-Path -LiteralPath (Join-Path $d $exeName)) }

function Find-GameDir {
    $cands = New-Object System.Collections.Generic.List[string]
    $cands.Add($here)                                    # the zip was extracted into the game folder
    $cands.Add((Split-Path -Parent $here))
    # Steam: main folder plus every library listed in libraryfolders.vdf
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ea 0).SteamPath
    $libs = @()
    if ($steam) {
        $libs += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
        }
    }
    foreach ($l in $libs) { foreach ($n in 'Saints Row the Third', 'Saints Row The Third') { $cands.Add((Join-Path $l "steamapps\common\$n")) } }
    # GOG: registry entries for the game
    foreach ($root in 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games') {
        foreach ($k in Get-ChildItem $root -ea 0) {
            $p = (Get-ItemProperty $k.PSPath -ea 0).path
            $name = (Get-ItemProperty $k.PSPath -ea 0).gameName
            if ($p -and $name -like '*Saints Row*Third*') { $cands.Add($p) }
        }
    }
    # common manual locations
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)) {
        foreach ($n in 'Games\Saints Row 3', 'Games\Saints Row The Third', 'Games\Saints Row the Third',
                       'GOG Games\Saints Row The Third', 'Program Files (x86)\GOG Galaxy\Games\Saints Row The Third') {
            $cands.Add((Join-Path $drive $n))
        }
    }
    $seen = @{}
    foreach ($c in $cands) {
        if (-not (Test-GameDir $c)) { continue }
        $full = [IO.Path]::GetFullPath($c).TrimEnd('\')
        if (-not $seen.ContainsKey($full.ToLower())) { $seen[$full.ToLower()] = $true; $full }   # Windows paths are case-insensitive
    }
}

function Select-GameDir {
    $found = @(Find-GameDir)
    if ($found.Count -eq 1) { Write-Host "Found the game: $($found[0])"; return $found[0] }
    if ($found.Count -gt 1) {
        Write-Host 'Several installs found:'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $found[$i]) }
        $n = Read-Host 'Which one? (number)'
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $found.Count) { return $found[[int]$n - 1] }
        Stop-Install 'No valid choice.'
    }
    Write-Host "Could not find a game folder containing $exeName automatically." -ForegroundColor Yellow
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Select your Saints Row The Third folder (the one that contains $exeName)"
        if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    } catch { }
    $p = Read-Host "Type the full path of the game folder"
    return $p.Trim('"')
}

if (-not $Game) { $Game = Select-GameDir }
$Game = $Game.TrimEnd('\')
if (-not (Test-GameDir $Game)) {
    Stop-Install "No $exeName in '$Game'.`nThis mod needs the DX11 executable. Pass the right folder with -Game, or see the README for requirements."
}
$running = Get-Process SaintsRowTheThird* -ea 0 | Where-Object { $_.Path -and $_.Path -like "$Game\*" }
if ($running) { Stop-Install 'The game is running from that folder - close it and run the installer again.' }

if ($Uninstall) {
    Remove-Item "$Game\SR3ModUI.asi", "$Game\SR3ModUI.log", "$Game\SR3ModUI\modui.lua" -ea 0
    Write-Host 'Removed SR3ModUI.asi and SR3ModUI\modui.lua.'
    Write-Host 'Kept SR3ModUI\mods\ (your mod scripts), SR3ModUI.ini (saved values) and dinput8.dll (the ASI loader, other mods may need it).'
    exit 0
}

# Where the files come from: a release zip (SR3ModUI.asi + SR3ModUI\modui.lua next to this script) or the repo (after build.bat).
$asi = @("$here\SR3ModUI.asi", "$here\out\SR3ModUI.asi") | Where-Object { Test-Path $_ } | Select-Object -First 1
$lua = @("$here\SR3ModUI\modui.lua", "$here\src\lua\modui.lua") | Where-Object { Test-Path $_ } | Select-Object -First 1
$ex  = @("$here\examples\example_mod.lua") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $asi) { Stop-Install 'SR3ModUI.asi not found next to the installer - download the release zip or run build.bat.' }
if (-not $lua) { Stop-Install 'modui.lua not found next to the installer.' }

New-Item -ItemType Directory -Force "$Game\SR3ModUI\mods" | Out-Null
$files = [ordered]@{ 'SR3ModUI.asi' = $asi; 'SR3ModUI\modui.lua' = $lua }
if ($Examples) {
    if ($ex) { $files['SR3ModUI\mods\example_mod.lua'] = $ex } else { Write-Host 'example_mod.lua not found - skipping -Examples' -ForegroundColor Yellow }
}
foreach ($k in $files.Keys) {
    Copy-Item $files[$k] "$Game\$k" -Force
    $ok = (Get-FileHash $files[$k]).Hash -eq (Get-FileHash "$Game\$k").Hash
    '{0,-34} {1}' -f $k, $(if ($ok) { 'OK' } else { 'HASH MISMATCH' })
    if (-not $ok) { Stop-Install "Copy of $k does not match its source - disk problem?" }
}

# ASI loader: it is what makes the game load SR3ModUI.asi at all.
if (-not (Test-Path "$Game\dinput8.dll")) {
    Write-Host ''
    Write-Host 'No dinput8.dll (ASI loader) in the game folder. Without one the game will not load SR3ModUI.asi.' -ForegroundColor Yellow
    $go = $false
    if (-not $NoLoader) {
        if ($Yes) { $go = $true }
        else {
            Write-Host "I can download Ultimate ASI Loader 9.7.2 (MIT licence, by ThirteenAG) from:"
            Write-Host "  $loaderUrl"
            Write-Host "and check it against a built-in SHA-256 before installing it as dinput8.dll."
            $a = Read-Host 'Download and install it? [Y/n]'
            $go = ($a -eq '' -or $a -match '^[Yy]')
        }
    }
    if ($go) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('sr3modui_loader_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $tmp | Out-Null
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $zip = Join-Path $tmp 'loader.zip'
            Invoke-WebRequest -Uri $loaderUrl -OutFile $zip -UseBasicParsing
            $h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
            if ($h -ne $loaderHash) { Stop-Install "Downloaded file has the wrong SHA-256 ($h). Not installing it." }
            Expand-Archive $zip -DestinationPath (Join-Path $tmp 'x') -Force
            $dll = Join-Path $tmp 'x\dinput8.dll'
            if (-not (Test-Path $dll)) { Stop-Install 'dinput8.dll not found inside the downloaded archive.' }
            Copy-Item $dll "$Game\dinput8.dll"
            Write-Host 'dinput8.dll                        OK (Ultimate ASI Loader 9.7.2)'
        } finally { Remove-Item $tmp -Recurse -Force -ea 0 }
    } else {
        Write-Host 'Skipped. Install an ASI loader yourself (a 32-bit dinput8.dll, e.g. Ultimate ASI Loader) before starting the game.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Installed. Start the game, pause, and pick MODS.   Log: SR3ModUI.log in the game folder.' -ForegroundColor Green
if (-not $Examples) { Write-Host 'Tip: run the installer with -Examples to add a demo page so you can see it working.' }
