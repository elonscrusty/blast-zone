--!strict
-- Gamepad menu focus. Starts itself (any "...System" module does).
--   * In combat nothing is focused, so A is always Slide and the sticks always move and aim.
--   * In menus (lobby, results, bots banner, settings) the cursor starts on the same button every
--     time, the D-pad and left stick go only where a button really lies, and A presses it.
--   * Settings sits on top of everything: while it is open, game input is off (Controls.setModal),
--     B closes it, and L1 / R1 or the left stick nudge the slider the cursor is on.
--   * Select opens settings from anywhere. L1 / R1 flip spectate targets.
-- It only reads other pieces' screens by name; they do not need to know about it.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Parent.Core.Net)
local Settings = require(script.Parent.Parent.Settings.Settings)
local SettingsModel = require(script.Parent.Parent.Settings.SettingsModel)
local SettingsPanel = require(script.Parent.Parent.Settings.SettingsPanel)
local Bindings = require(script.Parent.Bindings)
local Controls = require(script.Parent.Controls)
local FocusMap = require(script.Parent.FocusMap)

local UiFocusSystem = {}
UiFocusSystem.order = 300 -- after the screens it looks at

local POLL_SECONDS = 0.15
local STICK_NUDGE = 0.6 -- left stick pushed this far sideways nudges a slider
local STICK_REPEAT = 0.15 -- seconds between nudges while it stays pushed

-- Screens that can hold focus. `modal` ones own it while they have a visible button.
local SCREENS: { { name: string, modal: boolean } } = {
	{ name = "Settings", modal = true },
	{ name = "MatchFlow", modal = false },
	{ name = "BotBanner", modal = false },
}

local ids: { [GuiButton]: string } = setmetatable({}, { __mode = "k" }) :: any
local nextId = 0
local objs: { [string]: GuiButton } = {}

local function idOf(button: GuiButton): string
	local id = ids[button]
	if id == nil then
		nextId += 1
		id = "b" .. nextId
		ids[button] = id
	end
	return id
end

local function shown(obj: GuiObject, gui: ScreenGui): boolean
	local current: Instance? = obj
	while current ~= nil and current ~= gui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function priorityOf(button: GuiButton): number
	if button:GetAttribute("SliderKey") ~= nil or button.Name == "Toggle" then
		return 1 -- settings: start on the first setting, not on DONE
	elseif button.Name == "Play" then
		return 10
	end
	return 0
end

local function collect(playerGui: Instance): { FocusMap.Scope }
	local scopes: { FocusMap.Scope } = {}
	objs = {}
	for _, spec in SCREENS do
		local items: { FocusMap.Item } = {}
		local gui = playerGui:FindFirstChild(spec.name)
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			for _, d in gui:GetDescendants() do
				if
					d:IsA("GuiButton")
					and d.Name ~= "Dim" -- the full-screen "tap outside to close" layer
					and d.Selectable
					and (d.Active or d:GetAttribute("SliderKey") ~= nil)
					and d.AbsoluteSize.X > 0
					and d.AbsoluteSize.Y > 0
					and shown(d, gui)
				then
					local id = idOf(d)
					objs[id] = d
					table.insert(items, {
						id = id,
						x = d.AbsolutePosition.X,
						y = d.AbsolutePosition.Y,
						w = d.AbsoluteSize.X,
						h = d.AbsoluteSize.Y,
						priority = priorityOf(d),
					})
				end
			end
		end
		table.insert(scopes, { name = spec.name, modal = spec.modal, items = items })
	end
	return scopes
end

local function selectedButton(): GuiButton?
	local selected = GuiService.SelectedObject
	if selected ~= nil and selected:IsA("GuiButton") and ids[selected] ~= nil then
		return selected
	end
	return nil
end

local function applyLinks(items: { FocusMap.Item })
	for id, link in FocusMap.links(items) do
		local obj = objs[id]
		if obj then
			local left, right, up, down =
				objs[link.left], objs[link.right], objs[link.up], objs[link.down]
			if obj.NextSelectionLeft ~= left then
				obj.NextSelectionLeft = left
			end
			if obj.NextSelectionRight ~= right then
				obj.NextSelectionRight = right
			end
			if obj.NextSelectionUp ~= up then
				obj.NextSelectionUp = up
			end
			if obj.NextSelectionDown ~= down then
				obj.NextSelectionDown = down
			end
		end
	end
end

local function poll(playerGui: Instance)
	local scopes = collect(playerGui)
	local modal = FocusMap.hasModal(scopes)
	Controls.setModal(modal) -- settings open: no running, firing or sliding underneath

	local wantFocus = Controls.device() == "gamepad" and (modal or not Controls.isEnabled())
	local items = if wantFocus then FocusMap.active(scopes) else {}
	local current = selectedButton()
	local currentId = if current then ids[current] else nil

	local target = FocusMap.settle(items, currentId)
	if target == nil then
		if current ~= nil then
			GuiService.SelectedObject = nil -- back in combat: A must slide, not press a button
		end
		return
	end
	applyLinks(items)
	if target ~= currentId then
		GuiService.SelectedObject = objs[target]
	end
end

local function nudgeSelected(direction: number)
	local selected = selectedButton()
	local key = if selected then selected:GetAttribute("SliderKey") else nil
	if type(key) ~= "string" then
		return
	end
	local value = SettingsModel.nudge(key, Settings.number(key), direction)
	if value ~= nil then
		Settings.set(key, value)
	end
end

local function spectating(playerGui: Instance): boolean
	local gui = playerGui:FindFirstChild("Spectate")
	return gui ~= nil and gui:IsA("ScreenGui") and gui.Enabled and not Controls.isEnabled()
end

function UiFocusSystem.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	GuiService.AutoSelectGuiEnabled = false -- we choose what is focused, Roblox does not

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= POLL_SECONDS then
			elapsed = 0
			poll(playerGui)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if string.sub(input.UserInputType.Name, 1, 7) ~= "Gamepad" then
			return
		end
		local code = input.KeyCode.Name
		if code == Bindings.menu.settings then
			SettingsPanel.toggle()
		elseif code == Bindings.menu.back then
			if SettingsPanel.isOpen() then
				SettingsPanel.toggle()
			end
		elseif code == Bindings.menu.sliderLess or code == Bindings.menu.sliderMore then
			if SettingsPanel.isOpen() then
				nudgeSelected(if code == Bindings.menu.sliderMore then 1 else -1)
			elseif spectating(playerGui) then
				Net.send("SpectateCycle", if code == Bindings.menu.spectateNext then 1 else -1)
			end
		end
	end)

	local lastStick = 0
	UserInputService.InputChanged:Connect(function(input: InputObject, _processed: boolean)
		if input.KeyCode ~= Enum.KeyCode.Thumbstick1 or not SettingsPanel.isOpen() then
			return
		end
		local x = input.Position.X
		if math.abs(x) >= STICK_NUDGE and os.clock() - lastStick >= STICK_REPEAT then
			lastStick = os.clock()
			nudgeSelected(if x > 0 then 1 else -1)
		end
	end)
end

return UiFocusSystem
