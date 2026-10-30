--!strict
-- Pure rules for game modes (piece G24). Which modes exist, who may vote for one, what a vote looks like to a
-- player, and how a mode's tuning is put on the config and taken off again. No Roblox: Lune tests it.
-- The server owns all of it; a client only asks to vote.

local Config = require("../Config")
local VoteBook = require("../MapVote/VoteBook")
local VoteFlow = require("../MapVote/VoteFlow")

local ModeRules = {}

export type Def = {
	id: string,
	name: string,
	blurb: string,
	unlockLevel: number,
	tuning: Config.ModeTuning,
}

export type Choice = {
	id: string,
	name: string,
	blurb: string,
	unlockLevel: number,
	locked: boolean, -- true for THIS viewer: their level is below unlockLevel
	votes: number,
}

export type State = {
	open: boolean,
	modes: { Choice },
	yourVote: string?,
	nextModeId: string?, -- set once the vote is locked (the default mode when nobody voted)
	level: number, -- the viewer's account level, so the picker can say "level 4 opens this"
}

local function defOf(id: string): Def?
	local raw = Config.Modes.defs[id]
	if raw == nil then
		return nil
	end
	return {
		id = id,
		name = raw.name,
		blurb = raw.blurb,
		unlockLevel = raw.unlockLevel,
		tuning = raw.tuning,
	}
end

-- The modes shown, in Config.Modes.enabled order. An id with no definition is skipped.
function ModeRules.enabled(): { Def }
	local out: { Def } = {}
	local seen: { [string]: boolean } = {}
	for _, id in Config.Modes.enabled do
		local def = defOf(id)
		if def ~= nil and not seen[id] then
			seen[id] = true
			table.insert(out, def)
		end
	end
	return out
end

-- A shown mode by id, or nil (unknown, or defined but not enabled).
function ModeRules.get(id: string): Def?
	for _, def in ModeRules.enabled() do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The mode used when nobody votes: Config.Modes.defaultId if it is shown, else the first shown mode.
function ModeRules.default(): Def?
	local wanted = ModeRules.get(Config.Modes.defaultId)
	if wanted ~= nil then
		return wanted
	end
	return ModeRules.enabled()[1]
end

function ModeRules.isUnlocked(def: Def, level: number): boolean
	return level >= def.unlockLevel
end

-- A vote is allowed when the mode is shown and the voter's level opens it. The vote window is checked by the flow.
function ModeRules.canVote(modeId: string, level: number): boolean
	local def = ModeRules.get(modeId)
	return def ~= nil and ModeRules.isUnlocked(def, level)
end

-- The pool the vote book counts.
function ModeRules.pool(): { VoteBook.MapInfo }
	local out: { VoteBook.MapInfo } = {}
	for _, def in ModeRules.enabled() do
		table.insert(out, { id = def.id, name = def.name })
	end
	return out
end

-- One voter's vote. The level check comes first; the flow then checks the window and the pool.
function ModeRules.vote(
	flow: VoteFlow.Flow,
	voterId: string,
	modeId: string,
	level: number
): boolean
	if not ModeRules.canVote(modeId, level) then
		return false
	end
	return flow:vote(voterId, modeId)
end

-- What one player is shown: the flow's counts plus each mode's text and whether it is locked for them.
function ModeRules.stateFor(flow: VoteFlow.Flow, voterId: string?, level: number): State
	local raw = flow:state(voterId)
	local modes: { Choice } = {}
	for _, entry in raw.maps do
		local def = ModeRules.get(entry.id)
		if def ~= nil then
			table.insert(modes, {
				id = def.id,
				name = def.name,
				blurb = def.blurb,
				unlockLevel = def.unlockLevel,
				locked = not ModeRules.isUnlocked(def, level),
				votes = entry.votes,
			})
		end
	end
	return {
		open = raw.open,
		modes = modes,
		yourVote = raw.yourVote,
		nextModeId = raw.nextMapId,
		level = level,
	}
end

-- The mode that will be played once the vote is over: the winner, or the default when nobody voted.
function ModeRules.resolve(winnerId: string?): Def?
	if winnerId ~= nil then
		local def = ModeRules.get(winnerId)
		if def ~= nil then
			return def
		end
	end
	return ModeRules.default()
end

-- Why a tuning is not allowed, or nil if it is fine. Every shown mode is checked by a test.
function ModeRules.problem(tuning: Config.ModeTuning): string?
	local low, top = Config.Modes.minScale, Config.Modes.maxScale
	for _, key in { "zoneTimeScale", "zoneDamageScale" } do
		local value: number? = (tuning :: any)[key]
		if value ~= nil and not (value == value and value >= low and value <= top) then
			return `{key} must be between {low} and {top}`
		end
	end
	for _, key in { "floorGuns", "floorPacks" } do
		local value: number? = (tuning :: any)[key]
		if value ~= nil and not (value == math.floor(value) and value >= 0 and value <= 20) then
			return `{key} must be a whole number from 0 to 20`
		end
	end
	local weights = tuning.crateWeights
	if weights ~= nil then
		local total = 0
		for tier, weight in weights do
			if Config.Containers.tiers[tier] == nil then
				return `crateWeights names an unknown tier {tier}`
			end
			if not (weight == weight and weight >= 0 and weight <= 1000) then
				return `crateWeights.{tier} must be from 0 to 1000`
			end
			total += weight
		end
		if total <= 0 then
			return "crateWeights must have at least one tier above 0"
		end
	end
	return nil
end

-- Puts a mode's tuning on `config` (the shared Config, or a copy in tests) and returns a function that puts every
-- number back. Only the fields the tuning names are touched. Calling the undo twice does nothing the second time.
function ModeRules.apply(config: any, tuning: Config.ModeTuning): () -> ()
	local undoList: { () -> () } = {}
	local function set(holder: any, key: string, value: number)
		local old = holder[key]
		holder[key] = value
		table.insert(undoList, function()
			holder[key] = old
		end)
	end

	local zone = config.Zone
	local timeScale = tuning.zoneTimeScale
	if timeScale ~= nil then
		for _, stage in zone.stages do
			set(stage, "warnAt", stage.warnAt * timeScale)
			set(stage, "closeAt", stage.closeAt * timeScale)
			set(stage, "closeSeconds", stage.closeSeconds * timeScale)
		end
		set(zone.suddenDeath, "startsAt", zone.suddenDeath.startsAt * timeScale)
		set(zone.suddenDeath, "closeSeconds", zone.suddenDeath.closeSeconds * timeScale)
	end
	local damageScale = tuning.zoneDamageScale
	if damageScale ~= nil then
		for _, stage in zone.stages do
			set(stage, "damagePerSecond", stage.damagePerSecond * damageScale)
		end
		set(zone.suddenDeath, "damagePerSecond", zone.suddenDeath.damagePerSecond * damageScale)
	end
	if tuning.floorGuns ~= nil then
		set(config.Loot.floorGuns, "count", tuning.floorGuns)
	end
	if tuning.floorPacks ~= nil then
		set(config.Loot.heal, "floorPacks", tuning.floorPacks)
	end
	if tuning.crateWeights ~= nil then
		for tier, weight in tuning.crateWeights do
			local info = config.Containers.tiers[tier]
			if info ~= nil then
				set(info, "weight", weight)
			end
		end
	end

	local undone = false
	return function()
		if undone then
			return
		end
		undone = true
		for i = #undoList, 1, -1 do
			undoList[i]()
		end
	end
end

return ModeRules
