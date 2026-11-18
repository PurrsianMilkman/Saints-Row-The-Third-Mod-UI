// Example ASI mod using SR3 Mod UI from C++. Build (VS x86 prompt):
//   cl /nologo /O2 /LD /I..\include example_asi.cpp /Fe:ExampleModUI.asi user32.lib kernel32.lib
// Put ExampleModUI.asi next to SaintsRowTheThird_DX11.exe (with SR3ModUI.asi and an ASI loader).
#include <windows.h>
#include <cstdio>
#include "sr3modui.h"

static void __cdecl onChange(const char* page, const char* key, double value, void*) {
    char msg[128];
    snprintf(msg, sizeof msg, "%s.%s = %g", page, key, value);
    ModUI.Log("example_asi", msg);
    if (!strcmp(key, "reset")) {                 // a button: set the others back (no callbacks fire)
        ModUI.SetValue("example_asi", "god", 0);
        ModUI.SetValue("example_asi", "speed", 1.0);
    }
}

// Lua can call this: ModUI.call("example_add", 2, 3) -> 5
static void __cdecl add(SR3ModUI_Call* c, void*) {
    ModUI.ReturnNumber(c, ModUI.ArgNumber(c, 1) + ModUI.ArgNumber(c, 2));
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        if (!SR3ModUI_Load()) return TRUE;       // SR3 Mod UI not installed: run without a menu
        ModUI.AddPage("example_asi", "Example ASI");
        ModUI.AddLabel("example_asi", "info", "Registered from C++");
        ModUI.AddToggle("example_asi", "god", "Invincible", 0, onChange, nullptr);
        ModUI.AddSlider("example_asi", "speed", "Speed", 0.5, 3.0, 0.25, 1.0, onChange, nullptr);
        ModUI.AddChoice("example_asi", "weather", "Weather", "Clear|Rain|Storm", 0, onChange, nullptr);
        ModUI.AddColor("example_asi", "hud", "HUD colour", 0xFF40A0, onChange, nullptr);
        ModUI.AddButton("example_asi", "reset", "Reset", onChange, nullptr);
        ModUI.RegisterHandler("example_add", add, nullptr);
        // any thread, any time: double speed = ModUI.GetValue("example_asi", "speed");
    }
    return TRUE;
}
