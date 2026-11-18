-- Offline test of ModUI.extend / ModUI.modify against a stub of the game's Display screen.
-- Run after sim.lua in the same state:  python tools/luacheck.py run test/_pre.lua test/sim.lua test/sim_extend.lua
local fails = 0
local function check(cond, msg) if cond then print("pass: " .. msg) else print("FAIL: " .. msg) fails = fails + 1 end end

-- the real tracker is a class: instances find add_input through the metatable
Vdo_input_tracker = {}
Vdo_input_tracker.__index = Vdo_input_tracker
function Vdo_input_tracker:new() return setmetatable({ inputs = {} }, Vdo_input_tracker) end
function Vdo_input_tracker:add_input(input, fname) self.inputs[input] = fname end
function Vdo_input_tracker:subscribe() end
function Vdo_input_tracker:remove_all() end

-- the list as a class instance (draw_items/add_mouse_inputs come from the class)
local ListClass = {}
ListClass.__index = ListClass
for k, v in pairs(List) do if type(v) == "function" then ListClass[k] = v end end
local real_draw = ListClass.draw_items
function ListClass:draw_items(data, sel, width)
	real_draw(self, data, sel, width)
	local longest = 0
	for i = 1, #data do if data[i].label and #data[i].label > longest then longest = #data[i].label end end
	self.width = math.max(width or 0, longest * 12)		-- the real list grows to its content
end
function ListClass:get_button_index(t) return t or 0 end
function ListClass:is_left_arrow() return false end
function ListClass:is_right_arrow() return false end
function ListClass:is_slider() return false end
List = setmetatable({ sel = 1 }, ListClass)

local styled_width = nil
function menu_common_set_list_style(l, h, w) styled_width = w end

-- stub Display screen: index-addressed rows like the real one
local stock = {}
local Data
local VSYNC_INDEX
function pause_options_display_pc_init()
	local t = Vdo_input_tracker:new()
	t:add_input("select", "options_display_button_a", 50)
	t:add_input("nav_left", "options_display_nav_left", 50)
	t:add_input("nav_right", "options_display_nav_right", 50)
	Data = {}
	Data[#Data + 1] = { type = TYPE_TOGGLE, label = "MENU_SHADOW_DETAIL", options = { "LOW", "HIGH" }, current_value = 1, id = 1 }
	Data[#Data + 1] = { type = TYPE_TOGGLE, label = "MENU_VSYNC", options = { "OPTION_NO", "OPTION_YES" }, current_value = 1, id = 2 }
	VSYNC_INDEX = #Data
	List:draw_items(Data, 1, 800)
	menu_common_set_list_style(List, Header_obj, 800)
	List:add_mouse_inputs("pause_options_display_pc", Vdo_input_tracker:new())
end
function options_display_nav_right() stock.right = List:get_selection() List:move_slider(1) end
function options_display_nav_left() stock.left = List:get_selection() List:move_slider(-1) end
function options_display_button_a() stock.a = List:get_selection() end
function pause_options_display_pc_mouse_click(e, target) stock.click = target end
function pause_options_display_pc_cleanup() stock.cleanup = true end

-- the mod
local got = {}
local p = ModUI.extend("display", "moreopts", { heading = "MORE OPTIONS" })
p:toggle("fxaa", "A fairly long extra smoothing option label", false, function(v) got.fxaa = v end)
p:slider("lod", "LOD distance", 1, 3, 0.5, 1, function(v) got.lod = v end)
p:button("apply", "Apply extras", function() got.apply = true end)
p:tip("fxaa", "Smooths edges")
ModUI.modify("display", function(data)
	for i = 1, #data do
		if data[i].label == "MENU_SHADOW_DETAIL" then data[i].options[3] = "ULTRA+" end
	end
end)
ModUI._booted()
ModUI._after_load("pause_options_display_pc")

pause_options_display_pc_init()
check(#List.data == 6, "3 rows + heading appended (" .. #List.data .. " rows)")
check(List.data[VSYNC_INDEX].label == "MENU_VSYNC", "stock rows keep their indices")
check(List.data[3].label == "MORE OPTIONS" and List.data[3].disabled, "heading row greyed")
check(List.data[1].options[3] == "ULTRA+", "modify edited a stock row")
check(List.data[4].tool_tip_text == "Smooths edges", "tooltip carried")
check(styled_width ~= nil and styled_width > 800, "panel widened for our rows (" .. tostring(styled_width) .. ")")
local hidden = true
for _, pg in ipairs(ModUI.pages()) do if pg.id == "moreopts" and not pg.hidden then hidden = false end end
check(hidden, "attached page not listed in MODS")

-- our toggle: select and right go to us, not the stock handlers
List:set_selection(4) options_display_button_a()
check(got.fxaa == true and stock.a == nil, "select on our toggle -> our callback, stock skipped")
List:set_selection(5) options_display_nav_right()
check(got.lod == 1.5 and stock.right == nil, "right on our slider -> 1.5, stock skipped")
List:set_selection(6) options_display_button_a()
check(got.apply == true, "our button")
-- a stock row still goes to the game
List:set_selection(2) options_display_nav_right()
check(stock.right == 2, "right on a stock row -> stock handler")
-- mouse: clicking our row is ours, clicking a stock row is the game's
got.apply = nil
pause_options_display_pc_mouse_click(nil, 6)
check(got.apply == true and stock.click == nil, "click on our button -> ours")
pause_options_display_pc_mouse_click(nil, 1)
check(stock.click == 1, "click on a stock row -> stock")
-- the screen rebuilds its list (presets): ours come back once
Data = { Data[1], Data[2] }
List:draw_items(Data, 1, 800)
check(#List.data == 6, "redraw re-appends our rows once (" .. #List.data .. ")")
-- values persist
check(p:get("lod") == 1.5 and p:get("fxaa") == true, "values stored")
-- leaving the screen removes the injection
pause_options_display_pc_cleanup()
check(stock.cleanup and rawget(List, "draw_items") == nil, "cleanup restores the list")
List:draw_items({ { type = TYPE_BUTTON, label = "X" } }, 1, 495)
check(#List.data == 1, "other screens are untouched afterwards")
print(fails == 0 and "EXTEND ALL PASS" or (fails .. " EXTEND FAILED"))
