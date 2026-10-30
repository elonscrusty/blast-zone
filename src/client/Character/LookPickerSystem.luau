--!strict
-- Three big touch buttons (Runner, Courier, Spark) along the bottom while no fight is on, so you can try
-- each fighter. The server decides (SetLookRequest); this only draws the buttons and asks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Looks = require(Shared.Character.Looks)
local MatchPhase = require(Shared.MatchPhase)
local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)

local LookPickerSystem = {}

local localPlayer = Players.LocalPlayer

-- Left column of the lobby (the "looks" group in Ui/LobbyLayout): three rows of 52 points.
local RECT = { x = 56, y = 160, w = 104, h = 152 }
local ROW_H = 48
local ROW_GAP = 4

-- Phases where a body is not in a fight: the buttons show only here.
local CALM = {
	[MatchPhase.Waiting] = true,
	[MatchPhase.Countdown] = true,
	[MatchPhase.Results] = true,
	[MatchPhase.Resetting] = true,
}

function LookPickerSystem.start()
	local gui, root = Components.screen("LookPicker", "Calm")

	local column = Components.piece(root, "Column", RECT)

	local buttons: { [string]: TextButton } = {}
	local function paint()
		local worn = localPlayer:GetAttribute(Config.Character.lookAttribute)
		if type(worn) ~= "string" then
			worn = Config.Character.defaultLook
		end
		for name, button in buttons do
			Components.restyle(button, if name == worn then "good" else "secondary")
		end
	end

	for i, name in Looks.NAMES do
		local button = Components.button(
			column,
			root,
			name,
			{ text = string.upper(name), style = "secondary" }
		)
		button.Size = UDim2.fromScale(1, ROW_H / RECT.h)
		button.Position = UDim2.fromScale(0, (i - 1) * (ROW_H + ROW_GAP) / RECT.h)
		button.Activated:Connect(function()
			Net.send("SetLookRequest", name)
		end)
		buttons[name] = button
	end

	localPlayer:GetAttributeChangedSignal(Config.Character.lookAttribute):Connect(paint)
	paint()

	Net.on("MatchState", function(state: any)
		if type(state) == "table" then
			gui.Enabled = CALM[state.phase] == true
		end
	end)
end

return LookPickerSystem
