-- Offline simulation of the UI state for modui.lua (python tools/luacheck.py run test/_pre.lua test/sim.lua).
-- Stubs the natives, the pause menu list and the vint objects; drives the MODS screen; prints pass/FAIL.
local G = _G
floor = math.floor
TYPE_BUTTON, TYPE_TOGGLE, TYPE_SLIDER, TYPE_TOGGLE_COLOR = 0, 1, 2, 5
CTRL_MENU_BUTTON_B = 1
local saved = {}
local logs = {}
__modui_c = {
	state = "ui",
	log = function(s) logs[#logs + 1] = s print("  log: " .. s) end,
	pcall = pcall,
	fmt = function(x, d) return string.format("%." .. d .. "f", x) end,
	upper = string.upper,
	call = function() end,
	gget = function(k) return rawget(G, k) end,
	gset = function(k, v) rawset(G, k, v) end,
	find = function(s, sub) return string.find(s, sub, 1, true) ~= nil end,
	load = function(p, k) return saved[p .. "." .. k] end,
	save = function(p, k, v) saved[p .. "." .. k] = v end,
	rev = function() return 3 end,
	c_pages = function()
		return { { id = "cmod", title = "C Mod", widgets = {
			{ type = "toggle", key = "on", label = "On", value = 1, enabled = true, min = 0, max = 1, step = 1 },
			{ type = "choice", key = "q", label = "Quality", value = 1, enabled = true, options = { "Low", "Mid", "High" } } } } }, 3
	end,
	c_changed = function(p, k, v) logs[#logs + 1] = "c_changed " .. p .. "." .. k .. "=" .. v end,
}

-- vint objects
local OBJS = {}
local Obj = {}
Obj.__index = Obj
local function newobj(name) local o = setmetatable({ name = name, handle = #OBJS + 1, tint = nil, alpha = 1 }, Obj) OBJS[#OBJS + 1] = o return o end
function Obj:set_visible() end
function Obj:set_actual_size(w, h) self.w, self.h = w, h end
function Obj:get_actual_size() return 156, 12 end
function Obj:set_anchor(x, y) self.x, self.y = x, y end
function Obj:get_anchor() return 10, 0 end
function Obj:set_color(r, g, b) self.tint = { r, g, b } end
function Obj:set_depth(d) self.depth = d end
function Obj:get_depth() return 0 end
function Obj:set_alpha(a) self.alpha = a end
Vdo_base_object = {
	new = function(self, name, parent) return newobj(name) end,
	clone = function(self, h, parent) return newobj("clone") end,
}
Vdo_input_tracker = { new = function() return { add_input = function() end, subscribe = function() end, remove_all = function() end } end }
function game_get_platform() return "PC" end
function game_UI_audio_play() end
function bg_saints_show() end
function bg_saints_slide_out() end
local pushed = nil
function menu_common_transition_push(s) pushed = s end
function menu_common_transition_pop(n) pushed = "pop" .. n end
function menu_common_stack_add() end
function menu_common_stack_remove() end
function menu_common_set_list_style() end
function menu_common_set_screen_data() end
Menu_common_stack = { current_stack = 0 }
Header_obj = { set_text = function(self, t) self.text = t end }
Menu_hint_bar = { set_hints = function() end, add_mouse_inputs = function() end, get_hint_index = function() return 0 end, set_highlight = function() end }

-- the pause menu's list
List = { sel = 1 }
function List:draw_items(data, sel, w)
	self.data, self.sel = data, sel
	self.buttons = {}
	for i = 1, #data do
		local b = { set_label = function(s, l) s.label = l end }
		if data[i].type == TYPE_SLIDER then b.slider = { handle = 1000 + i, doc_handle = 1 } end
		if data[i].type == TYPE_TOGGLE_COLOR then b.toggle_color = { set_color_value = function(s, c) s.c = c end } end
		self.buttons[i] = b
	end
end
function List:get_selection() return self.sel end
function List:set_selection(i) self.sel = i end
function List:get_id() return self.data[self.sel].id end
function List:move_cursor(d) self.sel = self.sel + d end
function List:move_slider(d)
	local it = self.data[self.sel]
	if it.type == TYPE_SLIDER then it.current_value = math.max(it.min, math.min(it.max, it.current_value + d * it.step))
	elseif it.type == TYPE_TOGGLE then it.current_value = it.current_value + d if it.current_value > #it.options then it.current_value = 1 end if it.current_value < 1 then it.current_value = #it.options end end
end
function List:button_a() end
function List:button_b() end
function List:add_mouse_inputs() end
function List:enable_toggle_input() end

local fails = 0
local function check(cond, msg) if cond then print("pass: " .. msg) else print("FAIL: " .. msg) fails = fails + 1 end end

-- boot: the API, then a Lua mod
dofile(MODUI)
local got = {}
local p = ModUI.page("demo", "Demo")
p:toggle("on", "Enabled", false, function(v) got.on = v end)
p:slider("dens", "Density", 0, 2, 0.25, 1, function(v) got.dens = v end)
p:color("tint", "Tint", 0xFF0000, function(v, r, g, b) got.tint = v end)
p:button("go", "Go", function() got.go = true end)
p:label("info", "Info")
ModUI._booted()

-- a game document defines its functions, then the engine runs them
local Data
function pause_menu_top_init()
	Data = { { type = TYPE_BUTTON, label = "SAVELOAD_SAVE_GAME", id = 1 }, { type = TYPE_BUTTON, label = "HORDE_MODE_MENU_EXIT", id = 5 } }
	List:draw_items(Data, 1, 495)
end
function pause_menu_top_button_a() got.orig_a = true end
function pause_options_menu_init() got.options_init = true end
function pause_options_menu_cleanup() got.options_cleanup = true end
ModUI._after_load("pause_menu_top")

pause_menu_top_init()
check(#List.data == 3 and List.data[2].label == "MODS", "MODS inserted before Quit")
List:set_selection(2)
pause_menu_top_button_a()
check(pushed == "pause_options_menu" and not got.orig_a, "selecting MODS pushes the host screen")
pause_options_menu_init()
check(not got.options_init and Header_obj.text == "MODS", "options init replaced by the MODS screen")
check(List.data[1].label == "C Mod" and List.data[2].label == "Demo", "pages listed and sorted (C page included)")
List:set_selection(2) modui_menu_button_a()
check(Header_obj.text == "DEMO" and #List.data == 5, "page opened with 5 rows")
check(List.data[5].disabled == true, "label row disabled")
List:set_selection(1) modui_menu_button_a()
check(got.on == true and saved["demo.on"] == 1, "toggle via select -> true, saved 1")
List:set_selection(2) modui_menu_nav_right()
check(got.dens == 1.25 and List.data[2].mapping[5] == "1.25", "slider step + mapping text")
List:set_selection(4) modui_menu_button_a()
check(got.go == true, "button callback")
List:set_selection(3) modui_menu_button_a()
check(Header_obj.text == "TINT" and #List.data == 4, "colour editor opened")
local segs = 0
for _, o in ipairs(OBJS) do if o.name == "clone" and o.alpha == 1 and o.tint ~= nil then segs = segs + 1 end end
check(segs >= 3 * 24, "colour bars painted (" .. segs .. " visible pieces)")
List:set_selection(1) for i = 1, 40 do modui_menu_nav_right() end		-- hue 0 -> 120
check(got.tint ~= nil and got.tint ~= 0xFF0000, "live colour change notified: " .. string.format("%06X", got.tint or 0))
check(List.data[1].label == "Hue  120", "hue label shows value: " .. List.data[1].label)
modui_menu_button_b()
check(got.tint == 0xFF0000 and Header_obj.text == "DEMO", "back restores the old colour")
List:set_selection(3) modui_menu_button_a()
List:set_selection(1) for i = 1, 40 do modui_menu_nav_right() end
List:set_selection(4) modui_menu_button_a()
check(saved["demo.tint"] == got.tint and got.tint ~= 0xFF0000 and Header_obj.text == "DEMO", "keep stores the colour")
modui_menu_button_b()
List:set_selection(1) modui_menu_button_a()
check(Header_obj.text == "C MOD", "C page opened")
List:set_selection(2) modui_menu_nav_right()
local last = logs[#logs]
check(last == "c_changed cmod.q=2", "C choice reports 0-based index: " .. tostring(last))
modui_menu_button_b() modui_menu_button_b()
check(pushed == "pop1", "back from the top pops the screen")
pause_options_menu_cleanup()
check(not got.options_cleanup, "cleanup handled for the MODS screen")
pause_options_menu_init()
check(got.options_init, "the real Options screen still opens normally")
-- reload: the document redefines its function; the hook must come back exactly once
function pause_menu_top_init() Data = { { type = TYPE_BUTTON, label = "HORDE_MODE_MENU_EXIT", id = 5 } } List:draw_items(Data, 1, 495) end
ModUI._after_load("pause_menu_top")
ModUI._after_load("something_else")
pause_menu_top_init()
check(#List.data == 2 and List.data[1].label == "MODS", "hook re-applied once after reload")
-- a broken hook must not break the game function
function broken_fn() got.broken_ran = true end
ModUI.wrap("broken_fn", function(orig) error("boom") end)
broken_fn()
check(got.broken_ran, "erroring hook falls back to the original")
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
