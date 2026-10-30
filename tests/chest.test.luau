--!strict
local Harness = require("./harness")
local ChestDefs = require("../src/shared/Chest/ChestDefs")
local ChestMemoryStore = require("../src/shared/Chest/ChestMemoryStore")
local ChestReveal = require("../src/shared/Chest/ChestReveal")
local ChestRules = require("../src/shared/Chest/ChestRules")
local ChestService = require("../src/shared/Chest/ChestService")
local ChestText = require("../src/shared/Chest/ChestText")
local Config = require("../src/shared/Config")
local ProgressRules = require("../src/shared/Progression/ProgressRules")
local RemoteDefs = require("../src/shared/RemoteDefs")
local TrackDefs = require("../src/shared/Progression/TrackDefs")
local Types = require("../src/shared/Types")

local CAP = Config.Progression.maxMatchGrant
local MAX = Config.Chest.maxStored
local GOAL = Config.Chest.meterGoal

local function low(): number
	return 0
end
local function high(): number
	return 0.999999
end

-- A repeatable stream of numbers in [0, 1).
local function stream(seed: number): () -> number
	local x = seed
	return function(): number
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

local function freshData(kind: string?, n: number?): { [string]: any }
	local chests = ChestRules.new()
	if kind ~= nil then
		chests.owned[kind] = n or 1
	end
	return { chests = chests, progression = ProgressRules.new() }
end

-- ===== the list =====

Harness.test("chest defs: odds add up to 100, ids are unique, every row is real", function()
	for _, kind in ChestDefs.kinds do
		local chest = ChestDefs.chests[kind]
		Harness.eq(chest.id, kind)
		Harness.truthy(chest.items >= 1 and chest.items <= 5, kind .. " items")
		local total = 0
		local seen: { [string]: boolean } = {}
		for _, row in chest.rows do
			total += row.weight
			Harness.truthy(row.weight > 0, row.id .. " weight")
			Harness.truthy(not seen[row.id], "duplicate " .. row.id)
			seen[row.id] = true
			Harness.truthy(
				table.find(ChestDefs.rarityOrder, row.rarity) ~= nil,
				row.id .. " rarity"
			)
			if row.kind == "scrap" then
				local amount = row.amount or 0
				Harness.truthy(amount >= 1 and amount <= CAP, row.id .. " scrap over the grant cap")
			else
				local def = TrackDefs.get(row.itemId or "")
				Harness.truthy(def ~= nil, row.id .. " is not a real look")
				Harness.truthy(def ~= nil and def.cost == -1, row.id .. " must be not-for-sale")
			end
		end
		Harness.eq(total, 100, kind .. " weights")
	end
end)

Harness.test("chest defs: a Neon Chest is better than a Street Chest, repeats pay Scrap", function()
	Harness.truthy(ChestDefs.chests.neon.items > ChestDefs.chests.street.items)
	for _, rarity in ChestDefs.rarityOrder do
		local pay = ChestDefs.dupeScrap[rarity]
		Harness.truthy(pay ~= nil and pay >= 1 and pay <= CAP, rarity .. " dupe pay")
	end
	Harness.truthy(ChestDefs.dupeScrap.epic > ChestDefs.dupeScrap.rare)
end)

Harness.test("chest config: the reveal styles exist", function()
	Harness.truthy(ChestReveal.styles[Config.Chest.revealStyle] ~= nil)
	Harness.truthy(ChestReveal.styles[Config.Chest.reduceMotionStyle] ~= nil)
	Harness.truthy(Config.Chest.meterGoal >= 2)
end)

Harness.test("chest remotes: ask are limited, the state is told, nothing else is open", function()
	local open = RemoteDefs.byName.ChestOpenRequest
	Harness.truthy(open ~= nil and open.direction == "toServer" and open.rate ~= nil)
	Harness.truthy(RemoteDefs.byName.ChestRequest.direction == "toServer")
	Harness.truthy(RemoteDefs.byName.ChestState.direction == "toClient")
end)

-- ===== odds are shown =====

