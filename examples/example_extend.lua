-- Example: adding rows to the game's own option screens (SR3 Mod UI 2+).
-- Copy to <game>\SR3ModUI\mods\. Options > Display, Audio and Gameplay get extra rows at the end, and the
-- Options list gets a button. Values save to SR3ModUI.ini like any page.

local display = ModUI.extend("display", "example_display", { heading = "EXAMPLE EXTRAS" })
display:toggle("sharpen", "Example: sharpen", false, function(on) ModUI.log("example display: sharpen =", on) end)
display:tip("sharpen", "An example row added by a mod")
display:slider("lod", "Example: draw distance", 1, 3, 0.25, 1, function(v) ModUI.log("example display: lod =", v) end)
display:choice("fog", "Example: fog", { "Off", "Light", "Heavy" }, 2, function(i, name) ModUI.log("example display: fog =", name) end)

local audio = ModUI.extend("audio", "example_audio")
audio:slider("radio_vol", "Example: radio boost", 0, 100, 10, 50, function(v) ModUI.log("example audio: radio =", v) end)

local gameplay = ModUI.extend("gameplay", "example_gameplay")
gameplay:toggle("hardcore", "Example: hardcore", false, function(on) ModUI.log("example gameplay: hardcore =", on) end)

local options = ModUI.extend("options", "example_options")
options:button("hello", "Example: say hello", function() ModUI.log("example options: hello") end)

-- edit the game's own rows before they are drawn (here only a tooltip, which changes nothing it applies)
ModUI.modify("display", function(data)
	for i = 1, #data do
		if data[i].label == "MENU_VSYNC" then data[i].tool_tip_text = "VSYNC (tooltip set by a mod)" end
	end
end)
