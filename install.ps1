# Installs (or with -Uninstall removes) SR3 Mod UI into a Saints Row: The Third folder.
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Game "C:\Games\Saints Row 3" [-Examples]
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Game "C:\Games\Saints Row 3" -Uninstall
# Needs an ASI loader (dinput8.dll, e.g. Ultimate ASI Loader) and the DX11 executable. The game must be closed.
param([string]$Game = 'C:\Games\Saints Row 3', [switch]$Examples, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path "$Game\SaintsRowTheThird_DX11.exe")) { "No SaintsRowTheThird_DX11.exe in '$Game' - pass -Game <folder>"; exit 1 }
$running = Get-Process SaintsRowTheThird* -ea 0 | Where-Object { $_.Path -like "$Game\*" }
if ($running) { 'The game is running from that folder - close it first.'; exit 1 }

if ($Uninstall) {
    Remove-Item "$Game\SR3ModUI.asi", "$Game\SR3ModUI.log", "$Game\SR3ModUI\modui.lua" -ea 0
    'removed SR3ModUI.asi and SR3ModUI\modui.lua; kept SR3ModUI\mods\ (your mod scripts) and SR3ModUI.ini (saved values)'
    exit 0
}

$asi = @("$here\out\SR3ModUI.asi", "$here\SR3ModUI.asi") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $asi) { 'SR3ModUI.asi not found - run build.bat or use the release zip'; exit 1 }
New-Item -ItemType Directory -Force "$Game\SR3ModUI\mods" | Out-Null
$files = [ordered]@{ 'SR3ModUI.asi' = $asi; 'SR3ModUI\modui.lua' = "$here\src\lua\modui.lua" }
if ($Examples) { $files['SR3ModUI\mods\example_mod.lua'] = "$here\examples\example_mod.lua" }
foreach ($k in $files.Keys) {
    Copy-Item $files[$k] "$Game\$k" -Force
    $ok = (Get-FileHash $files[$k]).Hash -eq (Get-FileHash "$Game\$k").Hash
    '{0,-34} {1}' -f $k, $(if ($ok) { 'OK' } else { 'HASH MISMATCH' })
}
if (-not (Test-Path "$Game\dinput8.dll")) { 'NOTE: no dinput8.dll in the game folder - install an ASI loader or the plugin will not load' }
'Installed. In game: Pause > MODS. Log: SR3ModUI.log'
