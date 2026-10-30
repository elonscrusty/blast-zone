--!strict
local Harness = require("./harness")
local AnalyticsTracker = require("../src/server/Analytics/AnalyticsTracker")

type Sent = { kind: string, player: any, name: string, value: number, fields: { string } }

local function make()
	local sent: { Sent } = {}
	local now = 0
	local tracker = AnalyticsTracker.new({
		custom = function(player, name, value, fields)
			table.insert(
				sent,
				{ kind = "custom", player = player, name = name, value = value, fields = fields }
			)
		end,
		funnel = function(player, step, stepName)
			table.insert(
				sent,
				{ kind = "funnel", player = player, name = stepName, value = step, fields = {} }
			)
		end,
	}, { "volt_pistol", "arc_mortar" }, function()
		return now
	end)
	return tracker, sent, function(t: number)
		now = t
	end
end

local function count(sent: { Sent }, name: string): number
	local n = 0
	for _, s in sent do
		if s.name == name then
			n += 1
		end
	end
	return n
end

local alice = { name = "alice" }
local bob = { name = "bob" }
local roster = {
	{ id = "p1", kind = "player", player = alice, alive = true },
	{ id = "p2", kind = "player", player = bob, alive = false },
	{ id = "b1", kind = "bot", player = nil, alive = false },
}

Harness.test("match start logs once per human with the bot count", function()
	local tracker, sent = make()
	tracker:matchStarted(1, roster)
	Harness.eq(count(sent, "match_start"), 2)
	Harness.eq(sent[1].value, 3)
	Harness.eq(sent[1].fields[1], "bots1")
end)

Harness.test("match end reports win, out and the duration", function()
	local tracker, sent, setTime = make()
	tracker:matchStarted(1, roster)
	setTime(42.9)
	tracker:matchEnded(1, roster, "win")
	local ends = {}
	for _, s in sent do
		if s.name == "match_end" then
			table.insert(ends, s)
		end
	end
	Harness.eq(#ends, 2)
	Harness.eq(ends[1].fields[1], "win")
	Harness.eq(ends[2].fields[1], "out")
	Harness.eq(ends[1].value, 42)
end)

Harness.test("an old match end is ignored", function()
	local tracker, sent = make()
	tracker:matchStarted(2, roster)
	tracker:matchEnded(1, roster, "win")
	Harness.eq(count(sent, "match_end"), 0)
end)

Harness.test("deaths are counted by cause, and bad labels become other", function()
	local tracker, sent = make()
	tracker:died(alice, "zone", "none", nil)
	tracker:died(alice, "bullet", "bot", "volt_pistol")
	tracker:died(alice, "<script>", "player", "made_up_gun")
	Harness.eq(sent[1].fields[1], "zone")
	Harness.eq(sent[1].fields[3], "none")
	Harness.eq(sent[3].fields[2], "bot")
	Harness.eq(sent[3].fields[3], "volt_pistol")
	local last = sent[#sent - 1]
	Harness.eq(last.fields[1], "other")
	Harness.eq(last.fields[3], "none")
end)

Harness.test("gun picks use known ids only", function()
	local tracker, sent = make()
	tracker:gunPicked(alice, "arc_mortar")
	tracker:gunPicked(alice, "hax")
	Harness.eq(sent[1].fields[1], "arc_mortar")
	Harness.eq(sent[2].fields[1], "other")
end)

Harness.test("funnel steps go once per player, with their number", function()
	local tracker, sent = make()
	tracker:funnelStep(alice, "joined")
	tracker:funnelStep(alice, "joined")
	tracker:funnelStep(bob, "joined")
	tracker:funnelStep(alice, "pressedPlay")
	tracker:funnelStep(alice, "not_a_step")
	Harness.eq(#sent, 3)
	Harness.eq(sent[3].value, 2)
	tracker:forget(alice)
	tracker:funnelStep(alice, "joined")
	Harness.eq(#sent, 4)
end)

Harness.test("events carry no names or ids", function()
	local tracker, sent = make()
	tracker:matchStarted(1, roster)
	tracker:died(alice, "bullet", "player", "volt_pistol")
	for _, s in sent do
		for _, f in s.fields do
			Harness.eq(string.find(f, "alice") == nil and string.find(f, "p1") == nil, true)
		end
	end
end)
