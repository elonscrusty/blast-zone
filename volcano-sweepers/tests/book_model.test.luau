--!strict
-- Finds Book view-model: silhouettes, counts, set progress, claim states, odds legend.
local Harness = require("./harness")
local Finds = require("../src/shared/Catalog/Finds")
local BookModel = require("../src/shared/Ui/BookModel")
local Economy = require("../src/shared/Rules/Economy")

local function profileWith(finds: { [string]: number }, claimed: { [string]: boolean }?): any
	local p: any = Economy.blankProfile()
	p.finds = finds
	p.setsClaimed = claimed or {}
	return p
end

local function setOf(view: BookModel.View, id: string): BookModel.SetView
	for _, s in view.sets do
		if s.id == id then
			return s
		end
	end
	error("no set " .. id)
end

local function allOfSet(setId: string): { [string]: number }
	local out: { [string]: number } = {}
	for _, f in Finds.inSet(setId) do
		out[f.id] = 1
	end
	return out
end

Harness.test("book: empty book is 0 / 30 with silhouettes", function()
	local v = BookModel.build(profileWith({}))
	Harness.eq(v.found, 0)
	Harness.eq(v.total, 30)
	Harness.eq(v.headerText, "Found 0 / 30")
	Harness.eq(v.fraction, 0)
	Harness.eq(#v.sets, 6)
	Harness.eq(v.claimable, 0)
	Harness.eq(v.badge, false)
	for _, s in v.sets do
		Harness.eq(s.total, 5, s.id)
		Harness.eq(s.progressText, "0/5")
		Harness.eq(s.claimable, false)
		Harness.eq(s.claimed, false)
		for _, e in s.entries do
			Harness.eq(e.found, false)
			Harness.eq(e.shownName, "???")
			Harness.eq(e.countText, "")
			Harness.eq(e.coinsText, "Worth: ???")
		end
	end
end)

Harness.test("book: sets come in the catalog order and hold the catalog finds", function()
	local v = BookModel.build(profileWith({}))
	for i, s in v.sets do
		Harness.eq(s.id, Finds.sets[i].id)
		local list = Finds.inSet(s.id)
		Harness.eq(#s.entries, #list)
		for j, e in s.entries do
			Harness.eq(e.id, list[j].id)
			Harness.eq(e.coins, list[j].coins)
			Harness.eq(e.rarity, list[j].rarity)
		end
	end
end)

Harness.test("book: found finds show name, count, value and zone", function()
	local v = BookModel.build(profileWith({ shiny_shell = 3, starfish_sam = 1, fuzzy_acorn = 12 }))
	Harness.eq(v.found, 3)
	Harness.eq(v.headerText, "Found 3 / 30")
	Harness.near(v.fraction, 0.1)
	local beach = setOf(v, "beach")
	Harness.eq(beach.found, 2)
	Harness.eq(beach.progressText, "2/5")
	local shell = beach.entries[1]
	Harness.eq(shell.id, "shiny_shell")
	Harness.eq(shell.found, true)
	Harness.eq(shell.shownName, "Shiny Shell")
	Harness.eq(shell.countText, "x3")
	Harness.eq(shell.coinsText, `Worth {Finds.byId.shiny_shell.coins} coins`)
	Harness.eq(shell.zoneText, "Found in Sunny Beach")
	Harness.eq(shell.rarityLabel, "Common")
	Harness.eq(shell.oddsText, "62%")
	Harness.eq(shell.oddsLine, "Common: 62% of finds")
	Harness.eq(setOf(v, "forest").entries[1].countText, "x12")
	-- a missing find tells where it hides, not its name
	local note = beach.entries[3]
	Harness.eq(note.found, false)
	Harness.eq(note.zoneText, "Hides in Sunny Beach")
end)

Harness.test("book: rainbow finds are 'anywhere'", function()
	local v = BookModel.build(profileWith({ giggle_gem = 1 }))
	local rainbow = setOf(v, "rainbow")
	Harness.eq(rainbow.found, 1)
	local gem = rainbow.entries[3]
	Harness.eq(gem.id, "giggle_gem")
	Harness.eq(gem.zoneText, "Pops up anywhere!")
	Harness.eq(gem.rarityLabel, "Legendary")
	Harness.eq(rainbow.entries[1].zoneText, "Could pop up anywhere!")
end)

Harness.test("book: a finished set can be claimed, once", function()
	local finds = allOfSet("beach")
	local v = BookModel.build(profileWith(finds))
	local beach = setOf(v, "beach")
	Harness.eq(beach.complete, true)
	Harness.eq(beach.claimable, true)
	Harness.eq(beach.claimed, false)
	Harness.eq(beach.rewardText, "+2% coins forever")
	Harness.eq(beach.rewardLine, "Set complete! +2% coins forever")
	Harness.eq(v.claimable, 1)
	Harness.eq(v.badge, true)
	Harness.eq(BookModel.badge(profileWith(finds)), true)

	local after = BookModel.build(profileWith(finds, { beach = true }))
	local done = setOf(after, "beach")
	Harness.eq(done.claimed, true)
	Harness.eq(done.claimable, false)
	Harness.eq(done.rewardLine, "+2% coins forever")
	Harness.eq(after.badge, false)
	Harness.eq(BookModel.badge(profileWith(finds, { beach = true })), false)
end)

Harness.test("book: a set with a missing find is not claimable", function()
	local finds = allOfSet("forest")
	finds["fern_star"] = nil
	local v = BookModel.build(profileWith(finds))
	local forest = setOf(v, "forest")
	Harness.eq(forest.found, 4)
	Harness.eq(forest.complete, false)
	Harness.eq(forest.claimable, false)
	Harness.eq(forest.rewardLine, "Find all 5: +3% coins forever")
	Harness.eq(v.badge, false)
end)

Harness.test("book: reward text for every set matches the catalog", function()
	local expect: { [string]: string } = {
		beach = "+2% coins forever",
		forest = "+3% coins forever",
		springs = "+4% coins forever",
		rim = "+5% coins forever",
		heart = "+6% coins forever",
		rainbow = "+10% coins forever",
	}
	for _, s in BookModel.build(profileWith({})).sets do
		Harness.eq(s.rewardText, expect[s.id], s.id)
	end
	Harness.eq(BookModel.rewardText(0.025), "+2.5% coins forever")
	Harness.eq(BookModel.rewardText(0.07), "+7% coins forever")
end)

Harness.test("book: several claimable sets are counted", function()
	local finds = allOfSet("beach")
	for k, v in allOfSet("rim") do
		finds[k] = v
	end
	local v = BookModel.build(profileWith(finds, { beach = true }))
	Harness.eq(v.claimable, 1)
	local v2 = BookModel.build(profileWith(finds))
	Harness.eq(v2.claimable, 2)
	Harness.eq(v2.found, 10)
end)

Harness.test("book: all 30 found", function()
	local finds: { [string]: number } = {}
	for _, f in Finds.list do
		finds[f.id] = 1
	end
	local v = BookModel.build(profileWith(finds))
	Harness.eq(v.found, 30)
	Harness.eq(v.fraction, 1)
	Harness.eq(v.claimable, 6)
end)

Harness.test("book: every find has its own picture", function()
	local seen: { [string]: string } = {}
	for _, f in Finds.list do
		local icon = BookModel.iconFor(f.id)
		Harness.truthy(icon ~= "", f.id)
		Harness.eq(seen[icon], nil, `{f.id} shares an icon with {seen[icon]}`)
		seen[icon] = f.id
	end
	Harness.eq(BookModel.iconFor("nope"), "💎")
end)

Harness.test("book: odds legend shows the catalog odds, luck adds 'yours'", function()
	local plain = BookModel.build(profileWith({}), 1)
	Harness.eq(#plain.legend, 4)
	local text = ""
	for _, l in plain.legend do
		text ..= l.oddsText .. " "
		Harness.eq(l.yourOddsText, nil, l.id)
	end
	Harness.eq(text, "62% 25% 11% 2% ")
	Harness.eq(plain.legend[1].label, "Common")
	Harness.eq(plain.legend[4].colorHex, Finds.rarityById["legendary"].colorHex)
	Harness.eq(plain.tipText, "About 3 in every 100 clean patches hides a treasure!")

	local lucky = BookModel.build(profileWith({}), 3)
	local changed = 0
	for _, l in lucky.legend do
		if l.yourOddsText ~= nil then
			changed += 1
		end
	end
	Harness.truthy(changed >= 2, "luck changes the shown odds")
	-- luck moves odds toward rarer finds
	local c = tonumber((string.gsub(lucky.legend[1].yourOddsText or "100", "%%", ""))) or 100
	Harness.truthy(c < 62, "common gets less likely")
	Harness.truthy(string.find(lucky.tipText, "Your luck is helping", 1, true) ~= nil)
end)

Harness.test("book: junk input never throws", function()
	local junk: any = { finds = "oops", setsClaimed = 5 }
	Harness.eq(BookModel.build(junk).found, 0)
	Harness.eq(BookModel.build({}).found, 0)
	local weird: any =
		{ finds = { shiny_shell = -4, starfish_sam = 0 / 0, nobody = 9, bottle_note = 2.7 } }
	local v = BookModel.build(weird, 0 / 0)
	Harness.eq(v.found, 1) -- only bottle_note counts
	Harness.eq(setOf(v, "beach").entries[3].count, 2)
	Harness.eq(v.legend[1].yourOddsText, nil)
end)

Harness.test("book: columns for a width", function()
	Harness.eq(BookModel.columns(626, 5, 84, 6), 5)
	Harness.eq(BookModel.columns(282, 5, 84, 6), 3)
	Harness.eq(BookModel.columns(100, 5, 84, 6), 1)
	Harness.eq(BookModel.columns(2000, 5, 84, 6), 5)
	Harness.eq(BookModel.columns(0, 5, 84, 6), 1)
	Harness.eq(BookModel.columns(0 / 0, 5, 84, 6), 1)
	Harness.eq(BookModel.columns(300, 0, 84, 6), 1)
end)