Harness.test("chest text: every row is listed with its percent, rarest first", function()
	for _, kind in ChestDefs.kinds do
		local lines = ChestText.oddsLines(kind, "Scrap")
		Harness.eq(#lines, #ChestDefs.chests[kind].rows)
		Harness.truthy(string.find(lines[1], "Epic", 1, true) ~= nil, "rarest first: " .. lines[1])
		Harness.truthy(string.find(lines[#lines], "Common", 1, true) ~= nil, "common last")
		local sum = 0
		for _, line in lines do
			local pct = string.match(line, "(%d+)%%$")
			Harness.truthy(pct ~= nil, "no percent in: " .. line)
			sum += tonumber(pct) :: number
		end
		Harness.eq(sum, 100, kind .. " percents")
	end
	Harness.eq(#ChestText.oddsLines("nope", "Scrap"), 0)
end)

Harness.test("chest text: prizes, the meter and refusals read plainly", function()
	Harness.eq(
		ChestText.prize({ kind = "scrap", name = "Scrap", amount = 30, dupe = false }, "Scrap"),
		"+30 Scrap"
	)
	Harness.eq(
		ChestText.prize({ kind = "look", name = "Lime Flash", dupe = false }, "Scrap"),
		"Lime Flash"
	)
	Harness.truthy(
		string.find(
			ChestText.prize(
				{ kind = "scrap", name = "Lime Flash", amount = 40, dupe = true },
				"Scrap"
			),
			"+40",
			1,
			true
		) ~= nil
	)
	Harness.eq(ChestText.meter(GOAL, GOAL), "Free chest ready!")
	Harness.eq(ChestText.meter(GOAL - 1, GOAL), "1 more match = free chest")
	Harness.eq(ChestText.deny("none"), "No chest to open")
	Harness.eq(ChestText.deny("whatever"), "Try again")
end)

-- ===== earning =====

Harness.test("chest rules: first place gives Neon, top 3 gives Street, 4th gives none", function()
	local s = ChestRules.new()
	Harness.eq(table.concat(ChestRules.forMatch(s, 1, true, GOAL, MAX), ","), "neon")
	Harness.eq(table.concat(ChestRules.forMatch(s, 3, false, GOAL, MAX), ","), "street")
	Harness.eq(#ChestRules.forMatch(s, 4, false, GOAL, MAX), 0)
	Harness.eq(ChestRules.count(s, "neon"), 1)
	Harness.eq(ChestRules.count(s, "street"), 1)
end)

Harness.test(
	"chest rules: every few matches give a free Street Chest, even in last place",
	function()
		local s = ChestRules.new()
		for i = 1, GOAL - 1 do
			Harness.eq(#ChestRules.forMatch(s, 8, false, GOAL, MAX), 0, "match " .. i)
		end
		Harness.eq(s.meter, GOAL - 1)
		Harness.eq(table.concat(ChestRules.forMatch(s, 8, false, GOAL, MAX), ","), "street")
		Harness.eq(s.meter, 0)
	end
)

Harness.test("chest rules: a full pocket gives nothing and the meter waits", function()
	local s = ChestRules.new()
	s.owned.street = MAX
	s.meter = GOAL - 1
	Harness.eq(#ChestRules.forMatch(s, 8, false, GOAL, MAX), 0)
	Harness.eq(s.meter, GOAL, "meter waits at the goal")
	Harness.eq(s.owned.street, MAX)
	s.owned.street = MAX - 1
	Harness.eq(#ChestRules.forMatch(s, 8, false, GOAL, MAX), 1)
	Harness.eq(s.meter, 0)
end)

Harness.test("chest rules: award refuses unknown kinds and a full pocket", function()
	local s = ChestRules.new()
	local ok, why = ChestRules.award(s, "gold", MAX)
	Harness.eq(ok, false)
	Harness.eq(why, "badKind")
	s.owned.neon = MAX
	ok, why = ChestRules.award(s, "neon", MAX)
	Harness.eq(ok, false)
	Harness.eq(why, "full")
end)

Harness.test("chest rules: saved junk is repaired and unknown kinds are kept", function()
	local s = ChestRules.fill({
		owned = { street = -3, neon = 2.5, future = 4 },
		meter = "x",
		opened = 1e12,
	})
	Harness.eq(s.owned.street, 0)
	Harness.eq(s.owned.neon, 0)
	Harness.eq(s.owned.future, 4)
	Harness.eq(s.meter, 0)
	Harness.eq(s.opened, 0)
	Harness.eq(ChestRules.fill({}).meter, 0)
end)

-- ===== opening =====

Harness.test("chest rules: the pick follows the weights from first row to last", function()
	local chest = ChestDefs.chests.street
	Harness.eq(ChestRules.pick(chest, low).id, chest.rows[1].id)
	Harness.eq(ChestRules.pick(chest, high).id, chest.rows[#chest.rows].id)
	Harness.eq(ChestRules.pick(chest, function()
		return 0 / 0
	end).id ~= nil, true) -- a bad number never errors
	Harness.eq(
		ChestRules.pick(chest, function()
			return -5
		end).id,
		chest.rows[1].id
	)
end)

Harness.test("chest rules: 20000 rolls land near the shown odds", function()
	for _, kind in ChestDefs.kinds do
		local chest = ChestDefs.chests[kind]
		local rng = stream(7)
		local counts: { [string]: number } = {}
		local n = 20000
		for _ = 1, n do
			local row = ChestRules.pick(chest, rng)
			counts[row.id] = (counts[row.id] or 0) + 1
		end
		for _, row in chest.rows do
			local got = (counts[row.id] or 0) / n * 100
			Harness.truthy(
				math.abs(got - row.weight) < 1.5,
				`{kind} {row.id}: shown {row.weight}%, rolled {got}%`
			)
		end
	end
end)

Harness.test("chest open: takes one chest, pays every prize, counts it", function()
	local data = freshData("street", 2)
	local r = ChestRules.open(data, "street", low, CAP) -- low = the first row: 15 Scrap, twice
	Harness.eq(r.ok, true)
	Harness.eq(#r.prizes, ChestDefs.chests.street.items)
	Harness.eq(data.progression.coins, 30)
	Harness.eq(data.progression.totalEarned, 30)
	Harness.eq(data.chests.owned.street, 1)
	Harness.eq(data.chests.opened, 1)
	Harness.eq(r.prizes[1].kind, "scrap")
	Harness.eq(r.prizes[1].amount, 15)
end)

Harness.test(
	"chest open: a new look is owned and can be worn; a repeat turns into Scrap",
	function()
		local data = freshData("street", 2)
		-- high = the last row of the street chest: Sunset Shot (epic), twice.
		local r = ChestRules.open(data, "street", high, CAP)
		Harness.eq(r.ok, true)
		Harness.eq(r.prizes[1].kind, "look")
		Harness.eq(r.prizes[1].itemId, "tracer_sunset")
		Harness.eq(r.prizes[1].dupe, false)
		Harness.eq(r.prizes[2].kind, "scrap", "second copy in the same chest is a repeat")
		Harness.eq(r.prizes[2].dupe, true)
		Harness.eq(r.prizes[2].amount, ChestDefs.dupeScrap.epic)
		Harness.eq(data.progression.coins, ChestDefs.dupeScrap.epic)
		Harness.eq(data.progression.unlocked.tracer_sunset, true)
		Harness.eq(ProgressRules.equip(data.progression, "tracer_sunset").ok, true)
		-- The next chest: both are repeats now.
		local again = ChestRules.open(data, "street", high, CAP)
		Harness.eq(again.ok, true)
		Harness.eq(again.prizes[1].dupe, true)
		Harness.eq(again.prizes[2].dupe, true)
	end
)

Harness.test("chest open: no chest, wrong kind, or junk changes nothing", function()
	local data = freshData(nil)
	local r = ChestRules.open(data, "street", low, CAP)
	Harness.eq(r.ok, false)
	Harness.eq(r.reason, "none")
	Harness.eq(ChestRules.open(data, "gold", low, CAP).reason, "badKind")
	Harness.eq(ChestRules.open(data, 5, low, CAP).reason, "badKind")
	Harness.eq(ChestRules.open(data, nil, low, CAP).reason, "badKind")
	Harness.eq(data.progression.coins, 0)
	Harness.eq(data.chests.opened, 0)
	local s2 = freshData("neon", 1)
	Harness.eq(
		ChestRules.open(s2, "street", low, CAP).reason,
		"none",
		"you cannot open a kind you do not own"
	)
	Harness.eq(s2.chests.owned.neon, 1)
end)

Harness.test("chest open: all or nothing when the Scrap total would overflow", function()
	local data = freshData("street", 1)
	data.progression.coins = 1e9 - 10
	local r = ChestRules.open(data, "street", low, CAP)
	Harness.eq(r.ok, false)
	Harness.eq(r.reason, "full")
	Harness.eq(data.progression.coins, 1e9 - 10)
	Harness.eq(data.chests.owned.street, 1, "the chest is kept")
	Harness.eq(data.chests.opened, 0)
end)

Harness.test("chest open: a prize over the grant cap is refused whole", function()
	local data = freshData("neon", 1)
	local r = ChestRules.open(data, "neon", low, 20) -- cap below the first prize (30)
	Harness.eq(r.ok, false)
	Harness.eq(r.reason, "tooMuch")
	Harness.eq(data.progression.coins, 0)
	Harness.eq(data.chests.owned.neon, 1)
end)

-- ===== service =====

local function newService(seed: number?)
	local store = ChestMemoryStore.new()
	local sent: { Types.ChestState } = {}
	local changes = 0
	local service = ChestService.new({
		store = store,
		send = function(_player: any, state: Types.ChestState)
			table.insert(sent, state)
		end,
		random = stream(seed or 3),
		maxStored = MAX,
		meterGoal = GOAL,
		maxGrant = CAP,
		changed = function(_player: any)
			changes += 1
		end,
	})
	return service, store, sent, function(): number
		return changes
	end
end

local ANNA = { name = "anna" }

Harness.test("chest service: a match gives chests once per key", function()
	local service, _, sent = newService()
	Harness.eq(table.concat(service.onMatch(ANNA, 1, true, "m1:chest"), ","), "neon")
	Harness.eq(#service.onMatch(ANNA, 1, true, "m1:chest"), 0, "the same match twice gives nothing")
	local last = sent[#sent]
	Harness.eq(last.owned.neon, 1)
	Harness.eq(last.owned.street, 0)
	Harness.eq(last.meter, 1)
	Harness.eq(last.meterGoal, GOAL)
	Harness.eq(#sent, 1, "no second message for the repeat")
end)

Harness.test(
	"chest service: a match with no chest still moves the meter and says nothing new",
	function()
		local service, _, sent = newService()
		service.onMatch(ANNA, 7, false, "m2:chest")
		local last = sent[#sent]
		Harness.eq(last.meter, 1)
		Harness.eq(last.justAwarded, nil)
	end
)

Harness.test(
	"chest service: opening sends the prizes, pays them, and a second open needs a second chest",
	function()
		local service, store, sent, changes = newService()
		service.award(ANNA, "street", "gift1")
		Harness.eq(service.open(ANNA, "street"), true)
		local last = sent[#sent]
		Harness.truthy(last.reveal ~= nil)
		local reveal = last.reveal :: Types.ChestReveal
		Harness.eq(reveal.kind, "street")
		Harness.eq(#reveal.prizes, 2)
		Harness.eq(reveal.id, 1)
		Harness.eq(last.owned.street, 0)
		Harness.eq(changes(), 1, "the coin screen is told")
		local paid = 0
		for _, prize in reveal.prizes do
			paid += prize.amount or 0
		end
		local data = (store :: any).peek(ANNA)
		Harness.eq(data.progression.coins, paid)
		Harness.eq(service.open(ANNA, "street"), false, "double tap: no chest left")
		Harness.eq(sent[#sent].denied, "none")
		Harness.eq(sent[#sent].reveal, nil)
		Harness.eq((store :: any).peek(ANNA).progression.coins, paid, "nothing paid twice")
	end
)

Harness.test("chest service: reveal ids go up so the screen never plays one twice", function()
	local service, _, sent = newService()
	service.award(ANNA, "street", "a")
	service.award(ANNA, "street", "b")
	service.open(ANNA, "street")
	local first = (sent[#sent].reveal :: Types.ChestReveal).id
	service.open(ANNA, "street")
	local second = (sent[#sent].reveal :: Types.ChestReveal).id
	Harness.truthy(second > first)
end)

Harness.test("chest service: award pays once per key and respects the pocket limit", function()
	local service, _, sent = newService()
	local ok = service.award(ANNA, "neon", "login:5")
	Harness.eq(ok, true)
	local ok2, why = service.award(ANNA, "neon", "login:5")
	Harness.eq(ok2, false)
	Harness.eq(why, "duplicate")
	local ok3, why3 = service.award(ANNA, "gold", "x")
	Harness.eq(ok3, false)
	Harness.eq(why3, "badKind")
	for i = 1, MAX do
		service.award(ANNA, "neon", "fill" .. i)
	end
	local ok4, why4 = service.award(ANNA, "neon", "one-more")
	Harness.eq(ok4, false)
	Harness.eq(why4, "full")
	Harness.eq(sent[#sent].owned.neon, MAX)
end)

Harness.test("chest service: a bad kind from a client is refused and told so", function()
	local service, _, sent = newService()
	Harness.eq(service.open(ANNA, "../etc"), false)
	Harness.eq(sent[#sent].denied, "badKind")
	Harness.eq(service.open(ANNA, 12), false)
	Harness.eq(service.open(ANNA, nil), false)
end)

Harness.test("chest service: each player has their own chests", function()
	local service, _, sent = newService()
	local bob = { name = "bob" }
	service.award(ANNA, "street", "k1")
	service.push(bob)
	Harness.eq(sent[#sent].owned.street, 0)
	Harness.eq(service.open(bob, "street"), false)
end)

-- ===== reveal timing =====

local function prizes(...: string): { ChestReveal.Prize }
	local out = {}
	for _, r in { ... } do
		table.insert(out, { rarity = r })
	end
	return out
end

Harness.test("chest reveal: style A shows the best prize last", function()
	local style = ChestReveal.styles.A
	local order = ChestReveal.orderOf(style, prizes("epic", "common", "rare"))
	Harness.eq(table.concat(order, ","), "2,3,1")
	local rolled = ChestReveal.orderOf(ChestReveal.styles.B, prizes("epic", "common", "rare"))
	Harness.eq(table.concat(rolled, ","), "1,2,3", "style B keeps the rolled order")
	local tie = ChestReveal.orderOf(style, prizes("common", "common", "rare"))
	Harness.eq(table.concat(tie, ","), "1,2,3", "ties keep the rolled order")
end)

Harness.test("chest reveal: shake, then prizes one by one, then done", function()
	local m = ChestReveal.new("A", prizes("common", "rare", "epic"))
	Harness.eq(ChestReveal.phase(m), "shaking")
	Harness.eq(ChestReveal.shown(m), 0)
	ChestReveal.tick(m, m.style.shake + m.style.burst + 0.01)
	Harness.eq(ChestReveal.phase(m), "showing")
	Harness.eq(ChestReveal.shown(m), 1)
	ChestReveal.tick(m, m.style.gap)
	Harness.eq(ChestReveal.shown(m), 2)
	ChestReveal.tick(m, m.style.gap)
	Harness.eq(ChestReveal.shown(m), 3)
	Harness.eq(ChestReveal.phase(m), "done")
end)

Harness.test("chest reveal: style B shows everything at once", function()
	local m = ChestReveal.new("B", prizes("common", "rare", "epic"))
	ChestReveal.tick(m, m.style.shake + m.style.burst + 0.01)
	Harness.eq(ChestReveal.shown(m), 3)
	Harness.eq(ChestReveal.phase(m), "done")
end)

Harness.test(
	"chest reveal: a tap skips to the end, then waits a moment before it continues",
	function()
		local m = ChestReveal.new("A", prizes("common", "rare"))
		ChestReveal.tick(m, 0.2)
		Harness.eq(ChestReveal.tap(m), "skipped")
		Harness.eq(ChestReveal.phase(m), "done")
		Harness.eq(ChestReveal.shown(m), 2)
		Harness.eq(ChestReveal.tap(m), nil, "the quick second tap is ignored")
		ChestReveal.tick(m, ChestReveal.TAP_LOCK + 0.01)
		Harness.eq(ChestReveal.tap(m), "continue")
	end
)

Harness.test("chest reveal: no prizes, bad styles and bad time do not break it", function()
	local m = ChestReveal.new("Z", {})
	Harness.eq(m.style.name, ChestReveal.styles.A.name, "unknown style falls back to A")
	ChestReveal.tick(m, -5)
	ChestReveal.tick(m, 0 / 0)
	Harness.eq(m.elapsed, 0)
	ChestReveal.tick(m, 10)
	Harness.eq(ChestReveal.phase(m), "done")
	Harness.eq(ChestReveal.shown(m), 0)
end)

Harness.test("chest reveal: every style is quick enough for a phone player", function()
	for id, style in ChestReveal.styles do
		local m = ChestReveal.new(id, prizes("common", "common", "common"))
		Harness.truthy(m.doneAt <= 3, id .. " takes " .. m.doneAt .. "s")
	end
end)
