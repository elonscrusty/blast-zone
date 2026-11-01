--!strict
-- Island clean bar (top centre): how clean the whole island is (bar + % on the right), milestone
-- ticks at 25/50/75%, and on the left the zone you stand in with ITS clean % (from the server's
-- `Progress` remote; parties fire per zone, so this is the number a child can push up right here).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Ui.Format)
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local CleanBar = {}

local MILESTONES = { 0.25, 0.5, 0.75 }
local SPARKLE_GAP = 0.45 -- seconds between sparkles

local function zoneName(id: number): string
	for _, zone in Config.World.zones do
		if zone.id == id then
			return zone.name
		end
	end
	return ""
end

function CleanBar.new(parent: Instance, ctx: Context.Context): Widget.Widget
	local root = Instance.new("Frame")
	root.Name = "CleanBar"
	root.BackgroundColor3 = Theme.glass.color
	root.BackgroundTransparency = Theme.glass.transparency
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(300, UiMath.K.cleanH)
	root.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.radius.md
	corner.Parent = root
	local rim = Instance.new("UIStroke")
	rim.Color = Theme.glass.strokeColor
	rim.Transparency = Theme.glass.strokeTransparency
	rim.Thickness = 1.5
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = root

	local nameLabel = Components.Label({
		parent = root,
		name = "Zone",
		text = "",
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.white,
		align = Enum.TextXAlignment.Left,
		position = UDim2.fromOffset(10, 3),
		size = UDim2.new(1, -70, 0, 15),
	})
	local percentLabel = Components.Label({
		parent = root,
		name = "Percent",
		text = "0%",
		textSize = Theme.text.small,
		font = Theme.font.title,
		color = Theme.color.goldLight,
		align = Enum.TextXAlignment.Right,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, -10, 0, 3),
		size = UDim2.fromOffset(56, 15),
	})
	local bar = Components.Bar({
		parent = root,
		name = "Bar",
		position = UDim2.fromOffset(8, 21),
		size = UDim2.new(1, -16, 0, 12),
		fill = Theme.color.green,
		ticks = MILESTONES,
	})

	local value = 0
	local first = true
	local lastSparkle = 0
	local zoneId = 0
	local zoneClean: { [string]: number } = {}

	local function paintZone()
		local name = zoneName(zoneId)
		local f = zoneClean[tostring(zoneId)]
		nameLabel.Text = if f ~= nil then `{name} {Format.percent(f)}` else name
	end

	local function sparkle()
		local now = os.clock()
		if now - lastSparkle < SPARKLE_GAP then
			return
		end
		lastSparkle = now
		for i = 1, 2 do
			local star = Instance.new("TextLabel")
			star.Name = "Sparkle"
			star.BackgroundTransparency = 1
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Position = UDim2.new(value, (i - 1.5) * 8, 0.5, 0)
			star.Size = UDim2.fromOffset(16, 16)
			star.Font = Theme.font.title
			star.Text = "✨"
			star.TextSize = Theme.text.small
			star.TextColor3 = if i == 1 then Theme.color.goldLight else Theme.color.white
			star.ZIndex = 8
			star.Active = false
			star.Parent = bar.root
			local t = Components.tween(star, {
				Position = UDim2.new(value, (i - 1.5) * 14, -0.9, -4 * i),
				TextTransparency = 1,
				Rotation = 90 * i,
			}, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
			t.Completed:Connect(function()
				star:Destroy()
			end)
		end
	end

	local function refresh()
		local v = ctx.view().cleanTotal
		if type(v) ~= "number" or v ~= v then
			return
		end
		local new = UiMath.barFill(v)
		local rose = new > value + 0.0005
		value = new
		bar.set(new, not first)
		percentLabel.Text = Format.percent(new)
		for i, m in MILESTONES do
			bar.markTick(i, new >= m)
		end
		percentLabel.TextColor3 = if new >= 0.9999 then Theme.color.gold else Theme.color.goldLight
		if rose and not first then
			sparkle()
			bar.flash()
		end
		first = false
	end

	local function pollZone()
		local player = Players.LocalPlayer
		local char = if player then player.Character else nil
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if hrp == nil or not hrp:IsA("BasePart") then
			return
		end
		local id = UiMath.zoneAt(hrp.Position.X, hrp.Position.Z, Config.World.zones)
		if id ~= zoneId then
			zoneId = id
			paintZone()
		end
	end

	ctx.listen("Progress", function(payload: any)
		if type(payload) ~= "table" or type(payload.zones) ~= "table" then
			return
		end
		for key, f in payload.zones do
			if type(key) == "string" and type(f) == "number" and f == f then
				zoneClean[key] = UiMath.barFill(f)
			end
		end
		paintZone()
	end)

	zoneId = 1
	paintZone()
	ctx.every(0.25, pollZone)
	ctx.watch({ "cleanTotal" }, refresh)

	return {
		root = root,
		destroy = function()
			root:Destroy()
		end,
	}
end

return CleanBar
