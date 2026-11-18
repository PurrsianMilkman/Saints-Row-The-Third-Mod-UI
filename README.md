# SR3 Mod UI

A UI API for **Saints Row: The Third (PC, DX11)** mods. Mods describe their settings, and SR3 Mod UI
draws them as **native game menus** under **Pause > MODS**, with the game's own toggles, sliders and
option lists, plus an HSL colour picker with colour bars. Mods can be **Lua scripts** dropped in a folder
or **ASI plugins** in C/C++. No game file is modified.

```
PAUSED                        EXAMPLE MOD
  Save Game                     Enabled          < YES >
  Load Game                     Amount     ======|----  2.5
  Options                       Mode             < Calm >
  Co-op                         Tint             [#3080FF]  -> opens Hue / Saturation / Luminance
  MODS          <- new          Say hello
  Exit to Main Menu
```

Values are saved to `SR3ModUI.ini` and restored on the next launch. Navigation uses the same inputs as
the game's own option screens (tested with the keyboard; the mouse and controller handlers follow the
stock screens but are not tested yet).

## Install

Requirements: `SaintsRowTheThird_DX11.exe` and an ASI loader (`dinput8.dll`, e.g. Ultimate ASI Loader).

```
powershell -ExecutionPolicy Bypass -File install.ps1 -Game "C:\Games\Saints Row 3" [-Examples]
```

This copies `SR3ModUI.asi` and `SR3ModUI\modui.lua` into the game folder and creates `SR3ModUI\mods\`.
`-Examples` also installs the example script. Build the plugin yourself with `build.bat` (Visual Studio
2022 Build Tools, x86). Log: `SR3ModUI.log` in the game folder.

## Lua mods

Put a `.lua` file in `<game>\SR3ModUI\mods\`. It runs once in the game's UI script state at start-up.
(Files named `*.game.lua` run in the gameplay script state instead, where only `ModUI.wrap`, `on_load`,
`log` and `call` exist.)

```lua
local page = ModUI.page("mymod", "My Mod")          -- id ([A-Za-z0-9_]) and title

page:label("about", "Some text")
page:toggle("enabled", "Enabled", true, function(on) end)
page:slider("amount", "Amount", 0, 5, 0.5, 2.5, function(v) end)          -- min, max, step, default
page:choice("mode", "Mode", { "Calm", "Busy", "Chaos" }, 1, function(i, name) end)
page:color("tint", "Tint", 0x3080FF, function(rgb, r, g, b) end)          -- r, g, b are 0..1
page:button("hello", "Say hello", function() end)

page:get("amount")                -- current value (toggle: boolean, choice: index, colour: 0xRRGGBB)
page:set("amount", 3)             -- change + save, no callback
page:set_label("about", "Hello!")
page:enable("mode", false)        -- greyed out, skipped by the cursor
page:on_open(function(p) end)     -- each time the player opens the page
```

Colour rows open an editor with Hue / Saturation / Luminance sliders and a Result swatch. By default the
callback runs on every slider move (live preview) and again with the old colour if the player backs out;
pass `{ live = false }` as the last argument of `page:color` to get a call only when the colour is kept.

### Hooking the game's own UI

```lua
-- run your code around any global function of a game script; survives the script reloading
ModUI.wrap("store_clothing_item_details", function(orig, menu_data)
    local result = orig(menu_data)            -- call the game's function (or don't)
    -- change Store_common_sub_menu here ...
    return result
end)

ModUI.on_load("store_clothing", function(script_name) end)   -- after a script loads
```

A hook that raises an error is logged and the game's function runs anyway.

### The colour editor in your own menus

`ModUI.HslEditor` works in any game list built from slider/colour rows (pause screens, store menus):

```lua
local ed = ModUI.HslEditor.new{ r = 1, g = 0.2, b = 0.5, on_change = function(r, g, b) end }
local rows = ed:make_rows("Result (select to keep)")   -- 4 rows: Hue, Saturation, Luminance, Result
-- put rows[1..4] at positions 1..4 of your menu, draw it, then:
ed:attach(list, 1)        -- builds the colour bars on the drawn list
ed:changed()              -- call after a slider row's current_value changed
ed:get()                  -- r, g, b
```

### Helpers

`ModUI.log(...)`, `ModUI.pcall(f, ...)` (the UI state has no `pcall`), `ModUI.fmt(x, decimals)`,
`ModUI.rgb_pack(r, g, b)` / `ModUI.rgb_unpack(n)`, `ModUI.hsl_to_rgb(h, s, l)` / `ModUI.rgb_to_hsl`,
`ModUI.call(name, ...)` (a C handler, see below), `ModUI.global(name, value)` / `ModUI.get_global(name)`.

### Things to know about the game's UI Lua

- It is Lua 5.1 **without** the `string`, `math`, `table` and `os` libraries, `pcall` or `tonumber`. Use
  the globals `floor`, `min`, `max`, `abs`, the `^` and `%` operators, `type`, `pairs`.
- After start-up, assigning a **new** global raises "attempted to write to undefined global". Define
  globals at the top level of your script (that runs at start-up), or use `ModUI.global(name, value)`.
  Reading an undefined global also raises; use `ModUI.get_global(name)` when unsure.
- Functions the game calls **by name** (input callbacks, `pcu_report_*` callbacks) must be globals.
- Page titles are shown in capitals (the header font has no lower case). Keep row labels short
  (about 30 characters): the panel clips longer ones.

## ASI (C/C++) mods

Include [`include/sr3modui.h`](include/sr3modui.h) (header only, nothing to link):

```c
#include "sr3modui.h"

