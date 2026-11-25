# Builds the release zip: out\SR3-UI-API-Mod-v<version>.zip
#   powershell -ExecutionPolicy Bypass -File tools\package.ps1
# The zip root mirrors the game folder (SR3ModUI.asi, SR3ModUI\modui.lua), so installing by hand is "copy these two
# into the game folder"; install.bat does it with game detection and the ASI-loader check.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$cpp = Get-Content src\asi\modui.cpp -Raw
if ($cpp -notmatch '#define SR3MODUI_RELEASE "([0-9.]+)"') { throw 'SR3MODUI_RELEASE not found in src\asi\modui.cpp' }
$ver = $Matches[1]

& cmd /c "`"$root\build.bat`""
if ($LASTEXITCODE -ne 0) { throw 'build failed' }

$stage = "$root\out\release\SR3-UI-API-Mod-v$ver"
Remove-Item "$root\out\release" -Recurse -Force -ea 0
New-Item -ItemType Directory -Force "$stage\SR3ModUI", "$stage\examples", "$stage\include", "$stage\docs" | Out-Null
Copy-Item out\SR3ModUI.asi "$stage\SR3ModUI.asi"
Copy-Item src\lua\modui.lua "$stage\SR3ModUI\modui.lua"
Copy-Item install.bat, install.ps1, README.md, LICENSE $stage
Copy-Item examples\* "$stage\examples"
Copy-Item include\sr3modui.h "$stage\include"
Copy-Item docs\ENGINE.md "$stage\docs"
"SR3 UI API Mod $ver`r`nhttps://github.com/PurrsianMilkman/Saints-Row-The-Third-Mod-UI`r`n" | Set-Content "$stage\VERSION.txt" -Encoding ascii

# Nothing from the author's machine may ship: fail if a personal path leaked into a text file.
$leak = Get-ChildItem $stage -Recurse -File -Include *.lua,*.ps1,*.bat,*.md,*.txt,*.h,*.cpp |
        Select-String -Pattern 'C:\\Users\\|Purrsian\\' -SimpleMatch:$false | Where-Object { $_.Line -notmatch 'PurrsianMilkman' }
if ($leak) { $leak | ForEach-Object { "LEAK: $($_.Path):$($_.LineNumber): $($_.Line)" }; throw 'personal path in the release files' }

$zip = "$root\out\SR3-UI-API-Mod-v$ver.zip"
Remove-Item $zip -ea 0
# Compress-Archive in Windows PowerShell 5.1 can write backslash entry names; write the entries ourselves with '/'.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($f in Get-ChildItem $stage -Recurse -File) {
        $rel = $f.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, 'Optimal')
    }
} finally { $z.Dispose() }
$h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"built $zip  ($([math]::Round((Get-Item $zip).Length/1KB)) KB)"
"sha256 $h"
