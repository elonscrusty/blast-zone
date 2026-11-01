--!strict
-- Trade Posts: one small sell stall just inside the outer edge of each zone 2..5, beside that zone's
-- gate (WorldPlan.postSpots), so a kid sweeping deep in the island need not walk all the way back
-- to the Trade Hut. A post is the picked Toy Pop Trade Hut model drawn small (Wiring.POST_SCALE,
-- sign "TRADE POST") behind a glowing sell pad tagged `VSSellPad`; the hut's counter carries the
-- ProximityPrompt tagged `VSSellPrompt` (the same tags the hut uses, so SellService, the SELL button
-- and the coin pop already know it), and a tall flag in the zone's colour marks it from far away.
-- The ash layout keeps a clear circle around every post. About WorldPlan.postCost parts each.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

local Build = require(script.Parent.Models.Build)
local Wiring = require(script.Parent.Models.Wiring)
local WorldUtil = require(script.Parent.WorldUtil)

local TradePosts = {}

local P = WorldUtil.Palette
local V = Vector3.new

local PAD_RADIUS = 4.4
-- the counter prompt is short-range on purpose: from anywhere it fires, the player is well inside
-- Config.World.sellRange of this post's pad (the server judges selling by the pad)
local PROMPT_DISTANCE = 10

local function padLabel(part: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 46)
	gui.StudsOffset = V(0, 3.4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "SELL"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex(P.gold)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromHex("#7A3E12")
	label.Parent = gui
	gui.Parent = part
end

local function buildPost(folder: Instance, post: WorldPlan.Post)
	local accent = WorldUtil.zoneAccent[post.zoneId] or P.gold
	local origin = V(post.x, 0, post.z)
	-- looks inland (towards the volcano): local +Z is the outer side, where the stall stands
	local frame = CFrame.lookAt(origin, origin - V(post.ux, 0, post.uz))
	local model = Instance.new("Model")
	model.Name = `TradePost{post.zoneId}`

	-- the sell pad (what the server measures selling from)
	WorldUtil.disc(model, "SellPadBase", post.x, 0.25, post.z, PAD_RADIUS + 0.6, 0.25, "#FF9F1C")
	local pad = WorldUtil.disc(model, "SellPad", post.x, 0.4, post.z, PAD_RADIUS, 0.2, P.gold, {
		material = Enum.Material.Neon,
	})
	WorldUtil.tag(pad, "VSSellPad")
	padLabel(pad)

	-- the stall: the Toy Pop Trade Hut drawn small, its counter facing the pad
	local hutAt = frame * CFrame.new(0, 0, Wiring.postHutZ(post.counterA))
	local hut =
		Build.into(model, Wiring.kitSpec("TradeHut", 1, "TRADE POST"), hutAt, Wiring.POST_SCALE)
	hut.Name = "Stall"
	local counter = hut:FindFirstChild(Wiring.PART.counter)
	if counter == nil or not counter:IsA("BasePart") then
		error("the Trade Hut model has no Counter part")
	end

	-- a tall flag in the zone's colour to find the post from far away (on the side away from the gate)
	local poleBase = hutAt * CFrame.new(-7.6, 0, 2)
	WorldUtil.cylinder(
		model,
		"FlagPole",
		(poleBase * CFrame.new(0, 9, 0)).Position,
		0.5,
		18,
		P.woodDark
	)
	WorldUtil.block(model, "Flag", poleBase * CFrame.new(0, 16.4, -1.6), V(0.2, 2.4, 3.2), accent, {
		material = Enum.Material.Neon,
	})
	WorldUtil.ball(model, "FlagTop", (poleBase * CFrame.new(0, 18.3, 0)).Position, 1, P.gold, {
		material = Enum.Material.Neon,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Sell ash"
	prompt.ObjectText = "Trade Post"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	CollectionService:AddTag(prompt, "VSSellPrompt")
	prompt.Parent = counter

	model.Parent = folder
end

function TradePosts.build(root: Instance, plan: WorldPlan.Plan)
	local folder = Instance.new("Folder")
	folder.Name = "TradePosts"
	folder.Parent = root -- first: a post that fails to build never hides the others
	for _, post in plan.posts do
		local ok, err = pcall(buildPost, folder, post)
		if not ok then
			warn(`[TradePosts] post in zone {post.zoneId} failed: {err}`)
		end
	end
end

return TradePosts