static void __cdecl on_change(const char* page, const char* key, double value, void* user) { /* ... */ }

// DllMain, DLL_PROCESS_ATTACH:
if (SR3ModUI_Load()) {                                     // 0 = not installed; all calls stay no-ops
    ModUI.AddPage("mymod", "My Mod");
    ModUI.AddToggle("mymod", "god", "Invincible", 0, on_change, NULL);
    ModUI.AddSlider("mymod", "speed", "Speed", 0.5, 3.0, 0.25, 1.0, on_change, NULL);
    ModUI.AddChoice("mymod", "weather", "Weather", "Clear|Rain|Storm", 0, on_change, NULL);  // 0-based
    ModUI.AddColor("mymod", "hud", "HUD colour", 0xFF40A0, on_change, NULL);
    ModUI.AddButton("mymod", "reset", "Reset", on_change, NULL);
    ModUI.AddLabel("mymod", "info", "Text");
}
double speed = ModUI.GetValue("mymod", "speed");          // any thread
ModUI.SetValue("mymod", "speed", 1.0);                     // saves; the menu updates
```

Callbacks run on the game's UI thread when the player changes a value. Saved values are restored when a
widget is added (read them with `GetValue`). A C mod may add widgets to a page its own Lua script made
(same page id); they appear after the script's rows.

Lua scripts can call C code through handlers:

```c
static void __cdecl add(SR3ModUI_Call* c, void* user) {
    ModUI.ReturnNumber(c, ModUI.ArgNumber(c, 1) + ModUI.ArgNumber(c, 2));
}
ModUI.RegisterHandler("mymod_add", add, NULL);             // Lua: ModUI.call("mymod_add", 2, 3) --> 5
```

See [`examples/example_asi.cpp`](examples/example_asi.cpp) and [`examples/example_mod.lua`](examples/example_mod.lua).

## Mods built with SR3 Mod UI

SR3 Mod UI ships no mods of its own (the example page is opt-in with `install.ps1 -Examples`). Mods that
use it list it as a requirement and are installed separately:

- [Store Colour Picker](https://github.com/PurrsianMilkman/Saints-Row-The-Third-Store-Color-Picker):
  true-RGB HSL colour picker for the clothing stores (a script hooking the stock store + an ASI handler).

## How it works

The game loads every Lua script (each UI document's script and the gameplay scripts) through two engine
loaders. SR3ModUI.asi redirects their `luaL_loadbuffer` / `lua_pcall` calls: before the first script of a
Lua state it registers a native table and runs `modui.lua` and the mods; after every script it re-applies
the hooks. The MODS entry is a hook on `pause_menu_top_init`; the MODS screen is drawn by the pause menu's
own list inside the Options document. Addresses and details: [`docs/ENGINE.md`](docs/ENGINE.md).

DX11 executable only (the addresses are checked before patching; anything else leaves the plugin
inactive and says so in the log).

## Tests

`test/sim.lua` drives the MODS screen against stubs: `python tools/luacheck.py run test/_pre.lua test/sim.lua`
(needs a 64-bit Lua 5.1/LuaJIT DLL; OBS Studio's is used by default, `LUA51_DLL` overrides).
`tools/drive.ps1` drives a second game copy with posted window messages (no focus needed) and captures its
window; `tools/multi_instance.cpp` is a test-only plugin that lets that copy run next to another instance.

## License

MIT, see [LICENSE](LICENSE).

Your support is greatly appreciated. Nothing is paywalled: https://www.patreon.com/cw/Purrsian
