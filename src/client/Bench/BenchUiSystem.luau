--!strict
-- The bench screen (video 3 gap 14). PLACEHOLDER LOOK: built from Ui/Components roles only, so Claude Design's skin
-- restyles it. The server decides everything: this screen only shows BenchState and ASKS (BenchRequest, BenchMerge,
-- BenchBuild).
--   * BENCH button in the lobby slot "bench", opens a full panel (Components.modal: Modal layer + ModalGate).
--   * A green dot on the button when new parts dropped after a match.
--   * Parts list (each pile with MERGE when there are 3), plans list (needs, BUILD or BUILT), the drop odds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BenchDefs = require(Shared.Bench.BenchDefs)
local BenchText = require(Shared.Bench.BenchText)
local MatchPhase = require(Shared.MatchPhase)
local Types = require(Shared.Types)
local Net = require(script.Parent.Parent.Core.Net)
local Components = require(script.Parent.Parent.Ui.Components)
local LobbyMenu = require(script.Parent.Parent.Ui.LobbyMenu)
local Tokens = require(script.Parent.Parent.Ui.Tokens)

local BenchUiSystem = {}
BenchUiSystem.order = 227

local ROW_HEIGHT = 0.16 -- of the screen height

local function plural(n: number, word: string): string
	return if n == 1 then `1 {word}` else `{n} {word}s`
end

-- The line under the title after the server answered a request.
local function noticeFor(state: Types.BenchState): string
	if state.event == "denied" then
		return BenchText.reason(state.reason)
	elseif state.event == "merged" then
		return "Merged!"
	elseif state.event == "built" then
		return "Built!"
	elseif state.event == "dropped" and state.justGot ~= nil then
		return `New: {plural(#state.justGot, "part")}`
	end
	local words: { [string]: string } = {
		temporary = "Test mode: not saved",
		loading = "Loading...",
		failed = "Progress not loaded",
		lost = "Progress not loaded",
	}
	return words[state.status] or ""
end

function BenchUiSystem.start()
	local state: Types.BenchState? = nil
	local rebuild: () -> () = function() end

	local modal = Components.modal("Bench", "BENCH", nil)
	local root = modal.root

	-- ===== lobby button =====
	-- An empty, see-through screen: it only gives the button its sizing rules. The button itself lives in the slot.
	local _, slotRoot = Components.screen("BenchButtonHost", "MatchFlow")
	local button = Components.button(LobbyMenu.slot("bench"), slotRoot, "Bench", {
		text = "BENCH",
		style = "secondary",
		onPress = function()
			modal.open()
		end,
	})
	button.Size = UDim2.fromScale(1, 1)
	local dot = Instance.new("Frame")
	dot.Name = "NewDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(1, 0)
	dot.Size = UDim2.fromScale(0.3, 0.3)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = Color3.fromHex(Tokens.color("good"))
	dot.Visible = false
	dot.Parent = button

	-- ===== panel =====
	local notice = Components.text(modal.panel, root, "Notice", "caption", {
		color = "info",
		size = UDim2.fromScale(0.9, 0.06),
		position = UDim2.fromScale(0.5, 0.15),
		anchor = Vector2.new(0.5, 0),
	})
	local odds = Components.text(modal.panel, root, "Odds", "caption", {
		text = BenchText.odds(),
		color = "ink",
		size = UDim2.fromScale(0.9, 0.05),
		position = UDim2.fromScale(0.5, 0.78),
		anchor = Vector2.new(0.5, 0),
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = modal.body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local order = 0
	local function row(): Frame
		order += 1
		local f = Instance.new("Frame")
		f.Name = "Row" .. order
		f.LayoutOrder = order
		f.BackgroundTransparency = 1
		f.Size = UDim2.new(1, -10, 0, math.max(48, math.floor(root.AbsoluteSize.Y * ROW_HEIGHT)))
		f.Parent = list
		return f
	end
	local function heading(text: string)
		local f = row()
		Components.text(f, root, "Heading", "title", {
			text = text,
			color = "accent",
			align = Enum.TextXAlignment.Left,
		})
	end

	rebuild = function()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		order = 0
		local current = state
		if current == nil then
			notice.Text = ""
			return
		end
		notice.Text = noticeFor(current)

		heading("PARTS")
		if #current.parts == 0 then
			local f = row()
			Components.text(f, root, "Empty", "body", {
				text = "Play a match to get parts.",
				align = Enum.TextXAlignment.Left,
			})
		end
		for _, pile in current.parts do
			local f = row()
			Components.text(f, root, "Pile", "body", {
				text = BenchText.pile(pile.kind, pile.tier, pile.count),
				align = Enum.TextXAlignment.Left,
				size = UDim2.fromScale(0.6, 1),
			})
			if pile.canMerge then
				local merge = Components.button(f, root, "Merge", {
					text = `MERGE {BenchDefs.mergeCount}`,
					style = "primary",
					onPress = function()
						Net.send("BenchMerge", pile.kind, pile.tier)
					end,
				})
				merge.AnchorPoint = Vector2.new(1, 0.5)
				merge.Position = UDim2.fromScale(1, 0.5)
				merge.Size = UDim2.fromScale(0.36, 0.9)
			end
		end

		heading(`PLANS {current.built}/{current.total}`)
		for _, plan in current.blueprints do
			local f = row()
			local lines: { string } = {}
			for _, need in plan.needs do
				table.insert(lines, BenchText.need(need.kind, need.tier, need.have, need.count))
			end
			Components.text(f, root, "PlanName", "body", {
				text = `{plan.name} ({plan.slot})`,
				align = Enum.TextXAlignment.Left,
				size = UDim2.fromScale(0.6, 0.5),
			})
			Components.text(f, root, "PlanNeeds", "caption", {
				text = table.concat(lines, ", "),
				align = Enum.TextXAlignment.Left,
				position = UDim2.fromScale(0, 0.5),
				size = UDim2.fromScale(0.6, 0.5),
			})
			if plan.built then
				Components.text(f, root, "Built", "body", {
					text = "BUILT",
					color = "good",
					size = UDim2.fromScale(0.3, 1),
					position = UDim2.fromScale(0.7, 0),
				})
			else
				local build = Components.button(f, root, "Build", {
					text = "BUILD",
					style = if plan.ready then "primary" else "quiet",
					onPress = function()
						Net.send("BenchBuild", plan.id)
					end,
				})
				build.AnchorPoint = Vector2.new(1, 0.5)
				build.Position = UDim2.fromScale(1, 0.5)
				build.Size = UDim2.fromScale(0.36, 0.9)
			end
		end
	end

	Net.on("BenchState", function(incoming: Types.BenchState)
		state = incoming
		if incoming.event == "dropped" and not modal.isOpen() then
			dot.Visible = true
		end
		rebuild()
	end)

	-- Opening the panel clears the dot and asks for a fresh bench.
	modal.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if modal.gui.Enabled then
			dot.Visible = false
			Net.send("BenchRequest")
		end
	end)

	Net.on("MatchState", function(m: any)
		if m.phase ~= MatchPhase.Waiting then
			modal.close()
		end
	end)

	Net.send("BenchRequest")
end

return BenchUiSystem
