--!strict
-- The loadout catalogue and its rules. Pure data and checks, no Roblox services, so Lune can test it.
-- Seven slots: hero (piece 46: own health + own two guns, all free), outfit (the three fighters), head / body /
-- feet gear (piece 48: small trades, see shared/Gear), gun skin, slide sidegrade. Outfits and gun skins are looks only. Trails and tracers belong to piece 18 (the Rewards
-- board); the loadout screen only links to them.
-- A sidegrade trades one thing for another (Slide goes farther but waits longer), so nothing is simply
-- stronger and the match stays fair (brief section 20: no permanent power).
--
-- Unlocking follows piece 18's Rewards board: "level" is how many rewards the player has bought (0 to 6).
-- An item is free when `unlockAt` is nil, open once the level reaches `unlockAt`, or when owned outright.
-- The unlockAt numbers are placeholders for carter to tune; they must stay at 6 or less.

local Gear = require("./Gear")
local Heroes = require("./Heroes")

export type Slot = "hero" | "outfit" | "head" | "body" | "feet" | "gun" | "slide"

export type Look = {
	gunBody: number?,
	gunAcc: number?,
}

export type Item = {
	id: string,
	name: string,
	desc: string,
	unlockAt: number?, -- reward level needed; nil = free
	look: Look,
	fighter: string?, -- outfit slot only: the N11 look name (Config.Character.lookAttribute value)
	-- slide sidegrades only: studs added to Slide distance, seconds added to its wait
	slideDistance: number?,
	slideCooldown: number?,
	gear: Gear.Piece?, -- head / body / feet only: the piece (perks, placeholder shape and colour)
}

export type Selection = {
	hero: string,
	outfit: string,
	head: string,
	body: string,
	feet: string,
	gun: string,
	slide: string,
}

export type Unlocks = { level: number, owned: { [string]: boolean }? }

local Loadout = {}

Loadout.slots = { "hero", "outfit", "head", "body", "feet", "gun", "slide" } :: { Slot }

Loadout.slotNames = {
	hero = "HERO",
	outfit = "OUTFIT",
	head = Gear.slotNames.head,
	body = Gear.slotNames.body,
	feet = Gear.slotNames.feet,
	gun = "GUN",
	slide = "SLIDE",
} :: { [string]: string }

-- Heroes come straight from the roster (shared/Heroes); every one is free, so `unlockAt` stays nil.
local heroItems: { Item } = {}
for _, hero in Heroes.list do
	table.insert(heroItems, {
		id = hero.id,
		name = hero.name,
		desc = hero.blurb,
		look = {},
	})
end

-- Gear (piece 48): head, body and feet come straight from shared/Gear. Small trades, never plain power.
local function gearItems(slot: Gear.Slot): { Item }
	local out: { Item } = {}
	for _, piece in Gear.pieces[slot] do
		table.insert(out, {
			id = piece.id,
			name = piece.name,
			desc = piece.desc,
			unlockAt = piece.unlockAt,
			look = {},
			gear = piece,
		})
	end
	return out
end

Loadout.items = {
	hero = heroItems,
	-- The outfit slot is piece N11's three fighters (shared/Character/Looks). Runner is carter's pick;
	-- the other two became skins you earn.
	outfit = {
		{
			id = "runner",
			name = "Runner",
			desc = "Visor helmet, top fin, round white shoulders.",
			fighter = "Runner",
			look = {},
		},
		{
			id = "courier",
			name = "Courier",
			desc = "Headphones, green beanie, tall backpack.",
			unlockAt = 2,
			fighter = "Courier",
			look = {},
		},
		{
			id = "spark",
			name = "Spark",
			desc = "Square head, coral fins, pointy shoulders.",
			unlockAt = 4,
			fighter = "Spark",
			look = {},
		},
	},
	head = gearItems("head"),
	body = gearItems("body"),
	feet = gearItems("feet"),
	gun = {
		{
			id = "sleek",
			name = "Sleek",
			desc = "Volt Pistol, navy and cyan.",
			look = { gunBody = 0x14243A, gunAcc = 0x36D9E8 },
		},
		{
			id = "hazard",
			name = "Hazard",
			desc = "Volt Pistol, gold and black.",
			look = { gunBody = 0xFFC44D, gunAcc = 0x14243A },
		},
		{
			id = "pop",
			name = "Coral Pop",
			desc = "Volt Pistol, coral.",
			unlockAt = 3,
			look = { gunBody = 0xF15B64, gunAcc = 0xFFF4D6 },
		},
		{
			id = "chrome",
			name = "Chrome",
			desc = "Mirror finish.",
			unlockAt = 6,
			look = { gunBody = 0xCFD8E3, gunAcc = 0x8B5FBF },
		},
	},
	slide = {
		{
			id = "std",
			name = "Standard Slide",
			desc = "The normal Slide.",
			look = {},
			slideDistance = 0,
			slideCooldown = 0,
		},
		{
			id = "long",
			name = "Long Slide",
			desc = "Goes 4 studs farther. Waits 1 s longer.",
			look = {},
			slideDistance = 4,
			slideCooldown = 1,
		},
		{
			id = "quick",
			name = "Quick Slide",
			desc = "Goes 4 studs shorter. Ready 1 s sooner.",
			unlockAt = 4,
			look = {},
			slideDistance = -4,
			slideCooldown = -1,
		},
	},
} :: { [string]: { Item } }

