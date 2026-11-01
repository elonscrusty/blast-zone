--!strict
-- One helper bot's body: the Part-built model from Shared/Models/HelperBots (carter's pick, the B
-- Roller Bot; A Bumble and C Ember are skins). Only the see-through Root is anchored; every other
-- part is welded to it and weightless, so moving the bot is one CFrame change and costs the network
-- one assembly. The bot's level only changes its trim colour (bronze, silver, gold, volcano).
-- Every client turns the "Spin*" parts and bobs the "Bob*" parts itself (client/Vfx/BotAnim), so
-- the server never streams those little moves.
--
--   BotModel.build(level) -> Model            PrimaryPart = Root, facing -Z (like a character).
--                                             Its pivot sits PIVOT_UP above the ground under it, so
--                                             PivotTo(a point at HelperRules.hoverHeight) puts the
--                                             wheels on the ground.
--   BotModel.tierOf(level) -> string          rebuild when this changes (the trim colour)
--   BotModel.floatLabel(model) -> TextLabel?  the "+12" label over the bot (starts invisible)
--   BotModel.HOVERS                           true when the look floats (A Bumble): only then
--                                             should the whole body bob

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HelperRules = require(Shared.Player.HelperRules)
local BotSpecs = require(Shared.Models.BotSpecs)
local HelperBots = require(Shared.Models.HelperBots)

local BotModel = {}

BotModel.LOOK = HelperBots.defaultLook
BotModel.HOVERS = BotModel.LOOK == "A"
-- height of the pivot above the ground under the bot (the old round bot's centre height)
BotModel.PIVOT_UP = HelperRules.hoverHeight - Config.World.groundY

local LABEL_HEIGHT = 5.3 -- studs above the ground: clear of the Roller's antenna bulb (about 4.1)
local FLOAT_GOLD = Color3.fromRGB(255, 215, 64)
local LABEL_STROKE = Color3.fromRGB(40, 36, 52)

function BotModel.tierOf(level: number): string
	return BotSpecs.tierName(level)
end

function BotModel.build(level: number): Model
	local model = HelperBots.build(BotModel.LOOK, level, { lite = true }) -- 25 parts: 60 bots on a phone
	model.Name = "HelperBot"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- a bot streams in whole, never half
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true -- a welded model falls unless its Root is held
	root.PivotOffset = CFrame.new(0, BotModel.PIVOT_UP, 0)

	-- "+12" label over the head
	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatGui"
	gui.Adornee = root
	gui.Size = UDim2.fromOffset(140, 44)
	gui.StudsOffset = Vector3.new(0, LABEL_HEIGHT, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	label.TextColor3 = FLOAT_GOLD
	label.TextStrokeColor3 = LABEL_STROKE
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = gui
	gui.Parent = root

	return model
end

function BotModel.floatLabel(model: Model): TextLabel?
	local root = model.PrimaryPart
	local gui = root and root:FindFirstChild("FloatGui")
	local label = gui and gui:FindFirstChild("Label")
	if label ~= nil and label:IsA("TextLabel") then
		return label
	end
	return nil
end

return BotModel
