--!strict
-- Trade Posts: one small sell stall just inside the outer edge of each zone 2..5, beside that zone's
-- gate (WorldPlan.postSpots), so a kid sweeping deep in the island need not walk all the way back
-- to the Trade Hut. A post is a mini Trade Hut built from Parts: a glowing sell pad tagged
-- `VSSellPad`, a counter whose ProximityPrompt is tagged `VSSellPrompt` (the same tags the hut
-- uses, so SellService, the SELL button and the coin pop already know it), a striped awning, a
-- "TRADE POST" sign and a tall flag in the zone's colour to spot it from far away.
-- The ash layout keeps a clear circle around every post. About WorldPlan.postCost parts each.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldPlan = require(Shared.WorldPlan)

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
	-- looks inland (towards the volcano): local +Z is the outer side, where the counter stands
	local frame = CFrame.lookAt(origin, origin - V(post.ux, 0, post.uz))
	local function H(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local c = post.counterA
	local model = Instance.new("Model")
	model.Name = `TradePost{post.zoneId}`

	-- the sell pad (what the server measures selling from)
	WorldUtil.disc(model, "SellPadBase", post.x, 0.25, post.z, PAD_RADIUS + 0.6, 0.25, "#FF9F1C")
	local pad = WorldUtil.disc(model, "SellPad", post.x, 0.4, post.z, PAD_RADIUS, 0.2, P.gold, {
		material = Enum.Material.Neon,
	})
	WorldUtil.tag(pad, "VSSellPad")
	padLabel(pad)

	-- the stall: floor, counter, back wall, four posts, roof, striped awning
	local solid = { collide = true, shadow = true }
	WorldUtil.block(model, "Floor", H(0, 0.2, c + 0.8), V(11, 0.4, 5), P.wood)
	WorldUtil.block(model, "CounterBody", H(0, 1.7, c - 0.6), V(10, 2.6, 1.4), P.coral, solid)
	local counter =
		WorldUtil.block(model, "Counter", H(0, 3.15, c - 0.8), V(10.6, 0.3, 2.2), P.woodLight, {
			collide = true,
		})
	WorldUtil.block(model, "BackWall", H(0, 3.4, c + 2.6), V(10, 6, 0.5), P.cream, solid)
	for _, side in { -1, 1 } do
		for _, at in { c - 1.7, c + 2.6 } do
			WorldUtil.block(model, "StallPost", H(side * 5, 3.5, at), V(0.6, 7, 0.6), P.woodDark, {
				collide = true,
			})
		end
	end
	WorldUtil.block(
		model,
		"Roof",
		H(0, 7.2, c + 0.5) * CFrame.Angles(math.rad(8), 0, 0),
		V(11.4, 0.5, 6.4),
		P.teal,
		{ shadow = true }
	)
	for i = 0, 3 do
		local color = if i % 2 == 0 then P.red else P.white
		WorldUtil.block(
			model,
			"Awning",
			H(-4.2 + i * 2.8, 6.2, c - 2.6) * CFrame.Angles(-math.rad(22), 0, 0),
			V(2.8, 0.25, 2.2),
			color,
			{ shadow = true }
		)
	end
	WorldUtil.block(model, "RoofStrip", H(0, 6.85, c - 2.75), V(11.4, 0.25, 0.25), accent, {
		material = Enum.Material.Neon,
	})

	-- sign over the counter, readable from both sides
	WorldUtil.signBoard(
		model,
		"PostSign",
		H(0, 9.1, c - 1.2),
		V(8, 1.9, 0.35),
		P.sun,
		"#7A3E12",
		"TRADE POST"
	)

	-- a couple of ash sacks by the counter, and a tall flag to find the post from far away
	WorldUtil.ball(model, "Sack", H(-6.4, 1, c - 1).Position, 2, "#B9A48A")
	WorldUtil.ball(model, "Sack", H(-6.6, 0.9, c + 1).Position, 1.8, "#A8927A")
	local poleBase = H(6.6, 0, c + 2)
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
