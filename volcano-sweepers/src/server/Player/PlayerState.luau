--!strict
-- The one place that holds each player's live state: the saved Profile (from Profiles) plus
-- live fields (backpack, derived stats, buffs). EVERY change to coins/backpack/stats goes through
-- here so the client store and the save stay in step.
--
--   PlayerState.init()                       once, after Net.init() and Profiles.init()
--   PlayerState.get(player) -> State?        nil until the profile loaded AND the client said ClientReady
--   PlayerState.all() -> { State }           ready players only
--   PlayerState.onReady:connect(function(player, state) end)
--   PlayerState.onLeaving:connect(function(player) end)       fires before the state is dropped
--   PlayerState.touch(player, "coins", "carried")              mark View keys changed (sent at ~10 Hz)
--   PlayerState.addCoins / spendCoins / addCarried / dropCarried / takeCarried / addStat
--   PlayerState.recompute(player)            call after tool / upgrade / spark / set / zone changes
--   PlayerState.setBuff(id, endsAt)          island-wide buff ("party", "perfect"); recomputes everyone
--   PlayerState.setClean(total)              island clean fraction for the HUD
--   PlayerState.fullSync(player)             send the whole View (done automatically on ready)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local StatsCalc = require(Shared.Rules.StatsCalc)
local Types = require(Shared.Types)

local Net = require(script.Parent.Parent.Core.Net)
local Profiles = require(script.Parent.Parent.Profile.Profiles)

export type State = {
	player: Player,
	profile: Types.Profile,
	carried: number, -- units in the backpack
	carriedValue: number, -- coins-before-multipliers
	derived: StatsCalc.Full,
	clientReady: boolean,
	ready: boolean,
	dirty: { [string]: boolean },
	lastSweepAt: number, -- os.clock of last accepted swing
	lastHitAt: number,
	playSince: number,
}

local PlayerState = {}

PlayerState.onReady = Signal.new()
PlayerState.onLeaving = Signal.new()

local states: { [Player]: State } = {}
local buffs: { [string]: number } = {}
local cleanTotal = 0
local started = false

