--!strict
-- Big call-out banners (piece 46): DOUBLE KILL, KILLING SPREE, CIRCLE CLOSING, SUDDEN DEATH.
-- The server sends a `Moment`; MomentRules says what it says; BannerQueue keeps it to one at a time.
-- This file only draws. The look is Ui/MomentStyles (colour roles from Ui/Tokens). Takes no taps.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BannerQueue = require(Shared.Moments.BannerQueue)
local MatchPhase = require(Shared.MatchPhase)
local MomentRules = require(Shared.Moments.MomentRules)

local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)
local MomentStyles = require(script.Parent.Parent.Ui.MomentStyles)
local Tokens = require(script.Parent.Parent.Ui.Tokens)
local Layout = require(script.Parent.Parent.Hud.Layout)
local UiKit = require(script.Parent.Parent.Hud.UiKit)

local MomentBannerSystem = {}
MomentBannerSystem.order = 210

local POP_IN = 0.18 -- seconds, the banner grows from small
local POP_OUT = 0.22 -- seconds, it shrinks away at the end

local function color(role: string): Color3
	return Color3.fromHex(Tokens.color(role))
end

type View = {
	holder: Frame,
	scale: UIScale,
	emblemBadge: Frame,
	emblem: TextLabel,
	title: TextLabel,
	subtitle: TextLabel,
	stripe: Frame,
}

local function build(root: Frame): View
	local style = MomentStyles.get(Config.Moments.style).banner
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.Visible = false
	holder.Parent = root
	UiKit.place(holder, Layout.regions.moment)
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local panel, shadow = Components.panel(holder, root, "Panel", style.fill)
	panel.Size = UDim2.fromScale(1, 1)
	panel.Active = false
	shadow.Active = false
	local rounding = panel:FindFirstChildOfClass("UICorner")
	if rounding then
		rounding.CornerRadius = UDim.new(style.corner, 0)
	end
	local shadowRounding = shadow:FindFirstChildOfClass("UICorner")
	if shadowRounding then
		shadowRounding.CornerRadius = UDim.new(style.corner, 0)
	end
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color(style.outline)
	end
	shadow.BackgroundColor3 = color(style.outline)

	-- the emblem: a short sign in a badge on the left ("x2", "x5", "!")
	local badge = Instance.new("Frame")
	badge.Name = "EmblemBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.fromScale(0.03, 0.5)
	badge.Size = UDim2.fromScale(0.15, 0.8)
	badge.BorderSizePixel = 0
	badge.Active = false
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = badge
	badge.Parent = panel
	UiKit.circle(badge)
	local emblem = Components.text(badge, root, "Emblem", "title", { color = "inkOnAccent" })
	emblem.Size = UDim2.fromScale(0.8, 0.6)
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	emblem.Position = UDim2.fromScale(0.5, 0.5)

	local title = Components.text(panel, root, "Title", "title", {
		color = style.ink,
		size = UDim2.fromScale(0.74, 0.58),
		position = UDim2.fromScale(0.2, 0.06),
		align = Enum.TextXAlignment.Left,
	})
	local subtitle = Components.text(panel, root, "Subtitle", "caption", {
		color = style.subtitleInk,
		size = UDim2.fromScale(0.74, 0.26),
		position = UDim2.fromScale(0.2, 0.64),
		align = Enum.TextXAlignment.Left,
	})

	local stripe = Instance.new("Frame")
	stripe.Name = "ToneStripe"
	stripe.AnchorPoint = Vector2.new(0.5, 1)
	stripe.Position = UDim2.fromScale(0.5, 1)
	stripe.Size = UDim2.fromScale(1, 0.07)
	stripe.BorderSizePixel = 0
	stripe.Active = false
	stripe.Visible = style.toneStripe
	stripe.Parent = panel

	return {
		holder = holder,
		scale = scale,
		emblemBadge = badge,
		emblem = emblem,
		title = title,
		subtitle = subtitle,
		stripe = stripe,
	}
end

local function fill(view: View, banner: MomentRules.Banner)
	local style = MomentStyles.get(Config.Moments.style).banner
	view.title.Text = banner.title
	view.subtitle.Text = banner.subtitle or ""
	view.subtitle.Visible = banner.subtitle ~= nil
	view.title.Size = if banner.subtitle ~= nil
		then UDim2.fromScale(0.74, 0.58)
		else UDim2.fromScale(0.74, 0.8)
	view.title.Position = if banner.subtitle ~= nil
		then UDim2.fromScale(0.2, 0.06)
		else UDim2.fromScale(0.2, 0.1)
	view.emblem.Text = banner.emblem
	local tone = color(banner.tone)
	view.emblemBadge.BackgroundColor3 = tone
	view.emblemBadge.BackgroundTransparency = if style.emblemFill then 0 else 1
	view.emblem.TextColor3 = if style.emblemFill then color("inkOnAccent") else tone
	view.stripe.BackgroundColor3 = tone
end

function MomentBannerSystem.start()
	if not Config.Moments.enabled then
		return
	end
	local _, root = Components.screen("MomentBanner", "Moments")
	local view = build(root)
	local queue = BannerQueue.new(Config.Moments)
	local localId = "p" .. Players.LocalPlayer.UserId

	Net.on("Moment", function(payload: any)
		local banner = MomentRules.banner(payload, localId, Config.Moments.maxNameLength)
		if banner ~= nil then
			BannerQueue.push(queue, banner, os.clock())
		end
	end)

	-- Old news is never shown after a match ends.
	Net.on("MatchState", function(state: any)
		local phase = if type(state) == "table" then state.phase else nil
		if
			phase == MatchPhase.Waiting
			or phase == MatchPhase.Finished
			or phase == MatchPhase.Results
			or phase == MatchPhase.Resetting
		then
			BannerQueue.clear(queue)
			view.holder.Visible = false
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local banner, fresh = BannerQueue.update(queue, now)
		if banner == nil then
			view.holder.Visible = false
			return
		end
		if fresh then
			fill(view, banner)
			view.holder.Visible = true
		end
		-- grow in, hold, shrink out
		local seconds = queue.endsAt - queue.startedAt
		local t = now - queue.startedAt
		local s = 1
		if t < POP_IN then
			s = 0.6 + 0.4 * (t / POP_IN)
		elseif t > seconds - POP_OUT then
			s = math.max(0, (seconds - t) / POP_OUT)
		end
		view.scale.Scale = s
	end)
end

return MomentBannerSystem
