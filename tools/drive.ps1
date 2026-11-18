# Test driver for a second game copy (default C:\Games\Saints Row 3 Modded). Targets our instance by process id
# and talks to its window with posted messages, so it needs no focus and never types into other windows.
#   drive.ps1 -Launch                                start the game (pid saved to out\game.pid)
#   drive.ps1 -Keys esc,wait:800,down,enter -Shot x  post keys to our window, then capture it
#   drive.ps1 -Kill                                  close our instance
# Keys: esc enter up down left right space back, "vk:HH", "wait:ms".
param([string]$Game = 'C:\Games\Saints Row 3 Modded', [switch]$Launch, [switch]$Kill, [string[]]$Keys = @(), [string]$Shot = '', [double]$Scale = 0.5, [double]$Wait = 0)
$game = $Game
$root = Split-Path -Parent $PSScriptRoot
$pidFile = "$root\out\game.pid"
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Runtime.InteropServices; using System.Drawing;
public static class GW {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static void Key(IntPtr h, uint vk, bool ext) {
    uint sc = MapVirtualKey(vk, 0);
    uint l = 1u | (sc << 16) | (ext ? (1u << 24) : 0u);
    PostMessage(h, 0x100, (IntPtr)vk, (IntPtr)(int)l);
    System.Threading.Thread.Sleep(90);
    PostMessage(h, 0x101, (IntPtr)vk, (IntPtr)(int)(l | 0xC0000000u));
  }
  public static Bitmap Capture(IntPtr h) {
    RECT r; GetClientRect(h, out r);
    int w = Math.Max(1, r.R - r.L), ht = Math.Max(1, r.B - r.T);
    Bitmap b = new Bitmap(w, ht);
    using (Graphics g = Graphics.FromImage(b)) { IntPtr dc = g.GetHdc(); PrintWindow(h, dc, 3); g.ReleaseHdc(dc); }
    return b;
  }
}
"@
function Our-Process {
    if (-not (Test-Path $pidFile)) { return $null }
    $p = Get-Process -Id ([int](Get-Content $pidFile)) -ea 0
    if ($p -and $p.Path -like "$game\*") { return $p } else { return $null }
}
if ($Launch) {
    if (Our-Process) { 'already running'; exit 0 }
    Remove-Item "$game\SR3ModUI.log" -ea 0
    $p = Start-Process -FilePath "$game\SaintsRowTheThird_DX11.exe" -WorkingDirectory $game -PassThru
    New-Item -ItemType Directory -Force (Split-Path $pidFile) | Out-Null
    $p.Id | Set-Content $pidFile
    for ($i = 0; $i -lt 60 -and -not $p.MainWindowHandle; $i++) { Start-Sleep 1; $p.Refresh() }
    "pid $($p.Id) window $($p.MainWindowHandle)"
    exit 0
}
$p = Our-Process
if ($Kill) { if ($p) { Stop-Process -Id $p.Id -Force; 'killed' } else { 'not running' }; exit 0 }
if (-not $p) { 'OUR GAME IS NOT RUNNING'; exit 1 }
$h = $p.MainWindowHandle
if ($Wait -gt 0) { Start-Sleep -Milliseconds ([int]($Wait * 1000)) }
$vk = @{ esc = 0x1B; enter = 0x0D; up = 0x26; down = 0x28; left = 0x25; right = 0x27; space = 0x20; back = 0x08 }
$ext = @{ up = 1; down = 1; left = 1; right = 1 }
foreach ($k in @($Keys | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
    if ($k -like 'wait:*') { Start-Sleep -Milliseconds ([int]$k.Substring(5)); continue }
    if ($k -like 'vk:*') { [GW]::Key($h, [Convert]::ToUInt32($k.Substring(3), 16), $false) }
    elseif ($vk.ContainsKey($k)) { [GW]::Key($h, $vk[$k], $ext.ContainsKey($k)) }
    else { "unknown key $k"; continue }
    Start-Sleep -Milliseconds 300
}
if ($Shot) {
    Start-Sleep -Milliseconds 400
    $bmp = [GW]::Capture($h)
    $small = New-Object System.Drawing.Bitmap $bmp, ([int]($bmp.Width * $Scale)), ([int]($bmp.Height * $Scale))
    $out = "$root\test\shots\$Shot.png"
    New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
    $small.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $small.Dispose()
    $out
}
