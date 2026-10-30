--!strict
local Harness = require("./harness")
local EmoteRules = require("../src/shared/Character/EmoteRules")
local Emotes = require("../src/shared/Character/Emotes")
local Pose = require("../src/shared/Character/Pose")
local TrackDefs = require("../src/shared/Progression/TrackDefs")

local test, eq, truthy = Harness.test, Harness.eq, Harness.truthy

local FREE: EmoteRules.Scheme = { starterSet = "A", trackUnlocks = false }
local TRACK: EmoteRules.Scheme = { starterSet = "A", trackUnlocks = true }

local function finite(p: Pose.Pose): boolean
	for _, key in Pose.KEYS do
		local v = (p :: any)[key]
		if v ~= v or math.abs(v) == math.huge then
			return false
		end
	end
	return true
end

local function check(over: { [string]: any }?): EmoteRules.Check
	local base: any = {
		emoteId = "wave",
		scheme = FREE,
		tiersOwned = 0,
		hasBody = true,
		inCombat = false,
		now = 10,
		lastAt = nil,
		cooldown = 0.6,
	}
	for k, v in over or {} do
		base[k] = v
	end
	return base
end

-- ===== poses =====

test("emotes: 12 emotes, 4 per set, unique ids and slots", function()
	eq(#Emotes.LIST, 12)
	local seen: { [string]: boolean } = {}
	local perSet: { [string]: { [number]: boolean } } = { A = {}, B = {}, C = {} }
	for _, def in Emotes.LIST do
		truthy(not seen[def.id], "unique id " .. def.id)
		seen[def.id] = true
		truthy(string.match(def.id, "^[a-z]+$") ~= nil, "id is lowercase letters: " .. def.id)
		truthy(#def.id <= 16, "id fits the remote's maxLen")
		truthy(not perSet[def.set][def.slot], "slot used once")
		perSet[def.set][def.slot] = true
	end
	for _, key in Emotes.SETS do
		for slot = 1, 4 do
			truthy(perSet[key][slot], `set {key} has slot {slot}`)
		end
	end
end)

test("emotes: every emote and winner pose is finite and actually moves", function()
	local ids: { string } = {}
	for _, def in Emotes.LIST do
		table.insert(ids, def.id)
	end
	for _, id in ids do
		local moved = false
		local first = Emotes.compute(id, 0.6) :: Pose.Pose
		for i = 0, 60 do
			local p = Emotes.compute(id, i * 0.1) :: Pose.Pose
			truthy(finite(p), `{id} finite at {i * 0.1}`)
			for _, key in Pose.KEYS do
				if math.abs((p :: any)[key] - (first :: any)[key]) > 0.05 then
					moved = true
				end
			end
		end
		truthy(moved, id .. " is not frozen")
	end
	for _, key in Emotes.SETS do
		for i = 0, 40 do
			truthy(finite(Emotes.win(key, i * 0.13)), `win {key} finite`)
		end
	end
end)

test(
	"emotes: unknown id gives nil, negative time is safe, unknown win set falls back to A",
	function()
		eq(Emotes.compute("moonwalk", 1), nil)
		truthy(finite(Emotes.compute("wave", -5) :: Pose.Pose))
		local a = Emotes.win("A", 0.3)
		local odd = Emotes.win("Z", 0.3)
		for _, key in Pose.KEYS do
			eq((odd :: any)[key], (a :: any)[key])
		end
	end
)

test(
	"emotes: shapes read right (wave raises one arm, cheer both, bow bends forward, flex arms out)",
	function()
		local wave = Emotes.compute("wave", 1) :: Pose.Pose
		truthy(wave.aLx < -2.4 and wave.aRx > -0.5, "left hand up, gun hand down")
		local cheer = Emotes.compute("cheer", 1) :: Pose.Pose
		truthy(cheer.aLx < -2.5 and cheer.aRx < -2.5, "both arms up")
		local bow = Emotes.compute("bow", 0.9) :: Pose.Pose
		truthy(bow.tx > 0.6, "bent forward")
		local flex = Emotes.compute("flex", 1) :: Pose.Pose
		truthy(flex.aRz < -1.2 and flex.aLz > 1.2, "arms out to the sides")
		local cool = Emotes.win("C", 1)
		truthy(cool.aRz > 0.5 and cool.aLz < -0.5, "arms crossed in front")
	end
)

test("emotes: the A winner pose matches the character piece's victory", function()
	for _, t in { 0.1, 0.77, 2.3 } do
		local base: any = {
			t = t,
			speed = 0,
			forward = 0,
			alive = true,
			won = true,
		}
		local old = Pose.compute(base)
		local new = Emotes.win("A", t)
		for _, key in Pose.KEYS do
			Harness.near((new :: any)[key], (old :: any)[key], 1e-9, key)
		end
	end
end)

-- ===== rules =====

test("emote rules: carter's pick, all free: every emote is open with no coins", function()
	for _, def in Emotes.LIST do
		truthy(EmoteRules.owns(def.id, FREE, 0), def.id .. " free")
	end
	local list = EmoteRules.list(FREE, 0)
	eq(#list, 12)
	for _, e in list do
		truthy(e.owned)
		eq(e.tier, 0)
	end
end)

test("emote rules: with track unlocks, starter two are free and the rest open by tier", function()
	eq(EmoteRules.tierFor("wave", TRACK), 0)
	eq(EmoteRules.tierFor("shuffle", TRACK), 0)
	eq(EmoteRules.tierFor("flex", TRACK), 2)
	eq(EmoteRules.tierFor("point", TRACK), 4)
	eq(EmoteRules.tierFor("clap", TRACK), 1)
	eq(EmoteRules.tierFor("bow", TRACK), 6)
	truthy(not EmoteRules.owns("flex", TRACK, 1))
	truthy(EmoteRules.owns("flex", TRACK, 2))
	eq(EmoteRules.tierFor("nope", TRACK), nil)
	truthy(not EmoteRules.owns("nope", FREE, 99), "unknown is never owned")
	-- every tier fits the real track
	for _, def in Emotes.LIST do
		truthy((EmoteRules.tierFor(def.id, TRACK) :: number) <= #TrackDefs.tiers)
	end
	-- a different starter set swaps which ones are free
	local b: EmoteRules.Scheme = { starterSet = "B", trackUnlocks = true }
	eq(EmoteRules.tierFor("clap", b), 0)
	eq(EmoteRules.tierFor("wave", b), 1)
	eq(EmoteRules.list(b, 0)[1].id, "clap")
end)

test("emote rules: tiers are counted in track order and stop at the first gap", function()
	local t = TrackDefs.tiers
	eq(EmoteRules.tiersOwned({}), 0)
	eq(EmoteRules.tiersOwned({ [t[1].id] = true, [t[2].id] = true }), 2)
	eq(EmoteRules.tiersOwned({ [t[1].id] = true, [t[3].id] = true }), 1)
	eq(EmoteRules.tiersOwnedFromList({ t[1].id, t[2].id, t[3].id }), 3)
	eq(EmoteRules.tiersOwnedFromList({ "trail_cyan", "made_up" }), 0)
end)

test("emote rules: the server refuses fights, no body, locked, unknown and spam", function()
	truthy((EmoteRules.canPlay(check())))
	local function why(over: { [string]: any }): string?
		local ok, reason = EmoteRules.canPlay(check(over))
		truthy(not ok)
		return reason
	end
	eq(why({ inCombat = true }), "inCombat")
	eq(why({ hasBody = false }), "noBody")
	eq(why({ emoteId = "../../x" }), "unknown")
	eq(why({ emoteId = "point", scheme = TRACK, tiersOwned = 3 }), "locked")
	eq(why({ lastAt = 9.8 }), "cooldown")
	truthy((EmoteRules.canPlay(check({ lastAt = 9.0 }))), "after the cooldown it plays again")
end)

test("emote rules: winner pose picks", function()
	eq(EmoteRules.winPoseFrom("win_B"), "B")
	eq(EmoteRules.winPoseFrom("win_A"), "A")
	eq(EmoteRules.winPoseFrom("win_D"), nil)
	eq(EmoteRules.winPoseFrom("win_"), nil)
	eq(EmoteRules.winPoseFrom("wave"), nil)
	eq(EmoteRules.winPoseFrom("xwin_A"), nil)
	eq(EmoteRules.winPoseOr("C", "A"), "C")
	eq(EmoteRules.winPoseOr(nil, "B"), "B")
	eq(EmoteRules.winPoseOr(42, "nonsense"), "A")
	-- a winner pose id is never an emote
	for _, key in Emotes.SETS do
		eq(Emotes.get(EmoteRules.WIN_PREFIX .. key), nil)
	end
end)