Loadout.defaults = {
	hero = Heroes.default,
	outfit = "runner",
	head = Gear.defaults.head,
	body = Gear.defaults.body,
	feet = Gear.defaults.feet,
	gun = "sleek",
	slide = "std",
} :: Selection

-- Slide may never be tuned below these, whatever stacks of upgrades and sidegrades say.
Loadout.minSlideDistance = 4
Loadout.minSlideCooldown = 1

local byId: { [string]: { [string]: Item } } = {}
for _, slot in Loadout.slots do
	byId[slot] = {}
	for _, item in Loadout.items[slot] do
		byId[slot][item.id] = item
	end
end

function Loadout.isSlot(slot: any): boolean
	return type(slot) == "string" and byId[slot] ~= nil
end

function Loadout.find(slot: string, id: string): Item?
	local items = byId[slot]
	return if items then items[id] else nil
end

-- Is this item usable by a player with these unlocks?
function Loadout.isUnlocked(item: Item, unlocks: Unlocks): boolean
	if item.unlockAt == nil then
		return true
	end
	if unlocks.owned and unlocks.owned[item.id] then
		return true
	end
	return unlocks.level >= item.unlockAt
end

-- Why can't they equip this? nil means they can.
function Loadout.equipProblem(slot: any, id: any, unlocks: Unlocks): string?
	if not Loadout.isSlot(slot) then
		return "unknown_slot"
	end
	local item = if type(id) == "string" then Loadout.find(slot, id) else nil
	if not item then
		return "unknown_item"
	end
	if not Loadout.isUnlocked(item, unlocks) then
		return "locked"
	end
	return nil
end

-- A selection that is always valid: anything missing, unknown or still locked falls back to the default.
function Loadout.sanitize(raw: any, unlocks: Unlocks): Selection
	local out: Selection = {
		hero = Loadout.defaults.hero,
		outfit = Loadout.defaults.outfit,
		head = Loadout.defaults.head,
		body = Loadout.defaults.body,
		feet = Loadout.defaults.feet,
		gun = Loadout.defaults.gun,
		slide = Loadout.defaults.slide,
	}
	if type(raw) ~= "table" then
		return out
	end
	for _, slot in Loadout.slots do
		local id = (raw :: any)[slot]
		if Loadout.equipProblem(slot, id, unlocks) == nil then
			(out :: any)[slot] = id
		end
	end
	return out
end

-- Everything a client needs to draw the screen for this player: which ids are open.
function Loadout.unlockedIds(unlocks: Unlocks): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for _, slot in Loadout.slots do
		local ids = {}
		for _, item in Loadout.items[slot] do
			if Loadout.isUnlocked(item, unlocks) then
				table.insert(ids, item.id)
			end
		end
		out[slot] = ids
	end
	return out
end

-- The one look to show for a whole selection (gun colours; outfits are whole fighters, see `fighter`).
function Loadout.mergedLook(selection: Selection): Look
	local look: Look = {}
	for _, slot in Loadout.slots do
		local item = Loadout.find(slot, (selection :: any)[slot])
		if item then
			for k, v in item.look :: any do
				(look :: any)[k] = v
			end
		end
	end
	return look
end

-- 0xRRGGBB -> r, g, b (0..255), for Color3.fromRGB.
function Loadout.rgb(n: number): (number, number, number)
	return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

-- Apply the slide sidegrade to a stat sheet in place. Clamped so no stack can break Slide.
function Loadout.applySlide(
	sheet: { slideDistance: number, slideCooldown: number },
	slideId: string
)
	local item = Loadout.find("slide", slideId)
	if not item then
		return
	end
	sheet.slideDistance =
		math.max(Loadout.minSlideDistance, sheet.slideDistance + (item.slideDistance or 0))
	sheet.slideCooldown =
		math.max(Loadout.minSlideCooldown, sheet.slideCooldown + (item.slideCooldown or 0))
end

return Loadout