local SAVED_KEYS = {
	coins = true,
	runCoins = true,
	lifetimeCoins = true,
	sparks = true,
	coolDowns = true,
	tool = true,
	toolsOwned = true,
	upgrades = true,
	zones = true,
	helpers = true,
	helperLevel = true,
	sparkPerks = true,
	finds = true,
	setsClaimed = true,
	goalsClaimed = true,
	daily = true,
	stats = true,
	settings = true,
	tutorialDone = true,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function finite(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

-- Builds one View key's value from state.
local function valueOf(state: State, key: string): any
	if key == "carried" then
		return state.carried
	elseif key == "carriedValue" then
		return state.carriedValue
	elseif key == "derived" then
		return state.derived
	elseif key == "buffs" then
		return buffs
	elseif key == "cleanTotal" then
		return cleanTotal
	end
	return (state.profile :: any)[key]
end

local function flush(state: State)
	if not state.ready or next(state.dirty) == nil then
		return
	end
	local payload: { [string]: any } = {}
	local saved = false
	for key in state.dirty do
		payload[key] = valueOf(state, key)
		if SAVED_KEYS[key] then
			saved = true
		end
	end
	state.dirty = {}
	Net.fire("State", state.player, payload)
	if saved then
		Profiles.markDirty(state.player)
	end
end

function PlayerState.get(player: Player): State?
	local s = states[player]
	if s ~= nil and s.ready then
		return s
	end
	return nil
end

function PlayerState.all(): { State }
	local list = {}
	for _, s in states do
		if s.ready then
			table.insert(list, s)
		end
	end
	return list
end

function PlayerState.touch(player: Player, ...: string)
	local s = states[player]
	if s == nil then
		return
	end
	for _, key in { ... } do
		s.dirty[key] = true
	end
end

function PlayerState.recompute(player: Player)
	local s = states[player]
	if s == nil then
		return
	end
	s.derived = StatsCalc.compute(s.profile, buffs, now())
	if s.carried > s.derived.capacity then
		-- capacity can shrink (Cool Down, tool swap): keep the value share that fits
		local keep = s.derived.capacity / math.max(1, s.carried)
		s.carriedValue = s.carriedValue * keep
		s.carried = s.derived.capacity
		s.dirty.carried = true
		s.dirty.carriedValue = true
	end
	s.dirty.derived = true
	-- apply walk speed on the live character
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = s.derived.walkSpeed
	end
end

function PlayerState.setBuff(id: string, endsAt: number)
	buffs[id] = endsAt
	for _, s in states do
		s.dirty.buffs = true
		PlayerState.recompute(s.player)
	end
	-- expire later so the multiplier turns off by itself
	task.delay(math.max(0.1, endsAt - now()) + 0.2, function()
		for _, s in states do
			PlayerState.recompute(s.player)
		end
	end)
end

function PlayerState.setClean(total: number)
	if math.abs(total - cleanTotal) < 0.002 then
		return
	end
	cleanTotal = total
	for _, s in states do
		s.dirty.cleanTotal = true
	end
end

function PlayerState.addCoins(player: Player, amount: number)
	local s = states[player]
	if s == nil or amount ~= amount or amount <= 0 then
		return
	end
	amount = finite(amount)
	local p = s.profile
	p.coins += amount
	p.runCoins += amount
	p.lifetimeCoins += amount
	s.dirty.coins = true
	s.dirty.runCoins = true
	s.dirty.lifetimeCoins = true
end

-- true when the player had enough and it was taken
function PlayerState.spendCoins(player: Player, amount: number): boolean
	local s = states[player]
	if s == nil or amount ~= amount or amount < 0 or s.profile.coins < amount then
		return false
	end
	s.profile.coins -= amount
	s.dirty.coins = true
	return true
end

-- Adds units to the backpack (already clamped by the caller to capacity). Returns units added.
function PlayerState.addCarried(player: Player, units: number, valueCoins: number): number
	local s = states[player]
	if s == nil or units <= 0 then
		return 0
	end
	local room = math.max(0, s.derived.capacity - s.carried)
	local added = math.min(units, room)
	if added <= 0 then
		return 0
	end
	local share = added / units
	s.carried += added
	s.carriedValue += finite(valueCoins) * share
	s.dirty.carried = true
	s.dirty.carriedValue = true
	return added
end

-- Lose a share of the backpack (lava hit). Returns units lost.
function PlayerState.dropCarried(player: Player, fraction: number): number
	local s = states[player]
	if s == nil or s.carried <= 0 then
		return 0
	end
	local lost = math.floor(s.carried * math.clamp(fraction, 0, 1))
	if lost <= 0 then
		return 0
	end
	local keep = (s.carried - lost) / s.carried
	s.carried -= lost
	s.carriedValue *= keep
	s.dirty.carried = true
	s.dirty.carriedValue = true
	return lost
end

-- Empties the backpack for selling. Returns units, valueBeforeMultipliers.
function PlayerState.takeCarried(player: Player): (number, number)
	local s = states[player]
	if s == nil or s.carried <= 0 then
		return 0, 0
	end
	local units, value = s.carried, s.carriedValue
	s.carried = 0
	s.carriedValue = 0
	s.dirty.carried = true
	s.dirty.carriedValue = true
	return units, value
end

function PlayerState.addStat(player: Player, key: string, n: number)
	local s = states[player]
	if s == nil or n ~= n or n <= 0 then
		return
	end
	local stats = s.profile.stats :: any
	if type(stats[key]) ~= "number" then
		return
	end
	stats[key] += finite(n)
	s.dirty.stats = true
end

function PlayerState.fullSync(player: Player)
	local s = states[player]
	if s == nil then
		return
	end
	local payload: { [string]: any } = {
		carried = s.carried,
		carriedValue = s.carriedValue,
		derived = s.derived,
		buffs = buffs,
		cleanTotal = cleanTotal,
	}
	for key in SAVED_KEYS do
		payload[key] = (s.profile :: any)[key]
	end
	payload.version = s.profile.version
	s.dirty = {}
	Net.fire("State", player, payload)
end

-- One small message for the player's Toast line (kid-friendly text, short).
function PlayerState.toast(player: Player, text: string, kind: "info" | "good" | "warn" | "gold")
	if player.Parent == nil then
		return
	end
	local info: Types.ToastInfo = { text = text, kind = kind }
	Net.fire("Toast", player, info)
end

local function tryReady(player: Player)
	local s = states[player]
	if s == nil or s.ready or not s.clientReady then
		return
	end
	local profile = Profiles.get(player)
	if profile == nil then
		return
	end
	s.profile = profile
	s.derived = StatsCalc.compute(profile, buffs, now())
	s.ready = true
	PlayerState.recompute(player)
	PlayerState.fullSync(player)
	PlayerState.onReady:fire(player, s)
end

local function newState(player: Player): State
	local blank: any = {}
	return {
		player = player,
		profile = blank,
		carried = 0,
		carriedValue = 0,
		derived = blank,
		clientReady = false,
		ready = false,
		dirty = {},
		lastSweepAt = 0,
		lastHitAt = 0,
		playSince = os.clock(),
	}
end

function PlayerState.init()
	if started then
		return
	end
	started = true

	local function track(player: Player)
		if states[player] == nil then
			states[player] = newState(player)
		end
	end
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)

	-- Profiles fires onLeaving just before the final save: last chance to touch the profile.
	Profiles.onLeaving:Connect(function(player: Player, profile)
		local s = states[player]
		if s ~= nil and s.ready then
			profile.stats.playSeconds += math.floor(os.clock() - s.playSince)
			PlayerState.onLeaving:fire(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.delay(2, function()
			states[player] = nil
		end)
	end)

	Profiles.onLoaded:Connect(function(player: Player)
		track(player)
		tryReady(player)
	end)

	Net.onRequest("ClientReady", function(player)
		track(player)
		states[player].clientReady = true
		tryReady(player)
	end)

	-- walk speed follows respawns
	local function hookChar(player: Player)
		player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			local s = states[player]
			if hum ~= nil and s ~= nil and s.ready then
				hum.WalkSpeed = s.derived.walkSpeed
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		hookChar(p)
	end
	Players.PlayerAdded:Connect(hookChar)

	-- one batched State push per player at ~10 Hz
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		for _, s in states do
			flush(s)
		end
	end)
end

return PlayerState
