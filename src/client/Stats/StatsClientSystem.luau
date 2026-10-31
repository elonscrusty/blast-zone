--!strict
-- Shows the player's own lifetime stats (piece 24). Only shows: the server counts and saves.
--   * Lobby card (top left, Street Sticker look): WINS / ELIMS / GAMES. Visible in Waiting and Countdown.
--   * The YOU row on the 3D top-wins board (this client's copy only).
--   * Hides the board (and its lights) for this client during a fight; spins trophies if the look has any (A).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Look = require(script.Parent.Parent.Ui.Look)
local StatsRules = require(Shared.Stats.StatsRules)
local BoardRules = require(Shared.Stats.BoardRules)
local Net = require(script.Parent.Parent.Core.Net)
local UiLayers = require(script.Parent.Parent.Ui.UiLayers)
local ScreenMap = require(script.Parent.Parent.Ui.ScreenMap)
local UiKit = require(script.Parent.Parent.Hud.UiKit)
local Layout = require(script.Parent.Parent.Hud.Layout)

local StatsClientSystem = {}
StatsClientSystem.order = 220

local player = Players.LocalPlayer

type Look = { panel: string, ink: string, outline: string, accent: string, strokeScale: number }

local function loadLook(): Look
	local hud = script.Parent.Parent:FindFirstChild("Hud")
	local module = if hud then hud:FindFirstChild("Theme") else nil
	if module and module:IsA("ModuleScript") then
		local ok, theme = pcall(require, module)
		if ok then
			return theme.get(nil)
		end
	end
	return {
		panel = Look.hex("panel"),
		ink = Look.hex("ink"),
		outline = Look.hex("outline"),
		accent = Look.hex("accent"),
		strokeScale = 0.0085,
	}
end

local look = loadLook()
local FONT = Look.font("display")

local stats: StatsRules.Stats = StatsRules.empty()
local phase: string? = nil

-- ===== lobby card =====
local gui: ScreenGui
local card: Frame
local values: { [string]: TextLabel } = {}

local function buildCard()
	gui = Instance.new("ScreenGui")
	gui.Name = "LobbyStats"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UiLayers.Calm -- under MatchFlow so the PLAY and SETTINGS buttons stay on top
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the same frame as every other lobby piece
	gui.Parent = player:WaitForChild("PlayerGui")

	card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Visible = false
	card.Parent = gui
	-- Placed from Ui/ScreenMap (under Roblox's menu and chat buttons, clear of the map vote), so it moves with them.
	UiKit.place(card, ScreenMap.statsCard, nil, Layout.LOBBY_MIN_ASPECT)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0.03, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card

	for i, spec in { { "wins", "WINS" }, { "eliminations", "ELIMS" }, { "matches", "GAMES" } } do
		local pill = Instance.new("Frame")
		pill.Name = spec[2]
		pill.LayoutOrder = i
		pill.Size = UDim2.fromScale(0.313, 1)
		pill.BackgroundColor3 = Color3.fromHex(if i == 1 then look.accent else look.panel)
		pill.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.22, 0)
		corner.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromHex(look.outline)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = pill
		local function thick()
			stroke.Thickness =
				math.max(2, math.floor(gui.AbsoluteSize.Y * look.strokeScale * 0.8 + 0.5))
		end
		thick()
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(thick)

		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		caption.Font = FONT
		caption.Text = spec[2]
		caption.TextScaled = true
		caption.TextColor3 = Color3.fromHex(look.ink)
		caption.TextTransparency = 0.25
		caption.Position = UDim2.fromScale(0.08, 0.08)
		caption.Size = UDim2.fromScale(0.84, 0.3)
		caption.Parent = pill

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.BackgroundTransparency = 1
		value.Font = FONT
		value.Text = "0"
		value.TextScaled = true
		value.TextColor3 = Color3.fromHex(look.ink)
		value.Position = UDim2.fromScale(0.08, 0.4)
		value.Size = UDim2.fromScale(0.84, 0.52)
		value.Parent = pill
		values[spec[1]] = value
	end
end

-- ===== board =====
local board: Model? = nil
local youLine: TextLabel? = nil
local trophies: { { model: Model, base: CFrame } } = {}
local boardShown = true

local function showBoard(visible: boolean)
	local m = board
	if m == nil or visible == boardShown then
		return
	end
	boardShown = visible
	for _, inst in m:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = if visible then 0 else 1
		elseif inst:IsA("SurfaceGui") or inst:IsA("Light") then
			inst.Enabled = visible
		end
	end
end

local function attachBoard(m: Model)
	board = m
	boardShown = true
	trophies = {}
	for _, child in m:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Spin") then
			table.insert(trophies, { model = child, base = child:GetPivot() })
		end
	end
	local line = m:FindFirstChild("YouLine", true)
	youLine = if line and line:IsA("TextLabel") then line else nil
end

local function refresh()
	for key, label in values do
		label.Text = BoardRules.short((stats :: any)[key])
	end
	card.Visible = StatsRules.cardVisible(phase)
	if youLine then
		youLine.Text = StatsRules.youLine(stats, BoardRules.short)
	end
	showBoard(StatsRules.boardVisible(phase))
end

function StatsClientSystem.start()
	buildCard()

	Net.on("StatsUpdate", function(payload: any)
		stats = StatsRules.read(payload)
		refresh()
	end)
	Net.on("MatchState", function(state: any)
		if type(state) == "table" and type(state.phase) == "string" then
			phase = state.phase
			refresh()
		end
	end)

	local name = Config.Stats.board.modelName
	local function watch(child: Instance)
		if child.Name == name and child:IsA("Model") then
			-- The board's parts stream in a moment after the model; wait for the YOU row.
			child:WaitForChild("Board", 10)
			attachBoard(child)
			refresh()
		end
	end
	workspace.ChildAdded:Connect(function(child)
		task.spawn(watch, child)
	end)
	local existing = workspace:FindFirstChild(name)
	if existing then
		task.spawn(watch, existing)
	end

	-- Spin the trophies only while the board is shown and the camera is near.
	local spin = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local m = board
		if m == nil or not boardShown or #trophies == 0 or m.Parent == nil then
			return
		end
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - trophies[1].base.Position).Magnitude > 160 then
			return
		end
		spin = (spin + dt * 1.2) % (math.pi * 2)
		for _, t in trophies do
			t.model:PivotTo(t.base * CFrame.Angles(0, spin, 0))
		end
	end)

	Net.send("StatsRequest")
	refresh()
end

return StatsClientSystem
