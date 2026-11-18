-------------------------------------------------------------------------------------------------------
-- SR3 Mod UI - the Lua side of the API (SR3ModUI\modui.lua, run by SR3ModUI.asi in each Lua state).
--
-- For mod authors (UI state):
--   local page = ModUI.page("mymod", "My Mod")                 -- a page in Pause > MODS
--   page:toggle("enabled", "Enabled", true, function(on) end)
--   page:slider("density", "Density", 0, 10, 0.5, 2, function(v) end)
--   page:choice("mode", "Mode", { "Calm", "Busy", "Chaos" }, 1, function(i, name) end)
--   page:color("tint", "Tint", 0xFF4080, function(rgb, r, g, b) end)
--   page:button("reset", "Reset", function() end)
--   page:label("info", "Some text")
--   page:get("density")  page:set("density", 3)  page:set_label("info", "...")  page:enable("mode", false)
--   ModUI.wrap("store_clothing_item_details", function(orig, ...) ... return orig(...) end)
--   ModUI.on_load("store_clothing", function(script) end)
--   ModUI.call("my_c_handler", 1, 2)  -- a handler an ASI registered with RegisterHandler
--   ModUI.HslEditor - the HSL colour editor with colour bars, for any game list (see below)
-- Values are saved to SR3ModUI.ini. Everything here runs on the game's UI thread.
-------------------------------------------------------------------------------------------------------
local C = __modui_c
local M = {}
C.gset("ModUI", M)

M.version = 2
M.state = C.state			-- "ui" or "game"
M.pcall = C.pcall			-- the UI state has no pcall of its own
M.fmt = C.fmt				-- fmt(x, decimals) -> string
M.call = C.call
M.global = C.gset			-- define/replace a global safely after start-up: ModUI.global(name, value)
M.get_global = C.gget		-- read a global without the "undefined global" error

local function str(x)
	local t = type(x)
	if t == "string" then return x end
	if t == "number" then return x .. "" end
	if t == "boolean" then if x then return "true" end return "false" end
	return "(" .. t .. ")"
end
M.str = str

function M.log(a, b, c, d, e, f)
	local s = str(a)
	local rest = { b, c, d, e, f }
	for i = 1, 5 do
		if rest[i] ~= nil then s = s .. " " .. str(rest[i]) end
	end
	C.log(s)
end

local function round(x) return floor(x + 0.5) end
local function clamp(x, lo, hi) if x < lo then return lo end if x > hi then return hi end return x end

-------------------------------------------------------------------------------------------------------
-- hooks: wrap a game function by name; re-applied every time a script (re)defines it
-------------------------------------------------------------------------------------------------------
local Hooks = {}			-- name -> { list = { hook, ... }, base = original, top = outermost wrapper }
local Load_handlers = {}	-- { { pattern, fn }, ... }

local function contains(s, sub)
	-- plain substring test without the string library
	return C.find(s, sub)
end

local function build(name, h, base)
	local f = base
	for i = 1, #h.list do
		local inner, hook = f, h.list[i]
		f = function(...)
			local called = false
			local orig = function(...) called = true return inner(...) end
			local ok, a, b, c, d = C.pcall(hook, orig, ...)
			if ok then return a, b, c, d end
			M.log("ERROR in a hook on " .. name .. ": " .. str(a))
			if not called then return inner(...) end
		end
	end
	h.base, h.top = base, f
	C.gset(name, f)
end

local function apply_hook(name)
	local h = Hooks[name]
	local cur = C.gget(name)
	if type(cur) ~= "function" or cur == h.top then return end
	build(name, h, cur)
end

