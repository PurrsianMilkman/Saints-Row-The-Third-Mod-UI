# Engine notes (SaintsRowTheThird_DX11.exe, sha256 66d3ba3a...08d2b)

Found by disassembly (tools/disasm.py, funcs.py, xref.py, find_reg.py, scan_bindings.py) and verified in
game on 2026-11-17.

## Script loaders

| Loader | luaL_loadbuffer call | lua_pcall call | Notes |
|---|---|---|---|
| 0x00E7BB00 (file) | 0x00E7BBDA | 0x00E7BBED `lua_pcall(L, 0, -1, 0)` | all UI documents and gameplay scripts seen so far |
| 0x00E7C180 (buffer) | 0x00E7C207 | 0x00E7C218 | wraps the load in `_PrepareForDynamicGlobals(name)` / `_DynamicGlobalsLoadComplete()` |

SR3ModUI patches the four `call rel32` targets (each checked against the expected callee first).

## Lua states

- **UI** (interface): has `vint_document_find`. First script `system_lib.lua`, then `vint_lib.lua`.
- **Gameplay**: has `teleport_to_object`. Rebuilt on every save load (`system_lib`, `game_lib`, `sr3_city`).
- The globals table has **no metatable** when the state boots; `system_lib.lua` keeps per-script globals in
  `_DynamicGlobals[name]` and `_UGGlobals` carries the catching metatable. SR3ModUI only ever reads and
  writes globals raw (`gget`/`gset` also look into `_DynamicGlobals`), and runs the mods with any
  metatable on the globals lifted.
- The UI state lacks string/math/table/os, pcall, tonumber.

## Lua 5.1 C API

gettop E02050, settop E02060, remove E020B0, insert E02100, replace E02150, pushvalue E02210,
type E02240, typename E02260, iscfunction E02280, isnumber E022B0, rawequal E02320, tonumber E02360,
tointeger E023A0, toboolean E023E0, tolstring E02410, objlen E02480, pushnil E02580, pushnumber E025A0,
pushinteger E025C0, pushlstring E025E0, pushstring E02620, pushfstring E026C0, pushcclosure E026F0,
pushboolean E02790, pushlightuserdata E027B0, gettable E027E0, getfield E02810, rawget E02870,
rawgeti E028B0, createtable E028F0, getmetatable E02930, getfenv E02990, settable E02A00,
setfield E02A30, rawset E02A90, setmetatable E02B00, call E02C40, pcall E02CA0, load E02D10,
next E02E70, luaL_loadbuffer FCF890 (all 0x00......). No `lua_rawseti` in this build. TValue is 16 bytes
(numbers are doubles). Base library luaL_Reg array at 0x012971D0.

## Pause menu

- Screens are documents that drive the shared `List` (a `Vdo_mega_list` from `pause_menu_common`):
  `menu_common_transition_push("doc")` / `menu_common_transition_pop(n)`.
- Row types: `TYPE_BUTTON` 0, `TYPE_TOGGLE` 1 (`options`, `current_value` = index), `TYPE_SLIDER` 2
  (`min`/`max`/`step`, optional `mapping` value -> text), `TYPE_TOGGLE_COLOR` (`color` = {red, green, blue}).
  `disabled = true` greys a row and the cursor skips it.
- `List:draw_items(data, sel, width)` keeps a reference to `data`; `move_slider` writes `current_value`
  into it. Stock width 495.
- `Vdo_pause_header:set_text` uses a capitals-only font: lower-case letters render as nothing.
- Mouse: `List:add_mouse_inputs(prefix, tracker)` subscribes the globals `<prefix>_mouse_click/_move/
  _drag/_drag_release/_scroll`.

## Single instance

At start-up the game creates a named mutex (CreateMutexW at 0x00DC8872); if it already exists
(GetLastError 0xB7) it brings the other window forward and exits. `tools/multi_instance.cpp` turns the
`jne` at 0x00DC888C into `jmp` (test copies only).

## Input for automated tests

In a windowed copy, `SendInput` did not reach the game, but `PostMessage(WM_KEYDOWN/WM_KEYUP)` to its
window drives both menus and gameplay (held keys need auto-repeat messages, tools/hold.ps1).
`PrintWindow(hwnd, dc, PW_RENDERFULLCONTENT)` captures the game window even when it is covered.
