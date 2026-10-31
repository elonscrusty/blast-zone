--!strict
-- Piece 19 on the client: stepping on a pad in the lobby does that pad's job, and a LOADOUT button does the
-- same for phones that would rather tap.
--   LOADOUT pad   -> the loadout screen            (this piece; button in lobby slot "loadout")
--   PLAY pad      -> PlayRequest, same as piece 05's PLAY button (the server decides; nothing new)
--   SETTINGS pad  -> SettingsPanel.toggle()        (piece 10)
--   REWARDS pad   -> the Rewards screen            (piece 18, if it is there)
-- Walking onto a pad fires once; step off and back on to fire again. Nothing here changes game state
-- by itself: every pad only opens a screen or asks the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LobbyLayout = require(Shared.LobbyLayout)
local Look = require(script.Parent.Parent.Ui.Look)
local MatchPhase = require(Shared.MatchPhase)
local Signal = require(Shared.Signal)

local Net = require(script.Parent.Parent.Core.Net)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local Controller = require(script.Parent.LoadoutController)
local LoadoutPanel = require(script.Parent.LoadoutPanel)

local LobbyClientSystem = {}
LobbyClientSystem.order = 60

-- Other pieces can listen too, for example a sound when you step on a pad. (stationId)
LobbyClientSystem.StationUsed = Signal.new()

local COOLDOWN = 0.8
local CHECK_EVERY = 0.1

local phase: string = MatchPhase.Waiting
local current: string? = nil -- the pad we are standing on
local lastFired = 0

local function optionalModule(folderName: string, moduleName: string): any?
	local folder = script.Parent.Parent:FindFirstChild(folderName)
	local module = if folder then folder:FindFirstChild(moduleName) else nil
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			return result
		end
	end
	return nil
end

local function use(station: string)
	LobbyClientSystem.StationUsed:fire(station)
	if station == "loadout" then
		LoadoutPanel.open()
	elseif station == "play" then
		if phase == MatchPhase.Waiting then
			Net.send("PlayRequest")
		end
	elseif station == "settings" then
		local panel = optionalModule("Settings", "SettingsPanel")
		if panel and panel.toggle then
			panel.toggle()
		end
	elseif station == "rewards" then
		local panel = optionalModule("Progression", "TrackPanel")
		if panel and panel.toggle then
			panel.toggle()
		end
	end
end

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- The LOADOUT button lives in the lobby menu slot "loadout" (shown only in the lobby by the match screen).
local function makeButton()
	local b = Instance.new("TextButton")
	b.Name = "Loadout"
	b.Text = "LOADOUT"
	b.Font = Look.font("body")
	b.TextScaled = true
	b.TextColor3 = Look.color("ink")
	b.BackgroundColor3 = Look.color("panel")
	b.Size = UDim2.fromScale(1, 1)
	b.Parent = LobbyMenu.slot("loadout")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = Look.color("outline")
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	b.Activated:Connect(function()
		use("loadout")
	end)
end

function LobbyClientSystem.start()
	Controller.start()
	makeButton()

	Net.on("MatchState", function(state: any)
		if type(state) == "table" and type(state.phase) == "string" then
			phase = state.phase
		end
	end)

	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck < CHECK_EVERY then
			return
		end
		sinceCheck = 0
		local pos = rootPosition()
		local inLobby = pos ~= nil and LobbyLayout.contains(pos.X, pos.Z, 4)
		if not inLobby or not pos then
			current = nil
			if LoadoutPanel.isOpen() and phase ~= MatchPhase.Waiting then
				LoadoutPanel.close()
			end
			return
		end
		local station = LobbyLayout.stationAt(pos.X, pos.Z)
		if station ~= current then
			current = station
			if station and os.clock() - lastFired >= COOLDOWN then
				lastFired = os.clock()
				use(station)
			end
		end
	end)
end

return LobbyClientSystem
