--!strict
-- Piece 48: gear slots (video 3 gap #15). Head, body and feet each hold one piece of gear.
-- Pure data and rules, no Roblox services, so Lune can test it.
--
-- Every piece is a trade, never plain power: it gives a little in one "dial" and takes a little in another.
-- Each dial has a worth per unit, and a piece's total worth may never be above zero (tested). The sum of
-- all three pieces is also clamped by `Config.Gear.limits`, so no stack, and no `spread`, can break the match.
-- Gear is free: opened on the Rewards board like the other loadout slots, never sold, no Robux, no ids.
-- The `shape` and `color` of a piece are placeholders for the look layer (Claude Design / art), which reads
-- the player attributes GearHead / GearBody / GearFeet; nothing here draws anything.
--
-- Dials (a positive amount is a gain for the player):
--   health      hit points added to the hero's start health
--   speed       percent of run speed
--   reload      percent faster reload (both guns)
--   range       percent gun range (both guns)
--   slideWait   seconds sooner the Slide is ready
--   slideReach  studs farther Slide
local Ids = require("./Ids")

export type Dial = "health" | "speed" | "reload" | "range" | "slideWait" | "slideReach"
export type Slot = "head" | "body" | "feet"

export type Piece = {
	id: string,
	name: string,
	desc: string,
	unlockAt: number?, -- reward level needed; nil = free
	shape: string, -- placeholder name of the thing to draw ("cap", "vest", "boots"...)
	color: number, -- 0xRRGGBB
	perks: { [string]: number }, -- dial -> amount
}

export type Picks = { head: string?, body: string?, feet: string? }

local Gear = {}

Gear.slots = { "head", "body", "feet" } :: { Slot }

Gear.slotNames = { head = "HEAD", body = "BODY", feet = "FEET" } :: { [string]: string }

Gear.dials = { "health", "speed", "reload", "range", "slideWait", "slideReach" } :: { Dial }

-- Worth of one unit of each dial. A piece's perks must add up to zero or less.
Gear.worth = {
	health = 1,
	speed = 3,
	reload = 2,
	range = 1,
	slideWait = 10,
	slideReach = 3,
} :: { [string]: number }

-- A piece may lose at most this much worth on balance (not junk).
Gear.maxLoss = 4

Gear.defaults =
	{ head = "plain", body = "plain", feet = "plain" } :: { head: string, body: string, feet: string }

Gear.pieces = {
	head = {
		{
			id = "plain",
			name = "Plain",
			desc = "Nothing on your head.",
			shape = "none",
			color = 0x8E99A8,
			perks = {},
		},
		{
			id = "visor",
			name = "Visor Cap",
			desc = "Sees farther, reloads slower.",
			shape = "cap",
			color = 0x36D9E8,
			perks = { range = 6, reload = -3 },
		},
		{
			id = "echo",
			name = "Echo Helm",
			desc = "Reloads faster, sees less far.",
			unlockAt = 2,
			shape = "helm",
			color = 0xF15B64,
			perks = { reload = 4, range = -9 },
		},
		{
			id = "halo",
			name = "Halo Band",
			desc = "A bit tougher, a bit less sharp.",
			unlockAt = 5,
			shape = "band",
			color = 0xFFC44D,
			perks = { health = 8, range = -4, reload = -2 },
		},
	},
	body = {
		{
			id = "plain",
			name = "Plain",
			desc = "Just your fighter.",
			shape = "none",
			color = 0x8E99A8,
			perks = {},
		},
		{
			id = "vest",
			name = "Padded Vest",
			desc = "Tougher, slower on your feet.",
			shape = "vest",
			color = 0x8B5FBF,
			perks = { health = 10, speed = -4 },
		},
		{
			id = "wire",
			name = "Wire Jacket",
			desc = "Quicker, easier to knock down.",
			unlockAt = 3,
			shape = "jacket",
			color = 0x36D9E8,
			perks = { speed = 3, health = -10 },
		},
		{
			id = "plate",
			name = "Plate Coat",
			desc = "Very tough, clearly slower.",
			unlockAt = 6,
			shape = "coat",
			color = 0xCFD8E3,
			perks = { health = 16, speed = -6 },
		},
	},
	feet = {
		{
			id = "plain",
			name = "Plain",
			desc = "Your normal shoes.",
			shape = "none",
			color = 0x8E99A8,
			perks = {},
		},
		{
			id = "spring",
			name = "Spring Soles",
			desc = "Slide is ready sooner, you run a bit slower.",
			shape = "boots",
			color = 0xFFC44D,
			perks = { slideWait = 0.5, speed = -2 },
		},
		{
			id = "grip",
			name = "Grip Boots",
			desc = "Quicker on your feet, Slide waits longer.",
			unlockAt = 4,
			shape = "boots",
			color = 0x14243A,
			perks = { speed = 3, slideWait = -1 },
		},
		{
			id = "skates",
			name = "Glide Skates",
			desc = "Slide goes farther, you run slower.",
			unlockAt = 6,
			shape = "skates",
			color = 0xF15B64,
			perks = { slideReach = 3, speed = -3 },
		},
	},
} :: { [string]: { Piece } }

local byId: { [string]: { [string]: Piece } } = {}
for _, slot in Gear.slots do
	byId[slot] = {}
	for _, piece in Gear.pieces[slot] do
		byId[slot][piece.id] = piece
	end
end

function Gear.isSlot(slot: any): boolean
	return type(slot) == "string" and byId[slot] ~= nil
end

function Gear.find(slot: string, id: any): Piece?
	local pieces = byId[slot]
	if pieces == nil or type(id) ~= "string" then
		return nil
	end
	return pieces[id]
end

-- Worth of one piece on balance (zero or less for every real piece).
function Gear.net(piece: Piece): number
	local total = 0
	for dial, amount in piece.perks do
		total += (Gear.worth[dial] or 0) * amount
	end
	return total
end

-- The three pieces someone wears, always real ones (anything else counts as Plain).
function Gear.sanitize(picks: any): { head: string, body: string, feet: string }
	local out = { head = "plain", body = "plain", feet = "plain" }
	if type(picks) ~= "table" then
		return out
	end
	for _, slot in Gear.slots do
		local id = (picks :: any)[slot]
		if Gear.find(slot, id) ~= nil then
			(out :: any)[slot] = id
		end
	end
	return out
end

-- Sum of every dial for these picks, times `spread`, then kept inside the limits. A dial with nothing is 0.
function Gear.totals(cfg: any, picks: any): { [string]: number }
	local g = cfg.Gear
	local safe = Gear.sanitize(picks)
	local out: { [string]: number } = {}
	for _, dial in Gear.dials do
		out[dial] = 0
	end
	for _, slot in Gear.slots do
		local piece = Gear.find(slot, (safe :: any)[slot])
		if piece then
			for dial, amount in piece.perks do
				out[dial] = (out[dial] or 0) + amount * g.spread
			end
		end
	end
	for _, dial in Gear.dials do
		local limit = g.limits[dial]
		out[dial] = math.clamp(out[dial], limit[1], limit[2])
	end
	return out
end

-- Extra start health (whole number, may be negative). Read once when the match starts.
function Gear.healthBonus(cfg: any, picks: any): number
	return math.floor(Gear.totals(cfg, picks).health + 0.5)
end

-- Tunes a copy of a stat sheet, on top of upgrades and the hero. `sheet.firearm` / `sheet.explosive` must be this
-- caller's own tables (StatBook.get clones them before modifiers run). Reload and range are changed as shares of
-- the sheet's own numbers, so a gun that is already upgraded keeps its upgrade.
function Gear.applyToSheet(cfg: any, sheet: any, picks: any)
	local t = Gear.totals(cfg, picks)
	local g = cfg.Gear
	sheet.moveSpeed = sheet.moveSpeed * (1 + t.speed / 100)
	local reloadScale = 1 - t.reload / 100
	local rangeScale = 1 + t.range / 100
	sheet.firearm.reloadSeconds = sheet.firearm.reloadSeconds * reloadScale
	sheet.explosive.reloadSeconds = sheet.explosive.reloadSeconds * reloadScale
	sheet.firearm.range = sheet.firearm.range * rangeScale
	sheet.explosive.range = sheet.explosive.range * rangeScale
	sheet.slideCooldown = math.max(g.slideCooldownFloor, sheet.slideCooldown - t.slideWait)
	sheet.slideDistance = math.max(g.slideDistanceFloor, sheet.slideDistance + t.slideReach)
end

local function number(n: number): string
	local rounded = math.floor(math.abs(n) * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return tostring(rounded)
end

-- Short lines for a gear card, like "+10 health" or "Reload 3% slower". Real numbers (after `spread`) in a fixed
-- dial order, so the screen only prints them.
function Gear.lines(cfg: any, slot: string, id: string): { string }
	local piece = Gear.find(slot, id)
	local out: { string } = {}
	if piece == nil then
		return out
	end
	local spread = cfg.Gear.spread
	for _, dial in Gear.dials do
		local raw = piece.perks[dial]
		if raw ~= nil and raw ~= 0 then
			local n = raw * spread
			local sign = if n > 0 then "+" else "-"
			if dial == "health" then
				table.insert(out, `{sign}{number(n)} health`)
			elseif dial == "speed" then
				table.insert(out, `{sign}{number(n)}% speed`)
			elseif dial == "reload" then
				table.insert(out, `Reload {number(n)}% {if n > 0 then "faster" else "slower"}`)
			elseif dial == "range" then
				table.insert(out, `{sign}{number(n)}% range`)
			elseif dial == "slideWait" then
				table.insert(out, `Slide ready {number(n)} s {if n > 0 then "sooner" else "later"}`)
			elseif dial == "slideReach" then
				table.insert(out, `{sign}{number(n)} studs Slide`)
			end
		end
	end
	return out
end

-- Gear for a participant id: players wear what they picked (`pick(userId)`), bots wear nothing.
function Gear.of(
	participantId: string,
	pick: ((userId: number) -> any)?
): { head: string, body: string, feet: string }
	local userId = Ids.userIdOf(participantId)
	if userId ~= nil and pick ~= nil then
		return Gear.sanitize(pick(userId))
	end
	return Gear.sanitize(nil)
end

return Gear
