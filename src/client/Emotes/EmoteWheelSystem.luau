--!strict
-- The lobby emote button (piece 29): a round ★ EMOTE button at the bottom right, phone first. Tap it and four
-- bubbles fan out; a fifth small bubble flips to the next set (Street, Hype, Chill), and the last page picks your
-- winner pose. Locked emotes (only with Config.Emotes.trackUnlocks) show a lock and the track tier that opens them. Keyboard: B opens it, 1-4 play. Gamepad: ButtonY opens it, then the bubbles are selectable.
-- This only ASKS (EmoteRequest); the server checks the unlock and the phase. Walking off stops your emote.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EmoteRules = require(Shared.Character.EmoteRules)
local Emotes = require(Shared.Character.Emotes)
local MatchPhase = require(Shared.MatchPhase)
local RemoteDefs = require(Shared.RemoteDefs)
local Net = require(script.Parent.Parent.Core.Net)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)

local EmoteWheelSystem = {}
EmoteWheelSystem.order = 220

local tuning = Config.Emotes
local localPlayer = Players.LocalPlayer

local NAVY = Color3.fromHex(Config.Palette.Navy)
local CYAN = Color3.fromHex(Config.Palette.Cyan)
local GOLD = Color3.fromHex(Config.Palette.RewardGold)
local WHITE = Color3.fromRGB(243, 241, 234)
local LOCKED = Color3.fromRGB(204, 211, 220)
local LOCKED_INK = Color3.fromRGB(59, 70, 86)

local BUTTON = 72 -- points; touch minimum is 48
local BUBBLE = 58
-- Bubble centres, in points from the button's centre (an arc up and to the left, clear of the screen edge).
local ARC = {
	Vector2.new(-92, 6),
	Vector2.new(-82, -62),
	Vector2.new(-30, -108),
	Vector2.new(34, -118),
}
local MORE_AT = Vector2.new(-124, -112)

-- Only while nobody fights; the look picker (piece 11) uses the same calm phases minus results.
local CALM = {
	[MatchPhase.Waiting] = true,
	[MatchPhase.Countdown] = true,
}

