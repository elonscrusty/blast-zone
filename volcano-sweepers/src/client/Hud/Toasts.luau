--!strict
-- Toasts: short messages in a small stack, newest on top, 3 seconds each, slide in and fade out.
-- The same message twice just refreshes. Where they sit is decided by UiMath.layout: the empty
-- top-right corner in landscape, under the banner in portrait, never over the character (so they
-- never hide the lava circles a child must dodge). Slightly see-through, two short lines max.
-- While a panel is open Hud.toast sends messages into the panel instead (PanelHost.notify).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Ui.Format)
local UiMath = require(Shared.Ui.UiMath)
local Components = require(script.Parent.Parent.Ui.Components)
local Theme = require(script.Parent.Parent.Ui.Theme)
local Context = require(script.Parent.Context)
local Widget = require(script.Parent.Widget)

local Toasts = {}

export type ToastsWidget = Widget.Widget & {
	push: (text: string, kind: string?) -> (),
	setMax: (count: number) -> (),
}

type Entry = {
	frame: CanvasGroup,
	text: string,
	kind: string,
	token: number,
	alive: boolean,
}

local ICONS: { [string]: string } = {
	info = "💬",
	good = "✔️",
	warn = "⚠️",
	gold = "⭐",
}

local MAX_CHARS = 64 -- characters, not bytes (Format.clip never cuts an emoji in half)
local STEP = UiMath.K.toastH + UiMath.K.toastGap
local SEE_THROUGH = 0.15 -- the world shows a little through a toast

function Toasts.new(parent: Instance, _ctx: Context.Context): ToastsWidget
	local root = Instance.new("Frame")
	root.Name = "Toasts"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(300, STEP * 3)
	root.Parent = parent

	local entries: { Entry } = {} -- newest first
	local maxVisible = UiMath.K.toastCap
	local destroyed = false

	local function restack()
		for i, e in entries do
			Components.tween(
				e.frame,
				{ Position = UDim2.fromOffset(0, (i - 1) * STEP) },
				Theme.ease.normal
			)
		end
	end

	local function remove(e: Entry, instant: boolean)
		if not e.alive then
			return
		end
		e.alive = false
		local i = table.find(entries, e)
		if i then
			table.remove(entries, i)
		end
		if instant then
			e.frame:Destroy()
		else
			local pos = e.frame.Position
			local t = Components.tween(e.frame, {
				GroupTransparency = 1,
				Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset - 8),
			}, Theme.ease.normal)
			t.Completed:Connect(function()
				e.frame:Destroy()
			end)
		end
		restack()
	end

	local function arm(e: Entry)
		e.token += 1
		local mine = e.token
		task.delay(Theme.duration.toast, function()
			if not destroyed and e.alive and e.token == mine then
				remove(e, false)
			end
		end)
	end

	local function push(text: string, kind: string?)
		if destroyed or type(text) ~= "string" or text == "" then
			return
		end
		local k = if kind ~= nil and Theme.kind[kind] ~= nil then kind else "info"
		text = Format.clip(text, MAX_CHARS)
		for _, e in entries do
			if e.text == text and e.kind == k then
				arm(e)
				Components.punch(e.frame, 0.04)
				return
			end
		end

		local look = Theme.kind[k]
		local frame = Instance.new("CanvasGroup")
		frame.Name = "Toast"
		frame.Size = UDim2.new(1, 0, 0, UiMath.K.toastH)
		frame.Position = UDim2.fromOffset(0, -14)
		frame.BackgroundColor3 = look.fill
		frame.BackgroundTransparency = SEE_THROUGH
		frame.BorderSizePixel = 0
		frame.GroupTransparency = 1
		frame.Parent = root
		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.radius.md
		corner.Parent = frame
		local rim = Instance.new("UIStroke")
		rim.Color = look.accent
		rim.Thickness = 2
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = frame

		Components.Label({
			parent = frame,
			name = "Icon",
			text = ICONS[k] or "",
			textSize = Theme.text.icon,
			position = UDim2.fromOffset(6, 0),
			size = UDim2.new(0, 24, 1, 0),
		})
		Components.Label({
			parent = frame,
			name = "Text",
			text = text,
			textSize = Theme.text.small,
			font = Theme.font.bold,
			color = look.text,
			wrap = true, -- up to two lines, so long messages stay big instead of shrinking
			position = UDim2.fromOffset(34, 2),
			size = UDim2.new(1, -42, 1, -4),
			align = Enum.TextXAlignment.Left,
		})

		local e: Entry = { frame = frame, text = text, kind = k, token = 0, alive = true }
		table.insert(entries, 1, e)
		-- too many: drop the oldest straight away
		while #entries > maxVisible do
			remove(entries[#entries], true)
		end
		Components.tween(frame, { GroupTransparency = 0 }, Theme.ease.normal)
		restack()
		arm(e)
	end

	return {
		root = root,
		push = push,
		setMax = function(count: number)
			maxVisible = math.clamp(math.floor(count), 1, UiMath.K.toastCap)
			while #entries > maxVisible do
				remove(entries[#entries], true)
			end
		end,
		destroy = function()
			destroyed = true
			root:Destroy()
		end,
	}
end

return Toasts
