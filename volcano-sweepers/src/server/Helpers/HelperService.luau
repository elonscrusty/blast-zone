--!strict
-- Helper bots. Each player owns profile.helpers bots (0..6). A bot is a small Model that floats
-- behind its owner in a loose fan; once a second it takes ash off the ground nearby and pays the
-- OWNER coins straight away (never the backpack). All the rules (rates, which cells, pay, formation,
-- the 60-body cap) are in Shared/Player/HelperRules; this file only moves Models and reads state.
--
--   HelperService.init()
--   HelperService.refresh(player)   rebuild/repaint this player's bots now (after Cool Down)
--   HelperService.visibleCount()    bot bodies in the world right now
--
-- Bots beyond the server cap (HelperRules.MAX_VISIBLE) have no body but still sweep and pay.
-- Buying a bot, a Cool Down or a new tool needs no call: the loop notices the profile changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AshGrid = require(Shared.Ash.AshGrid)
local Config = require(Shared.Config)
local Tools = require(Shared.Catalog.Tools)
local HelperRules = require(Shared.Player.HelperRules)
local Rng = require(Shared.Rng)

local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local BotModel = require(script.Parent.BotModel)

local TICK = 0.05 -- seconds between movement steps (20 Hz keeps the follow smooth)
local SWEEP_SECONDS = 1 -- each bot sweeps once a second
local FOLDER_NAME = "VSHelpers"
local FALLBACK_COLOR = "#A9805B"

type Bot = {
	index: number,
	model: Model?,
	label: TextLabel?,
	pos: Vector3,
	carry: number, -- fraction of an ash unit not swept yet
	pending: number, -- fraction of a coin not paid yet
	sweepAcc: number,
	lastFloat: number,
	floatCoins: number,
}

type Owner = {
	player: Player,
	bots: { Bot },
	colorHex: string,
	look: Vector3,
	snap: boolean, -- bots jump next to the owner on the next step (respawn)
	charConn: RBXScriptConnection?,
}

local HelperService = {}

local started = false
local owners: { [Player]: Owner } = {}
local rng = Rng.new(os.time() + math.floor(os.clock() * 1000))
local gridCache: AshGrid.AshGrid? = nil
local ashModule: any = nil -- AshService, once found (for noteSwept)
local gridTriedAt = -100
local visible = 0
local lastWarnAt = -100

local function ashGrid(): AshGrid.AshGrid?
	if gridCache ~= nil then
		return gridCache
	end
	local now = os.clock()
	if now - gridTriedAt < 5 then
		return nil -- AshService may not be up yet (or is broken): look again in a few seconds
	end
	gridTriedAt = now
	local server = script.Parent and script.Parent.Parent
	local folder = server and server:FindFirstChild("Ash")
	local module = folder and folder:FindFirstChild("AshService")
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, service = pcall(require, module)
	if ok and type(service) == "table" then
		local grid = (service :: any).grid
		if type(grid) == "table" then
			gridCache = grid :: AshGrid.AshGrid
			ashModule = service
		end
	end
	return gridCache
end

local function folder(): Folder
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	return f
end

local function toolColor(toolId: string): string
	local tool = Tools.byId[toolId]
	return if tool ~= nil then tool.color else FALLBACK_COLOR
end

local function setVisible(owner: Owner, bot: Bot, want: boolean)
	if want and bot.model == nil then
		local model = BotModel.build(owner.colorHex)
		model.Name = `HelperBot{bot.index}`
		model:SetAttribute("OwnerUserId", owner.player.UserId)
		model:PivotTo(CFrame.lookAt(bot.pos, bot.pos + owner.look))
		model.Parent = folder()
		bot.model = model
		bot.label = BotModel.floatLabel(model)
		visible += 1
	elseif not want and bot.model ~= nil then
		bot.model:Destroy()
		bot.model = nil
		bot.label = nil
		visible -= 1
	end
end

local function removeBot(owner: Owner, bot: Bot)
	setVisible(owner, bot, false)
end

local function removeOwner(player: Player)
	local owner = owners[player]
	if owner == nil then
		return
	end
	owners[player] = nil
	if owner.charConn ~= nil then
		owner.charConn:Disconnect()
	end
	for _, bot in owner.bots do
		removeBot(owner, bot)
	end
	owner.bots = {}
end

local function ensureOwner(player: Player, state: PlayerState.State): Owner
	local owner = owners[player]
	if owner ~= nil then
		return owner
	end
	local created: Owner = {
		player = player,
		bots = {},
		colorHex = toolColor(state.profile.tool),
		look = Vector3.new(0, 0, -1),
		snap = true,
		charConn = nil,
	}
	created.charConn = player.CharacterAdded:Connect(function()
		created.snap = true -- a respawn: the bots catch up at once
	end)
	owners[player] = created
	return created
end

-- Bring the number of bots and their colour in line with the profile.
local function reconcile(owner: Owner, state: PlayerState.State)
	local want = math.clamp(math.floor(state.profile.helpers), 0, Config.Economy.maxHelpers)
	local bots = owner.bots
	while #bots > want do
		local bot = table.remove(bots) :: Bot
		removeBot(owner, bot)
	end
	while #bots < want do
		local n = #bots + 1
		table.insert(bots, {
			index = n,
			model = nil,
			label = nil,
			pos = Vector3.new(0, HelperRules.hoverHeight, 0),
			carry = 0,
			pending = 0,
			sweepAcc = (n - 1) / math.max(1, want), -- spread the 1 s sweeps over the second
			lastFloat = -10,
			floatCoins = 0,
		})
		owner.snap = true
	end
	local hex = toolColor(state.profile.tool)
	if hex ~= owner.colorHex then
		owner.colorHex = hex
		for _, bot in bots do
			if bot.model ~= nil then
				BotModel.setColor(bot.model, hex)
			end
		end
	end