local function corner(obj: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = obj
end

local function stroke(obj: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Parent = obj
end

local function round(parent: Instance, name: string, size: number, centre: Vector2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(1, centre.X - BUTTON / 2, 1, centre.Y - BUTTON / 2)
	b.Size = UDim2.fromOffset(size, size)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 12
	b.TextWrapped = true
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Parent = parent
	corner(b, UDim.new(0.5, 0))
	return b
end

function EmoteWheelSystem.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteWheel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.Popups
	gui.Enabled = false

	-- Bottom right, inside a 16 point gutter. Everything else is placed from the button's centre.
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -16, 1, -16)
	holder.Size = UDim2.fromOffset(BUTTON, BUTTON)
	holder.Parent = gui

	local main = round(holder, "Emote", BUTTON, Vector2.zero)
	main.BackgroundColor3 = NAVY
	main.TextColor3 = GOLD
	main.Text = "★\nEMOTE"
	main.TextSize = 13
	stroke(main, WHITE, 4)

	local bubbles: { TextButton } = {}
	for i, at in ARC do
		local b = round(holder, "Bubble" .. i, BUBBLE, at)
		b.Visible = false
		stroke(b, CYAN, 3)
		bubbles[i] = b
	end
	local more = round(holder, "NextSet", 46, MORE_AT)
	more.Visible = false
	more.BackgroundColor3 = NAVY
	more.TextColor3 = WHITE
	more.TextSize = 11
	stroke(more, GOLD, 3)

	local phase = MatchPhase.Waiting
	local open = false
	local page = 1
	local tiers = 0
	local playing = false
	local scheme: EmoteRules.Scheme =
		{ starterSet = tuning.starterSet, trackUnlocks = tuning.trackUnlocks }

	-- One page per emote set (4 bubbles), then one page of winner poses (3 bubbles).
	type Item = { id: string, label: string, owned: boolean, tier: number, picked: boolean }
	type Page = { title: string, items: { Item } }
	local pages: { Page } = {}

	local function build()
		pages = {}
		for _, e in EmoteRules.list(scheme, tiers) do
			local last = pages[#pages]
			if last == nil or #last.items >= #ARC then
				last = { title = Emotes.SET_NAMES[e.set], items = {} }
				table.insert(pages, last)
			end
			table.insert(
				last.items,
				{ id = e.id, label = e.name, owned = e.owned, tier = e.tier, picked = false }
			)
		end
		local mine = EmoteRules.winPoseOr(
			localPlayer:GetAttribute(tuning.winPoseAttribute),
			tuning.defaultWinPose
		)
		local wins: Page = { title = "Win", items = {} }
		for _, key in Emotes.SETS do
			table.insert(wins.items, {
				id = EmoteRules.WIN_PREFIX .. key,
				label = Emotes.WIN_NAMES[key],
				owned = true,
				tier = 0,
				picked = key == mine,
			})
		end
		table.insert(pages, wins)
	end

	local function paint()
		build()
		page = math.clamp(page, 1, #pages)
		local items = pages[page].items
		for i, b in bubbles do
			local e = items[i]
			b.Visible = open and e ~= nil
			if e ~= nil then
				b.Text = if not e.owned
					then `🔒\n{e.label}\nTier {e.tier}`
					elseif e.picked then `✓\n{e.label}`
					else e.label
				b.TextSize = if e.owned then 12 else 10
				b.BackgroundColor3 = if not e.owned then LOCKED elseif e.picked then GOLD else WHITE
				b.TextColor3 = if e.owned then NAVY else LOCKED_INK
			end
		end
		local nextPage = page % #pages + 1
		more.Visible = open and #pages > 1
		more.Text = `{pages[nextPage].title} ›`
		main.BackgroundColor3 = if open then CYAN else NAVY
		main.TextColor3 = if open then NAVY else GOLD
	end

	local function setOpen(on: boolean)
		open = on
		paint()
	end

	local function playSlot(i: number)
		local e = pages[page] and pages[page].items[i]
		if e == nil or not e.owned then
			return
		end
		Net.send("EmoteRequest", e.id)
		if EmoteRules.winPoseFrom(e.id) ~= nil then
			return -- picking a winner pose keeps the wheel open; the tick shows once the server agrees
		end
		playing = true
		setOpen(false)
	end

	local function refresh()
		gui.Enabled = CALM[phase] == true
		if not gui.Enabled and open then
			setOpen(false)
		end
	end

	main.Activated:Connect(function()
		setOpen(not open)
	end)
	more.Activated:Connect(function()
		page = page % #pages + 1
		paint()
	end)
	for i, b in bubbles do
		b.Activated:Connect(function()
			playSlot(i)
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.B or key == Enum.KeyCode.ButtonY then
			setOpen(not open)
			if open and input.UserInputType == Enum.UserInputType.Gamepad1 then
				GuiService.SelectedObject = bubbles[1]
			end
		elseif open then
			local slot = if key == Enum.KeyCode.One
				then 1
				elseif key == Enum.KeyCode.Two then 2
				elseif key == Enum.KeyCode.Three then 3
				elseif key == Enum.KeyCode.Four then 4
				else nil
			if slot ~= nil then
				playSlot(slot)
			end
		end
	end)

	-- Walking off ends your own emote (the server also ends it after a few seconds).
	RunService.Heartbeat:Connect(function()
		if not playing then
			return
		end
		local character = localPlayer.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if character == nil or character:GetAttribute(tuning.attribute) == nil then
			playing = false
			return
		end
		if root ~= nil and root:IsA("BasePart") then
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > tuning.stopMoveSpeed then
				playing = false
				Net.send("EmoteRequest", EmoteRules.STOP)
			end
		end
	end)

	Net.on("MatchState", function(p: any)
		if type(p) == "table" and type(p.phase) == "string" then
			phase = p.phase
			refresh()
		end
	end)
	-- Piece 18 tells us our track progress; until it does, only the free emotes are open.
	Net.on("ProgressState", function(p: any)
		if type(p) == "table" and type(p.unlocked) == "table" then
			tiers = EmoteRules.tiersOwnedFromList(p.unlocked)
			paint()
		end
	end)

	localPlayer:GetAttributeChangedSignal(tuning.winPoseAttribute):Connect(paint)

	paint()
	refresh()
	if RemoteDefs.byName.ProgressRequest ~= nil then
		Net.send("ProgressRequest") -- in case our state went out before this listener was up
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

return EmoteWheelSystem
