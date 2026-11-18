# Hold a key in OUR modded game window with posted messages (key down + auto-repeat, then key up).
#   hold.ps1 -Vk 0x41 -Ms 700
param([int]$Vk, [int]$Ms = 500, [string]$Game = 'C:\Games\Saints Row 3 Modded')
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class HK {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  public static void Hold(IntPtr h, uint vk, int ms) {
    uint l = 1u | (MapVirtualKey(vk, 0) << 16);
    PostMessage(h, 0x100, (IntPtr)vk, (IntPtr)(int)l);
    for (int t = 0; t < ms; t += 50) { System.Threading.Thread.Sleep(50); PostMessage(h, 0x100, (IntPtr)vk, (IntPtr)(int)(l | 0x40000000u)); }
    PostMessage(h, 0x101, (IntPtr)vk, (IntPtr)unchecked((int)(l | 0xC0000000u)));
  }
}
"@
$p = Get-Process -Id ([int](Get-Content "$(Split-Path -Parent $PSScriptRoot)\out\game.pid")) -ea 0
if (-not $p -or $p.Path -notlike "$Game\*") { 'OUR GAME IS NOT RUNNING'; exit 1 }
[HK]::Hold($p.MainWindowHandle, [uint32]$Vk, $Ms)