-- ModUI.wrap("game_function", function(orig, ...) ... end): your function runs instead of the game's,
-- and calls orig(...) when (and if) the game's should run. Works across document reloads.
function M.wrap(name, hook)
	local h = Hooks[name]
	if h == nil then
		h = { list = {} }
		Hooks[name] = h
	end
	h.list[#h.list + 1] = hook
	if h.top ~= nil and C.gget(name) == h.top then
		build(name, h, h.base)
	else
		apply_hook(name)
	end
end

-- ModUI.on_load("pattern", fn): fn(script_name) after every script whose name contains pattern
function M.on_load(pattern, fn)
	Load_handlers[#Load_handlers + 1] = { pattern, fn }
end

function M._after_load(script)
	for name, _ in pairs(Hooks) do
		apply_hook(name)
	end
	for i = 1, #Load_handlers do
		local h = Load_handlers[i]
		if contains(script, h[1]) then
			local ok, err = C.pcall(h[2], script)
			if not ok then M.log("ERROR in on_load(" .. h[1] .. "): " .. str(err)) end
		end
	end
end

-------------------------------------------------------------------------------------------------------
-- colour helpers (sRGB 0..1; packed colours are 0xRRGGBB numbers)
-------------------------------------------------------------------------------------------------------
function M.rgb_unpack(n)
	n = floor(n or 0)
	local r = floor(n / 65536) % 256
	local g = floor(n / 256) % 256
	local b = n % 256
	return r / 255, g / 255, b / 255
end

function M.rgb_pack(r, g, b)
	return round(clamp(r, 0, 1) * 255) * 65536 + round(clamp(g, 0, 1) * 255) * 256 + round(clamp(b, 0, 1) * 255)
end

local function hue2rgb(p, q, t)
	if t < 0 then t = t + 1 end
	if t > 1 then t = t - 1 end
	if t < 1 / 6 then return p + (q - p) * 6 * t end
	if t < 1 / 2 then return q end
	if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
	return p
end

-- h 0..360, s and l 0..1 -> r, g, b 0..1
function M.hsl_to_rgb(h, s, l)
	if s <= 0 then return l, l, l end
	local q
	if l < 0.5 then q = l * (1 + s) else q = l + s - l * s end
	local p = 2 * l - q
	local hh = h / 360
	return hue2rgb(p, q, hh + 1 / 3), hue2rgb(p, q, hh), hue2rgb(p, q, hh - 1 / 3)
end

-- r, g, b 0..1 -> h 0..360, s and l 0..1
function M.rgb_to_hsl(r, g, b)
	local mx, mn = r, r
	if g > mx then mx = g end
	if b > mx then mx = b end
	if g < mn then mn = g end
	if b < mn then mn = b end
	local l = (mx + mn) / 2
	local d = mx - mn
	if d < 0.00001 then return 0, 0, l end
	local s
	if l > 0.5 then s = d / (2 - mx - mn) else s = d / (mx + mn) end
	local h
	if mx == r then
		h = (g - b) / d
		if g < b then h = h + 6 end
	elseif mx == g then
		h = (b - r) / d + 2
	else
		h = (r - g) / d + 4
	end
	return h * 60, s, l
end

-------------------------------------------------------------------------------------------------------
-- HSL editor: Hue / Saturation / Luminance sliders with colour bars and a Result swatch, for any game
-- list built from TYPE_SLIDER / TYPE_TOGGLE_COLOR rows (pause menus, store menus).
--
--   local ed = ModUI.HslEditor.new{ r = 1, g = 0.2, b = 0.5,
--                                   on_change = function(r, g, b) end }   -- each slider move
--   local rows = ed:make_rows("Result (select to keep)")                    -- 4 row tables
--   -- put rows[1..4] into your menu data, then tell the editor where they are:
--   ed:attach(list, first_index)          -- after the list is drawn; builds the colour bars
--   ed:changed()                          -- after a slider row's current_value changed
--   ed:get() -> r, g, b                   -- the colour now
-------------------------------------------------------------------------------------------------------
local Hsl = {}
Hsl.__index = Hsl
M.HslEditor = Hsl

local HSL_SEGS = 24		-- pieces per colour bar
local HSL_BAR_W = 156	-- width of a slider's fill (vdo_slider.lua width_max)
local HSL_NAMES = { "Hue", "Saturation", "Luminance" }

function Hsl.new(o)
	local ed = { on_change = o.on_change, rgb = { red = 1, green = 1, blue = 1 }, bars = {} }
	setmetatable(ed, Hsl)
	local h, s, l = M.rgb_to_hsl(o.r or 1, o.g or 1, o.b or 1)
	ed.hsl = { round(h) % 360, round(s * 100), round(l * 100) }
	ed.rgb.red, ed.rgb.green, ed.rgb.blue = o.r or 1, o.g or 1, o.b or 1
	return ed
end

function Hsl:label(i)
	return HSL_NAMES[i] .. "  " .. round(self.hsl[i])
end

function Hsl:make_rows(result_label, row_extra)
	local maxes, steps = { 359, 100, 100 }, { 3, 2, 2 }
	self.items = {}
	for i = 1, 3 do
		local it = { type = TYPE_SLIDER, label = self:label(i), min = 0, max = maxes[i], step = steps[i], current_value = self.hsl[i] }
		if row_extra ~= nil then for k, v in pairs(row_extra) do it[k] = v end end
		self.items[i] = it
	end
	self.items[4] = { type = TYPE_TOGGLE_COLOR, label = result_label or "Result", color = self.rgb }
	if row_extra ~= nil then for k, v in pairs(row_extra) do self.items[4][k] = v end end
	return self.items
end

function Hsl:get()
	return self.rgb.red, self.rgb.green, self.rgb.blue
end

-- colour of a bar at position t (0..1) for slider i
function Hsl:bar_color(i, t)
	local h, s, l = self.hsl[1], self.hsl[2] / 100, self.hsl[3] / 100
	if i == 1 then return M.hsl_to_rgb(t * 360, 1, 0.5) end
	if i == 2 then return M.hsl_to_rgb(h, t, l) end
	return M.hsl_to_rgb(h, s, t)
end

local function piece(left, sl)
	local o = Vdo_base_object:clone(left.handle, sl.handle, sl.doc_handle)
	o:set_visible(true)
	return o
end

-- Lay out, recolour and re-show every piece of every bar, move the marker, update the label. All of it
-- is re-applied on each paint, so nothing the stock slider code did in between survives.
function Hsl:paint()
	for i, bar in pairs(self.bars) do
		local item = self.items[i]
		for k = 1, HSL_SEGS do
			local seg = bar.parts[k]
			local r, g, b = self:bar_color(i, (k - 0.5) / HSL_SEGS)
			seg:set_actual_size(bar.seg_w + 0.75, bar.h)
			seg:set_anchor(bar.x + (k - 1) * bar.seg_w, bar.y)
			seg:set_color(r, g, b)
			seg:set_depth(bar.depth)
			seg:set_alpha(1)
		end
		local t = (item.current_value - item.min) / (item.max - item.min)
		local mx = bar.x + t * HSL_BAR_W
		local out, inn = bar.parts[HSL_SEGS + 1], bar.parts[HSL_SEGS + 2]
		-- vint draws LOWER depth in front; at equal depth the order is arbitrary
		out:set_actual_size(3, bar.h)
		out:set_anchor(mx - 1.5, bar.y)
		out:set_color(0.05, 0.05, 0.05)
		out:set_depth(bar.depth - 1)
		out:set_alpha(1)
		inn:set_actual_size(1.2, bar.h)
		inn:set_anchor(mx - 0.6, bar.y)
		inn:set_color(1, 1, 1)
		inn:set_depth(bar.depth - 2)
		inn:set_alpha(1)
		for _, o in pairs(bar.hide) do o:set_alpha(0) end
		item.label = self:label(i)
		if bar.button.set_label ~= nil then bar.button:set_label(item.label) end
	end
	local sw = self.list ~= nil and self.list.buttons ~= nil and self.list.buttons[self.first + 3] or nil
	if sw ~= nil and sw.toggle_color ~= nil then sw.toggle_color:set_color_value(self.rgb) end
end

-- Replace each slider's fill with HSL_SEGS tinted clones of itself plus a two-line marker.
function Hsl:attach(list, first)
	self.list, self.first, self.bars = list, first, {}
	if list == nil or list.buttons == nil then return end
	for i = 1, 3 do
		local b = list.buttons[first + i - 1]
		if b ~= nil and b.slider ~= nil then
			local sl = b.slider
			local left = Vdo_base_object:new("slider_bg_left", sl.handle, sl.doc_handle)
			local right = Vdo_base_object:new("slider_bg_right", sl.handle, sl.doc_handle)
			local value = Vdo_base_object:new("slider_value", sl.handle, sl.doc_handle)
			local x, y = left:get_anchor()
			local w, h = left:get_actual_size()
			local depth = left:get_depth()
			if type(depth) ~= "number" then depth = 0 end
			local bar = { parts = {}, x = x, y = y, h = h, depth = depth, seg_w = HSL_BAR_W / HSL_SEGS, button = b,
				hide = { left, right, value } }
			for k = 1, HSL_SEGS + 2 do bar.parts[k] = piece(left, sl) end
			-- The stock slider finds its fill BY NAME on every change, resizes it and paints it; clones share
			-- the name, so the lookup can land on one of ours. A hidden decoy takes the hit; a piece the
			-- lookup still lands on becomes a decoy too and is replaced. Decoys never get alpha back.
			local decoys = { piece(left, sl) }
			for _ = 1, 4 do
				local f = Vdo_base_object:new("slider_bg_left", sl.handle, sl.doc_handle)
				local hit = nil
				for k = 1, #bar.parts do
					if bar.parts[k].handle == f.handle then hit = k end
				end
				if hit == nil then break end
				decoys[#decoys + 1] = bar.parts[hit]
				bar.parts[hit] = piece(left, sl)
			end
			for _, o in pairs(decoys) do
				o:set_actual_size(0.01, h)
				bar.hide[#bar.hide + 1] = o
			end
			self.bars[i] = bar
		end
	end
	self:paint()
end

-- read the three sliders, recompute the colour, repaint, tell the owner
function Hsl:changed()
	for i = 1, 3 do self.hsl[i] = self.items[i].current_value end
	local r, g, b = M.hsl_to_rgb(self.hsl[1], self.hsl[2] / 100, self.hsl[3] / 100)
	self.rgb.red, self.rgb.green, self.rgb.blue = r, g, b
	self:paint()
	if self.on_change ~= nil then
		local ok, err = C.pcall(self.on_change, r, g, b)
		if not ok then M.log("ERROR in HslEditor on_change: " .. str(err)) end
	end
end

if M.state ~= "ui" then return end

-------------------------------------------------------------------------------------------------------
-- pages and widgets
-------------------------------------------------------------------------------------------------------
local Pages = {}			-- in display order
local Adding_c = false		-- set while mirroring C widgets
local Page = {}
Page.__index = Page

local function valid_id(s)
	return type(s) == "string" and #s > 0 and #s <= 64
end

-- ModUI.page(id, title) -> page (the same page again if the id exists)
function M.page(id, title, opts)
	if not valid_id(id) then M.log("ModUI.page: bad id " .. str(id)) return nil end
	for i = 1, #Pages do
		if Pages[i].id == id then
			if title ~= nil then Pages[i].title = title end
			return Pages[i]
		end
	end
	local p = { id = id, title = title or id, widgets = {}, by_key = {} }
	setmetatable(p, Page)
	Pages[#Pages + 1] = p
	return p
end

function M.pages() return Pages end

function Page:add(w)
	if not valid_id(w.key) then M.log("ModUI: bad widget key on page " .. self.id) return nil end
	local old = self.by_key[w.key]
	if old ~= nil then
		for i = 1, #self.widgets do if self.widgets[i] == old then self.widgets[i] = w end end
	else
		self.widgets[#self.widgets + 1] = w
	end
	self.by_key[w.key] = w
	w.page = self
	if Adding_c then w.c = true end
	if w.enabled == nil then w.enabled = true end
	if w.kind ~= "button" and w.kind ~= "label" and not w.c then
		local saved = C.load(self.id, w.key)
		if saved ~= nil then w.value = w.decode(saved) end
	end
	return w
end

local function num(v) return v end
local function from_bool(v) if v then return 1 end return 0 end
local function to_bool(n) return n ~= 0 end

function Page:button(key, label, fn)
	return self:add({ kind = "button", key = key, label = label or key, fn = fn, decode = num })
end
function Page:label(key, text)
	return self:add({ kind = "label", key = key, label = text or "", decode = num })
end
function Page:toggle(key, label, default, fn)
	return self:add({ kind = "toggle", key = key, label = label or key, value = default and true or false, fn = fn,
		decode = to_bool, encode = from_bool })
end
function Page:slider(key, label, min, max, step, default, fn)
	step = step or 1
	if not (max > min) or not (step > 0) then M.log("ModUI: bad slider range " .. key) return nil end
	local w = self:add({ kind = "slider", key = key, label = label or key, min = min, max = max, step = step,
		value = default or min, fn = fn, decode = num })
	if w ~= nil then w.value = clamp(w.value, min, max) end
	return w
end
function Page:choice(key, label, options, default, fn)
	return self:add({ kind = "choice", key = key, label = label or key, options = options, value = default or 1, fn = fn,
		decode = num })
end
-- opts.live = false: fn only when the player keeps the colour (default: on every slider move, and with
-- the old colour again when the player backs out)
function Page:color(key, label, default, fn, opts)
	local live = true
	if opts ~= nil and opts.live == false then live = false end
	return self:add({ kind = "color", key = key, label = label or key, value = default or 0xFFFFFF, fn = fn, live = live,
		decode = num })
end

function Page:get(key)
	local w = self.by_key[key]
	if w == nil then return nil end
	return w.value
end

local Screen = nil		-- the open MODS screen, if any
local redraw			-- defined with the screen
local sync_c_pages		-- defined with the C mirror
local C_rev = -1

local function notify(w, v)
	if w.c then
		local n = v
		if w.kind == "toggle" then n = from_bool(v) elseif w.kind == "choice" then n = v - 1 end
		C.c_changed(w.page.id, w.key, n or 0)
		-- the C callback may have changed values (SetValue/SetLabel): show them
		if C.rev() ~= C_rev then
			sync_c_pages()
			if Screen ~= nil and Screen.page == w.page and Screen.level == "page" then redraw() end
		end
		return
	end
	if w.fn == nil then return end
	local ok, err
	if w.kind == "choice" then
		ok, err = C.pcall(w.fn, v, w.options[v])
	elseif w.kind == "color" then
		local r, g, b = M.rgb_unpack(v)
		ok, err = C.pcall(w.fn, v, r, g, b)
	else
		ok, err = C.pcall(w.fn, v)
	end
	if not ok then M.log("ERROR in " .. w.page.id .. "." .. w.key .. ": " .. str(err)) end
end

local function store(w, v)
	w.value = v
	if not w.c then
		local n = v
		if w.encode ~= nil then n = w.encode(v) end
		C.save(w.page.id, w.key, n)
	end
end

-- set(key, value): changes and saves the value without calling the widget's function
function Page:set(key, v)
	local w = self.by_key[key]
	if w == nil then return end
	store(w, v)
	if Screen ~= nil and Screen.page == self then redraw() end
end
function Page:set_label(key, text)
	local w = self.by_key[key]
	if w == nil then return end
	w.label = text
	if Screen ~= nil and Screen.page == self then redraw() end
end
function Page:enable(key, on)
	local w = self.by_key[key]
	if w == nil then return end
	w.enabled = on and true or false
	if Screen ~= nil and Screen.page == self then redraw() end
end
-- on_open(fn): fn(page) each time the player opens the page (refresh labels/values here)
function Page:on_open(fn) self.open_fn = fn end

-------------------------------------------------------------------------------------------------------
-- pages registered by ASI mods (C API), mirrored here
-------------------------------------------------------------------------------------------------------
sync_c_pages = function()
	local rev = C.rev()
	if rev == C_rev then return end
	C_rev = rev
	local list = C.c_pages()
	for i = 1, #list do
		local cp = list[i]
		-- a page may mix Lua and C widgets (an ASI adding a button to its own script's page)
		local p = nil
		for k = 1, #Pages do if Pages[k].id == cp.id then p = Pages[k] end end
		if p == nil then p = M.page(cp.id, cp.title) end
		for j = 1, #cp.widgets do
			local cw = cp.widgets[j]
			local w
			Adding_c = true
			if cw.type == "button" then w = p:button(cw.key, cw.label)
			elseif cw.type == "label" then w = p:label(cw.key, cw.label)
			elseif cw.type == "toggle" then w = p:toggle(cw.key, cw.label, cw.value ~= 0)
			elseif cw.type == "slider" then w = p:slider(cw.key, cw.label, cw.min, cw.max, cw.step, cw.value)
			elseif cw.type == "choice" then w = p:choice(cw.key, cw.label, cw.options, floor(cw.value) + 1)
			elseif cw.type == "color" then w = p:color(cw.key, cw.label, cw.value)
			end
			Adding_c = false
			if w ~= nil then w.enabled = cw.enabled end
		end
		if cp.attach ~= nil and cp.attach ~= "" and not p.attached then
			M.extend(cp.attach, cp.id, { list_in_mods = cp.listed })
		end
	end
end

local function sort_pages()
	-- by title, case-insensitively is not possible without string.lower; plain order is fine
	for i = 2, #Pages do
		local p = Pages[i]
		local j = i - 1
		while j >= 1 and Pages[j].title > p.title do
			Pages[j + 1] = Pages[j]
			j = j - 1
		end
		Pages[j + 1] = p
	end
end

-------------------------------------------------------------------------------------------------------
-- the MODS screen: hosted in the pause menu's options document, drawn with the pause menu's list
-------------------------------------------------------------------------------------------------------
local ID_MODS = 7701
local WIDTH = 495		-- the stock pause screens' width (the minimum)
local MAX_WIDTH = 1000	-- widest panel (the screen is 1280 wide in UI units; the panel starts near x 100)
local PANEL_PAD = 30	-- panel beyond the list: room for the toggles' right arrows

-- width the list's rows need: its own sum (list.new_width) plus the colour swatch rows it does not count
local function list_content_width(list)
	local w = WIDTH
	if type(list.new_width) == "number" and list.new_width > w then w = list.new_width end
	local label = list.max_label_width
	local item = list.max_item_width
	if type(label) == "number" and type(item) == "number" and label + item + 20 > w then w = label + item + 20 end
	if w > MAX_WIDTH - PANEL_PAD then w = MAX_WIDTH - PANEL_PAD end
	return w
end
local Want_screen = false
local OPT_YES_NO = { "OPTION_NO", "OPTION_YES" }

-- slider rows run on whole steps (0..n) so the value shown is exact: the mapping gives each step's text
local function slider_mapping(w)
	local d, s = 0, w.step
	while d < 4 and (s - floor(s + 0.0000001)) > 0.000001 do
		s = s * 10
		d = d + 1
	end
	local n = round((w.max - w.min) / w.step)
	local map = {}
	for i = 0, n do map[i] = C.fmt(w.min + i * w.step, d) end
	if n == 1 then map[100] = map[1] end	-- vdo_slider rescales 0..1 ranges to percent
	return map, n
end

local function row_for(w)
	local it = { label = w.label, _w = w, disabled = not w.enabled }
	if w.kind == "button" then
		it.type = TYPE_BUTTON
	elseif w.kind == "label" then
		it.type = TYPE_BUTTON
		it.disabled = true
	elseif w.kind == "toggle" then
		it.type = TYPE_TOGGLE
		it.options = OPT_YES_NO
		it.current_value = w.value and 2 or 1
	elseif w.kind == "choice" then
		it.type = TYPE_TOGGLE
		it.options = w.options
		it.current_value = clamp(floor(w.value), 1, #w.options)
	elseif w.kind == "slider" then
		local map, n = slider_mapping(w)
		it.type = TYPE_SLIDER
		it.min, it.max, it.step = 0, n, 1
		it.mapping = map
		it.current_value = clamp(round((w.value - w.min) / w.step), 0, n)
	elseif w.kind == "color" then
		local r, g, b = M.rgb_unpack(w.value)
		it.type = TYPE_TOGGLE_COLOR
		it.color = { red = r, green = g, blue = b }
	end
	return it
end

local function screen_data()
	local data = {}
	if Screen.level == "pages" then
		Screen.title = "MODS"
		for i = 1, #Pages do
			if not Pages[i].hidden then		-- pages attached to a game screen live there instead
				data[#data + 1] = { type = TYPE_BUTTON, label = Pages[i].title, _page = Pages[i] }
			end
		end
		if #data == 0 then data[1] = { type = TYPE_BUTTON, label = "No mods installed", disabled = true } end
	elseif Screen.level == "page" then
		Screen.title = Screen.page.title
		for i = 1, #Screen.page.widgets do
			data[#data + 1] = row_for(Screen.page.widgets[i])
		end
		if #data == 0 then data[1] = { type = TYPE_BUTTON, label = "(empty)", disabled = true } end
	else	-- colour editor for Screen.color (Screen.ed is made when the editor opens)
		Screen.title = Screen.color.label
		local rows = Screen.ed:make_rows("Result (select to keep)")
		for i = 1, 4 do data[i] = rows[i] end
	end
	return data
end

local function first_enabled(data, want)
	want = clamp(want or 1, 1, #data)
	if not data[want].disabled then return want end
	for i = 1, #data do if not data[i].disabled then return i end end
	return want
end

-- redraw(sel): rebuild the list for the current level; sel defaults to the current selection
redraw = function(sel)
	if Screen == nil then return end
	local list = C.gget("List")
	if sel == nil then
		if Screen.data ~= nil then sel = list:get_selection() else sel = 1 end
	end
	Screen.data = screen_data()
	sel = first_enabled(Screen.data, sel)
	-- The list widens itself to fit long labels, but its own sum leaves out colour swatches; draw, measure,
	-- and draw again at the width the content needs, so the highlight bar spans every row.
	list:draw_items(Screen.data, sel, WIDTH)
	local w = list_content_width(list)
	if w > WIDTH then list:draw_items(Screen.data, sel, w) end
	-- the background panel and its mask are sized from this width: a panel narrower than the list cuts rows
	local panel = clamp((list.width or w) + PANEL_PAD, WIDTH, MAX_WIDTH)
	local header = C.gget("Header_obj")
	if header ~= nil then
		header:set_text(C.upper(Screen.title), panel - PANEL_PAD)	-- the header font has capitals only
		if Screen.panel ~= panel then		-- re-styling replays the panel's slide, so only when it changes
			menu_common_set_list_style(list, header, panel)
			Screen.panel = panel
		end
	end
	local hints = C.gget("Menu_hint_bar")
	if hints ~= nil then hints:set_hints({ { CTRL_MENU_BUTTON_B, "MENU_BACK" } }) end
	if Screen.mouse ~= nil then
		Screen.mouse:remove_all()
		list:add_mouse_inputs("modui_menu", Screen.mouse)
		if hints ~= nil then hints:add_mouse_inputs("modui_menu", Screen.mouse) end
		Screen.mouse:subscribe(true)
	end
	if Screen.level == "color" then Screen.ed:attach(list, 1) end
end

-- go(level, back): switch level; going back restores that level's last selection
local function go(level, back)
	local list = C.gget("List")
	Screen.sel[Screen.level] = list:get_selection()
	Screen.level = level
	if not back then Screen.sel[level] = 1 end
	redraw(Screen.sel[level] or 1)
end

local function leave_screen(pops)
	local list = C.gget("List")
	Screen.input:subscribe(false)
	if Screen.mouse ~= nil then Screen.mouse:subscribe(false) end
	if pops == 1 then
		list:button_b()
		menu_common_stack_remove()
		menu_common_transition_pop(1)
	else
		menu_common_set_screen_data(list, C.gget("Header_obj"), Screen.input, C.gget("Screen_back_out_anim"), C.gget("Screen_out_anim"))
		menu_common_transition_pop(pops)
		bg_saints_slide_out()
	end
end

-- a value row changed through the list (arrows, drag, click)
local function row_changed(idx)
	local it = Screen.data[idx]
	if it == nil then return end
	if Screen.level == "color" then
		if it.type == TYPE_SLIDER then Screen.ed:changed() end
		return
	end
	local w = it._w
	if w == nil then return end
	local v
	if w.kind == "toggle" then v = it.current_value == 2
	elseif w.kind == "choice" then v = it.current_value
	elseif w.kind == "slider" then v = w.min + it.current_value * w.step
	else return end
	if v == w.value then return end
	store(w, v)
	notify(w, v)
end

function modui_menu_nav_up() C.gget("List"):move_cursor(-1) end
function modui_menu_nav_down() C.gget("List"):move_cursor(1) end
function modui_menu_nav_left()
	local list = C.gget("List")
	list:move_slider(-1, nil, true)
	row_changed(list:get_selection())
end
function modui_menu_nav_right()
	local list = C.gget("List")
	list:move_slider(1, nil, true)
	row_changed(list:get_selection())
end

function modui_menu_button_a()
	if Screen == nil then return end
	local list = C.gget("List")
	local idx = list:get_selection()
	local it = Screen.data[idx]
	if it == nil or it.disabled then return end
	if Screen.level == "pages" then
		Screen.page = it._page
		sync_c_pages()
		if Screen.page.open_fn ~= nil then
			local ok, err = C.pcall(Screen.page.open_fn, Screen.page)
			if not ok then M.log("ERROR in on_open of " .. Screen.page.id .. ": " .. str(err)) end
		end
		go("page")
		game_UI_audio_play("UI_Main_Menu_Select")
	elseif Screen.level == "color" then
		if it.type == TYPE_TOGGLE_COLOR then		-- keep
			local w = Screen.color
			local v = M.rgb_pack(Screen.ed:get())
			store(w, v)
			if not w.live or w.c then notify(w, v) end
			game_UI_audio_play("UI_Main_Menu_Select")
			Screen.color = nil
			go("page", true)
		end
	else
		local w = it._w
		if w.kind == "button" then
			game_UI_audio_play("UI_Main_Menu_Select")
			notify(w, 1)
		elseif w.kind == "toggle" or w.kind == "choice" then
			list:move_slider(1)
			row_changed(idx)
		elseif w.kind == "color" then
			local r, g, b = M.rgb_unpack(w.value)
			Screen.color, Screen.prev = w, w.value
			Screen.ed = Hsl.new{ r = r, g = g, b = b, on_change = function(nr, ng, nb)
				if w.live then
					local v = M.rgb_pack(nr, ng, nb)
					store(w, v)
					notify(w, v)
				end
			end }
			go("color")
			game_UI_audio_play("UI_Main_Menu_Select")
		end
	end
end

function modui_menu_button_b()
	if Screen == nil then return end
	if Screen.level == "color" then
		local w = Screen.color
		if w.live and w.value ~= Screen.prev then	-- put the old colour back
			store(w, Screen.prev)
			notify(w, Screen.prev)
		end
		Screen.color = nil
		game_UI_audio_play("UI_Main_Menu_Nav_Back")
		go("page", true)
	elseif Screen.level == "page" then
		Screen.page = nil
		game_UI_audio_play("UI_Main_Menu_Nav_Back")
		go("pages", true)
	else
		leave_screen(1)
	end
end

function modui_menu_button_start()
	if Screen == nil then return end
	leave_screen(3)		-- this screen, pause_menu_top, pause_menu_top's parent
end

function modui_menu_mouse_click(event, target, mouse_x, mouse_y)
	if Screen == nil then return end
	local list = C.gget("List")
	local hints = C.gget("Menu_hint_bar")
	if hints ~= nil and hints:get_hint_index(target) == 1 then
		modui_menu_button_b()
		return
	end
	local idx = list:get_button_index(target)
	if idx ~= 0 then
		list:set_selection(idx)
		local it = Screen.data[idx]
		if it ~= nil and it.type ~= TYPE_SLIDER then modui_menu_button_a() end
	end
	if list:is_left_arrow(target) then
		list:move_slider(-1)
		row_changed(list:get_selection())
	elseif list:is_right_arrow(target) then
		list:move_slider(1)
		row_changed(list:get_selection())
	end
	if list:is_slider(target) then
		list:move_slider(0, mouse_x)
		row_changed(list:get_selection())
	end
end

function modui_menu_mouse_move(event, target)
	if Screen == nil then return end
	local list = C.gget("List")
	local hints = C.gget("Menu_hint_bar")
	if hints ~= nil then
		hints:set_highlight(0)
		local hi = hints:get_hint_index(target)
		if hi ~= 0 then hints:set_highlight(hi) end
	end
	local idx = list:get_button_index(target)
	if idx ~= 0 then
		list:set_selection(idx)
		list:move_cursor(0, true)
	end
end

function modui_menu_mouse_drag(event, target, mouse_x, mouse_y)
	if Screen == nil then return end
	local list = C.gget("List")
	if list:is_slider(target) then
		list:move_slider(0, mouse_x)
		row_changed(list:get_selection())
	end
end

function modui_menu_mouse_drag_release() end

function modui_menu_mouse_scroll(event, target, value)
	if Screen == nil then return end
	local list = C.gget("List")
	if list.scroll_list ~= nil then list:scroll_list(value * -1) end
	if Screen.mouse ~= nil then list:update_mouse_inputs("modui_menu", Screen.mouse) end
end

local function open_screen()
	Screen = { level = "pages", sel = {} }
	local input = Vdo_input_tracker:new()
	input:add_input("select", "modui_menu_button_a", 50)
	input:add_input("back", "modui_menu_button_b", 50)
	input:add_input("nav_up", "modui_menu_nav_up", 50)
	input:add_input("nav_down", "modui_menu_nav_down", 50)
	input:add_input("nav_left", "modui_menu_nav_left", 50)
	input:add_input("nav_right", "modui_menu_nav_right", 50)
	input:add_input("pause", "modui_menu_button_start", 50)
	input:subscribe(false)
	Screen.input = input
	if game_get_platform() == "PC" then Screen.mouse = Vdo_input_tracker:new() end
	sync_c_pages()
	redraw()			-- also sizes the panel
	local list = C.gget("List")
	bg_saints_show(true)
	menu_common_set_screen_data(list, C.gget("Header_obj"), input, C.gget("Screen_back_out_anim"), C.gget("Screen_slide_out_anim"))
	-- input is switched on by menu_common_anim_in_cb when the slide-in finishes; the options screen
	-- leaves that to the same callback, so do as it does
end

-- the options document hosts the MODS screen when we asked for it
M.wrap("pause_options_menu_init", function(orig, ...)
	if not Want_screen then return orig(...) end
	Want_screen = false
	local ok, err = C.pcall(open_screen)
	if not ok then
		M.log("ERROR opening the MODS screen: " .. str(err))
		Screen = nil
		return orig(...)
	end
end)

M.wrap("pause_options_menu_cleanup", function(orig, ...)
	if Screen == nil then return orig(...) end
	Screen.input:subscribe(false)
	if Screen.mouse ~= nil then Screen.mouse:subscribe(false) end
	C.gget("List"):enable_toggle_input(false)
	Screen = nil
end)

-- the MODS entry in the pause menu, before Quit
M.wrap("pause_menu_top_init", function(orig, ...)
	local list = C.gget("List")
	if list == nil then return orig(...) end
	local real, own = list.draw_items, rawget(list, "draw_items")
	list.draw_items = function(self, data, sel, width, a, b, c)
		self.draw_items = own
		local at = #data + 1
		for i = 1, #data do
			if data[i].label == "HORDE_MODE_MENU_EXIT" then at = i end
		end
		for i = #data, at, -1 do data[i + 1] = data[i] end
		data[at] = { type = TYPE_BUTTON, label = "MODS", id = ID_MODS }
		-- coming back from the MODS screen: select it again (the stack holds its id)
		if Menu_common_stack ~= nil and Menu_common_stack[Menu_common_stack.current_stack] == ID_MODS then sel = at
		elseif type(sel) == "number" and sel >= at then sel = sel + 1 end
		return real(self, data, sel, width, a, b, c)
	end
	local r1, r2 = orig(...)
	list.draw_items = own
	return r1, r2
end)

M.wrap("pause_menu_top_button_a", function(orig, ...)
	local list = C.gget("List")
	if list ~= nil and list:get_id() == ID_MODS then
		menu_common_stack_add(ID_MODS)
		Want_screen = true
		menu_common_transition_push("pause_options_menu")
		list:button_a()
		return
	end
	return orig(...)
end)

-------------------------------------------------------------------------------------------------------
-- extending the game's own screens: rows appended to Options > Display, Audio, Gameplay, ...
--
--   local p = ModUI.extend("display", "moreopts_display", { heading = "MORE OPTIONS" })
--   p:toggle("fxaa", "Extra smoothing", false, function(on) end)   -- the same widgets as a page
--   ModUI.modify("display", function(data) ... end)                 -- edit the game's own rows
--
-- Rows go at the END of the screen: the game's scripts address some rows by index, and an insert in the
-- middle would shift them. While a screen initialises we learn which handler functions it registers
-- (Vdo_input_tracker:add_input, List:add_mouse_inputs) and route input on our rows to us; every other
-- row stays the game's. Colour rows are not supported here (they need the MODS screen's editor).
-------------------------------------------------------------------------------------------------------
M.screens = {
	pause = "pause_menu_top", options = "pause_options_menu", display = "pause_options_display_pc",
	audio = "pause_options_audio", gameplay = "pause_options_difficulty", controls = "pause_options_controls",
	mouse = "pause_options_mouse",
}
local Ext = {}			-- screen -> { pages, modifiers, handlers = { func_name = input }, prefix, active }
local Ext_wrapped = {}	-- handler names already routed
local ID_EXT = 7800

local function ext_rows_present(e)
	for i = 1, #e.pages do
		for j = 1, #e.pages[i].widgets do
			if e.pages[i].widgets[j].kind ~= "color" then return true end
		end
	end
	return false
end

-- strip our previous rows, let mods edit the game's rows, then append ours
local function ext_fill(e, data)
	local n = #data
	local k = 0
	for i = 1, n do
		local it = data[i]
		if not (type(it) == "table" and it._ext) then
			k = k + 1
			data[k] = it
		end
	end
	for i = k + 1, n do data[i] = nil end
	for i = 1, #e.modifiers do
		local ok, err = C.pcall(e.modifiers[i], data)
		if not ok then M.log("ERROR in ModUI.modify(" .. e.screen .. "): " .. str(err)) end
	end
	local id = ID_EXT
	for i = 1, #e.pages do
		local p = e.pages[i]
		if p.heading ~= nil and #p.widgets > 0 then
			data[#data + 1] = { type = TYPE_BUTTON, label = p.heading, disabled = true, _ext = true, id = id, tool_tip_text = "" }
			id = id + 1
		end
		for j = 1, #p.widgets do
			local w = p.widgets[j]
			if w.kind ~= "color" then
				local it = row_for(w)
				it._ext = true
				it.id = id
				it.tool_tip_text = w.tip or ""
				data[#data + 1] = it
				id = id + 1
			end
		end
	end
end

local function ext_selected()
	local list = C.gget("List")
	if list == nil or list.data == nil then return nil end
	local it = list.data[list:get_selection()]
	if type(it) == "table" and it._ext and it._w ~= nil then return it, list end
	return nil
end

local function ext_changed(it)
	local w = it._w
	local v
	if w.kind == "toggle" then v = it.current_value == 2
	elseif w.kind == "choice" then v = it.current_value
	elseif w.kind == "slider" then v = w.min + it.current_value * w.step
	else return end
	if v == w.value then return end
	store(w, v)
	notify(w, v)
end

local function ext_select(it, list)
	local w = it._w
	if w.kind == "button" then
		game_UI_audio_play("UI_Main_Menu_Select")
		notify(w, 1)
	elseif w.kind == "toggle" or w.kind == "choice" then
		list:move_slider(1)
		ext_changed(it)
	end
end

local function ext_move(it, list, dir)
	if it.type == TYPE_SLIDER or it.type == TYPE_TOGGLE then
		list:move_slider(dir)
		ext_changed(it)
	end
end

-- route the screen's own handlers: our rows to us, everything else to the game
local function ext_route(e)
	for fname, input in pairs(e.handlers) do
		if not Ext_wrapped[fname] then
			if input == "select" then
				Ext_wrapped[fname] = true
				M.wrap(fname, function(orig, ...)
					local it, list = ext_selected()
					if it ~= nil then ext_select(it, list) return end
					return orig(...)
				end)
			elseif input == "nav_left" or input == "nav_right" then
				Ext_wrapped[fname] = true
				local dir = -1
				if input == "nav_right" then dir = 1 end
				M.wrap(fname, function(orig, ...)
					local it, list = ext_selected()
					if it ~= nil then ext_move(it, list, dir) return end
					return orig(...)
				end)
			end
		end
	end
	local prefix = e.prefix
	if prefix == nil then return end
	-- the list subscribes these by name for slider rows; a screen without sliders may not define them
	local names = { "_mouse_click", "_mouse_move", "_mouse_drag", "_mouse_drag_release" }
	for i = 1, #names do
		if C.gget(prefix .. names[i]) == nil then C.gset(prefix .. names[i], function() end) end
	end
	local click = prefix .. "_mouse_click"
	if not Ext_wrapped[click] then
		Ext_wrapped[click] = true
		M.wrap(click, function(orig, event, target, x, y)
			local list = C.gget("List")
			if list ~= nil and list.data ~= nil then
				local idx = list:get_button_index(target)
				if idx ~= 0 then
					local it = list.data[idx]
					if type(it) == "table" and it._ext and it._w ~= nil then
						list:set_selection(idx)
						list:move_cursor(0, true)
						if it.type ~= TYPE_SLIDER then ext_select(it, list) end
						return
					end
				else
					local it = ext_selected()
					if it ~= nil then
						if list:is_left_arrow(target) then ext_move(it, list, -1) return end
						if list:is_right_arrow(target) then ext_move(it, list, 1) return end
						if list:is_slider(target) then
							list:move_slider(0, x)
							ext_changed(it)
							return
						end
					end
				end
			end
			return orig(event, target, x, y)
		end)
	end
	local drag = prefix .. "_mouse_drag"
	if not Ext_wrapped[drag] then
		Ext_wrapped[drag] = true
		M.wrap(drag, function(orig, event, target, x, y)
			local it, list = ext_selected()
			if it ~= nil and list:is_slider(target) then
				list:move_slider(0, x)
				ext_changed(it)
				return
			end
			return orig(event, target, x, y)
		end)
	end
end

local function ext_install(screen, e)
	M.wrap(screen .. "_init", function(orig, ...)
		-- the MODS screen borrows the options document; leave that one alone
		if screen == "pause_options_menu" and Want_screen then return orig(...) end
		local list = C.gget("List")
		local tracker = C.gget("Vdo_input_tracker")
		if list == nil or tracker == nil or not ext_rows_present(e) and #e.modifiers == 0 then return orig(...) end

		-- rows: every draw of this screen's list (it redraws on presets, reverts, ...) gets ours appended
		if not (e.active and rawget(list, "draw_items") == e.draw) then
			local real, own = list.draw_items, rawget(list, "draw_items")
			e.own_draw = own
			e.draw = function(self, data, sel, width, a, b, c)
				if e.active and type(data) == "table" then ext_fill(e, data) end
				return real(self, data, sel, width, a, b, c)
			end
			list.draw_items = e.draw
		end
		e.active = true

		-- learn the handler names, and widen the panel to our rows, while the screen sets itself up
		local add_input = rawget(tracker, "add_input")
		tracker.add_input = function(self, input, fname, a, b, c)
			if type(fname) == "string" then e.handlers[fname] = input end
			return add_input(self, input, fname, a, b, c)
		end
		local own_mouse = rawget(list, "add_mouse_inputs")
		local add_mouse = list.add_mouse_inputs
		list.add_mouse_inputs = function(self, prefix, a, b, c, d, f, g)
			if type(prefix) == "string" then e.prefix = prefix end
			return add_mouse(self, prefix, a, b, c, d, f, g)
		end
		local style = C.gget("menu_common_set_list_style")
		if type(style) == "function" then
			C.gset("menu_common_set_list_style", function(l, h, w, a, b)
				if type(w) == "number" and type(l) == "table" and type(l.width) == "number" then
					local need = l.width + PANEL_PAD
					if need > w then w = clamp(need, w, MAX_WIDTH) end
				end
				return style(l, h, w, a, b)
			end)
		end

		local ok, r1, r2 = C.pcall(orig, ...)

		tracker.add_input = add_input
		list.add_mouse_inputs = own_mouse
		if type(style) == "function" then C.gset("menu_common_set_list_style", style) end
		ext_route(e)
		if not ok then M.log("ERROR in " .. screen .. "_init: " .. str(r1)) end
		return r1, r2
	end)

	M.wrap(screen .. "_cleanup", function(orig, ...)
		local r1, r2 = orig(...)
		if e.active then
			e.active = false
			local list = C.gget("List")
			if list ~= nil and rawget(list, "draw_items") == e.draw then list.draw_items = e.own_draw end
		end
		return r1, r2
	end)
end

local function ext_for(screen)
	local e = Ext[screen]
	if e == nil then
		e = { screen = screen, pages = {}, modifiers = {}, handlers = {} }
		Ext[screen] = e
		ext_install(screen, e)
	end
	return e
end

-- ModUI.extend(screen, id, opts) -> a page whose rows are appended to a game screen.
--   screen: a key of ModUI.screens ("display", "audio", "gameplay", "controls", "mouse", "options", "pause")
--           or a document name. opts.heading: a greyed row above yours; opts.list_in_mods: also in MODS.
function M.extend(screen, id, opts)
	screen = M.screens[screen] or screen
	local p = M.page(id, (opts ~= nil and opts.title) or id)
	if p == nil then return nil end
	p.hidden = not (opts ~= nil and opts.list_in_mods)
	if opts ~= nil and opts.heading ~= nil then p.heading = opts.heading end
	p.attached = screen
	local e = ext_for(screen)
	local have = false
	for i = 1, #e.pages do if e.pages[i] == p then have = true end end
	if not have then e.pages[#e.pages + 1] = p end
	return p
end

-- ModUI.modify(screen, fn): fn(data) before every draw of that screen, with the game's own rows
-- (labels, options, min/max/step, disabled, tool_tip_text). Changing what a row MEANS is up to your mod:
-- the game's scripts still apply the row's value as before.
function M.modify(screen, fn)
	screen = M.screens[screen] or screen
	local e = ext_for(screen)
	e.modifiers[#e.modifiers + 1] = fn
end

-- tooltip text for a widget on screens that show one (Display)
function Page:tip(key, text)
	local w = self.by_key[key]
	if w ~= nil then w.tip = text end
end

function M._booted()
	sync_c_pages()
	sort_pages()
	M.log("ModUI ready: " .. #Pages .. " page(s)")
end