end

local function showFloat(bot: Bot, now: number)
	local label = bot.label
	if label == nil then
		bot.floatCoins = 0
		return
	end
	label.Text = HelperRules.floatText(bot.floatCoins)
	bot.floatCoins = 0
	bot.lastFloat = now
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.4
	label.Position = UDim2.fromScale(0, 0.3)
	TweenService
		:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0, -0.2),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		:Play()
end

-- One bot's sweep: ash off the ground, coins to the owner.
local function sweepBot(
	owner: Owner,
	state: PlayerState.State,
	bot: Bot,
	elapsed: number,
	now: number
)
	local grid = ashGrid()
	if grid == nil then
		return
	end
	local whole, carry = HelperRules.accrue(bot.carry, state.profile.helperLevel, elapsed)
	bot.carry = carry
	if whole > 0 then
		local allowed = HelperRules.allowedZones(state.profile.zones)
		local result = HelperRules.sweepAround(grid, bot.pos.X, bot.pos.Z, whole, allowed, rng)
		if result.units > 0 then
			-- bots count for the adaptive regrow too, so bot-heavy servers never starve players
			local mod = ashModule
			if mod ~= nil and type(mod.noteSwept) == "function" then
				pcall(mod.noteSwept, result.units)
			end
			bot.pending += HelperRules.coinsFor(
				result.valueUnits,
				state.derived.helperMult,
				state.derived.sellMult
			)
			local coins, rest = HelperRules.settle(bot.pending)
			bot.pending = rest
			if coins > 0 then
				PlayerState.addCoins(owner.player, coins)
				bot.floatCoins += coins
			end
		end
	end
	if bot.floatCoins >= 1 and HelperRules.canShowFloat(bot.lastFloat, now) then
		showFloat(bot, now)
	end
end

-- Move every bot toward its place beside the owner. Returns false when the owner has no live body.
local function follow(owner: Owner, dt: number, now: number): boolean
	local char = owner.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hrp == nil or not hrp:IsA("BasePart") or (hum ~= nil and hum.Health <= 0) then
		return false
	end
	local cf = hrp.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = owner.look
	else
		look = look.Unit
	end
	owner.look = look
	local right = look:Cross(Vector3.yAxis)
	local origin = Vector3.new(cf.Position.X, 0, cf.Position.Z)
	local alpha = HelperRules.followAlpha(dt)
	local count = #owner.bots
	for _, bot in owner.bots do
		local ox, oz = HelperRules.formationOffset(bot.index, count)
		local height = HelperRules.hoverHeight + HelperRules.bob(now, bot.index)
		local target = origin + right * ox - look * oz + Vector3.new(0, height, 0)
		local flat = Vector3.new(bot.pos.X - origin.X, 0, bot.pos.Z - origin.Z)
		if owner.snap or HelperRules.shouldTeleport(flat.Magnitude) then
			bot.pos = target
		else
			bot.pos = bot.pos:Lerp(target, alpha)
		end
		if bot.model ~= nil then
			bot.model:PivotTo(CFrame.lookAt(bot.pos, bot.pos + look))
		end
	end
	owner.snap = false
	return true
end

local function step(dt: number, now: number)
	-- who plays: ready players only
	local active: { Owner } = {}
	local states: { [Player]: PlayerState.State } = {}
	local seen: { [Player]: boolean } = {}
	for _, state in PlayerState.all() do
		local player = state.player
		if player.Parent == Players then
			seen[player] = true
			states[player] = state
			local owner = ensureOwner(player, state)
			reconcile(owner, state)
			table.insert(active, owner)
		end
	end
	for player in table.clone(owners) do
		if not seen[player] then
			removeOwner(player)
		end
	end

	-- how many bodies each owner gets (fair share of the server cap)
	table.sort(active, function(a: Owner, b: Owner): boolean
		return a.player.UserId < b.player.UserId
	end)
	local counts: { number } = {}
	for i, owner in active do
		counts[i] = #owner.bots
	end
	local shares = HelperRules.allocateVisible(counts, HelperRules.MAX_VISIBLE)

	for i, owner in active do
		local state = states[owner.player]
		follow(owner, dt, now)
		for _, bot in owner.bots do
			setVisible(owner, bot, bot.index <= shares[i])
			bot.sweepAcc += dt
			if bot.sweepAcc >= SWEEP_SECONDS then
				local elapsed = bot.sweepAcc
				bot.sweepAcc = 0
				sweepBot(owner, state, bot, elapsed, now)
			end
		end
	end
end

function HelperService.refresh(player: Player)
	local state = PlayerState.get(player)
	if state == nil then
		return
	end
	local owner = ensureOwner(player, state)
	reconcile(owner, state)
	owner.snap = true
end

function HelperService.visibleCount(): number
	return visible
end

function HelperService.init()
	if started then
		return
	end
	started = true
	folder()

	Players.PlayerRemoving:Connect(removeOwner)
	PlayerState.onLeaving:connect(removeOwner)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = math.min(now - last, 0.5)
			last = now
			local ok, err = pcall(step, dt, now)
			if not ok and now - lastWarnAt > 5 then
				lastWarnAt = now
				warn(`[Helpers] step failed: {err}`)
			end
		end
	end)
end

return HelperService
