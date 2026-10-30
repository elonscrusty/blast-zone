--!strict
local Harness = require("./harness")
local Config = require("../src/shared/Config")
local RemoteDefs = require("../src/shared/RemoteDefs")
local Types = require("../src/shared/Types")
local WalletBarModel = require("../src/shared/Wallet/WalletBarModel")
local WalletDefs = require("../src/shared/Wallet/WalletDefs")
local WalletMemoryStore = require("../src/shared/Wallet/WalletMemoryStore")
local WalletRules = require("../src/shared/Wallet/WalletRules")
local WalletService = require("../src/shared/Wallet/WalletService")

local function newService(scrap: number?)
	local sent: { Types.WalletState } = {}
	local store = WalletMemoryStore.new()
	local service = WalletService.new({
		store = store,
		scrap = function(_player: any): number?
			return scrap
		end,
		send = function(_player: any, state)
			table.insert(sent, state)
		end,
	})
	return service, sent, store
end

local P = { name = "player" }

-- ===== the list =====

Harness.test(
	"wallet: counter ids are saveable and unique, the bar leads with Scrap, scrap is not saved here",
	function()
		local seen: { [string]: boolean } = {}
		for _, def in WalletDefs.list do
			Harness.truthy(string.match(def.id, "^[a-z][a-z0-9_]*$") ~= nil, def.id)
			Harness.truthy(not seen[def.id], "duplicate " .. def.id)
			seen[def.id] = true
			Harness.truthy(#def.short >= 1 and #def.short <= 8, def.id .. " short name")
		end
		Harness.eq(WalletDefs.list[1].id, "scrap")
		Harness.eq(WalletDefs.list[1].name, Config.Rewards.currencyName)
		Harness.eq(WalletDefs.isSaved("scrap"), false)
		Harness.eq(WalletDefs.isSaved("sparks"), true)
		Harness.eq(WalletDefs.isSaved("nope"), false)
	end
)

Harness.test("wallet: nothing here sells counters for Robux or gates play on one", function()
	for _, def in WalletDefs.list do
		local text = string.lower(def.id .. def.name)
		Harness.truthy(string.find(text, "robux") == nil, def.id)
		Harness.truthy(string.find(text, "energy") == nil, def.id)
	end
	for _, n in { Config.Wallet.sparks.win, Config.Wallet.sparks.podium } do
		Harness.truthy(n >= 0 and n <= Config.Wallet.maxGrant, "pay is under the grant cap")
	end
	Harness.truthy(Config.Wallet.sparks.win > Config.Wallet.sparks.podium, "a win pays more")
end)

Harness.test("wallet: the remotes exist with the right direction", function()
	local ask = RemoteDefs.byName.WalletRequest
	local tell = RemoteDefs.byName.WalletState
	Harness.truthy(ask ~= nil and ask.direction == "toServer" and ask.rate ~= nil)
	Harness.truthy(tell ~= nil and tell.direction == "toClient")
end)

-- ===== rules =====

Harness.test("wallet rules: fill repairs bad saved data and keeps unknown counters", function()
	local w = WalletRules.fill({ sparks = -4, future_gems = 7 })
	Harness.eq(w.sparks, 0)
	Harness.eq(w.future_gems, 7)
	Harness.eq(WalletRules.fill({ sparks = 0 / 0 }).sparks, 0)
	Harness.eq(WalletRules.fill({ sparks = 2.5 }).sparks, 0)
	Harness.eq(WalletRules.fill({ sparks = "9" }).sparks, 0)
	Harness.eq(WalletRules.fill({ sparks = 5e9 }).sparks, 0, "absurd number is rejected")
	Harness.eq(WalletRules.fill({ sparks = 12 }).sparks, 12)
end)

Harness.test(
	"wallet rules: add refuses bad amounts, unknown counters and over-cap grants",
	function()
		local w = WalletRules.new()
		for _, bad in { -1, 1.5, 0 / 0, math.huge, Config.Wallet.maxGrant + 1 } do
			Harness.eq(WalletRules.add(w, "sparks", bad).ok, false, tostring(bad))
		end
		Harness.eq(
			WalletRules.add(w, "scrap", 5).reason,
			"unknownCounter",
			"scrap is not ours to write"
		)
		Harness.eq(WalletRules.add(w, "gems", 5).reason, "unknownCounter")
		Harness.eq(w.sparks, 0, "refusals change nothing")
		Harness.eq(WalletRules.add(w, "sparks", 3).ok, true)
		Harness.eq(w.sparks, 3)
	end
)

Harness.test("wallet rules: add stops at the balance cap and never wraps", function()
	local w = WalletRules.new()
	w.sparks = Config.Wallet.maxBalance - 1
	Harness.eq(WalletRules.add(w, "sparks", 10).ok, true)
	Harness.eq(w.sparks, Config.Wallet.maxBalance)
end)

Harness.test("wallet rules: spend is all or nothing", function()
	local w = WalletRules.new()
	w.sparks = 5
	Harness.eq(WalletRules.spend(w, "sparks", 6).reason, "tooPoor")
	Harness.eq(w.sparks, 5)
	Harness.eq(WalletRules.spend(w, "sparks", 0).reason, "badAmount")
	Harness.eq(WalletRules.spend(w, "sparks", -2).reason, "badAmount")
	Harness.eq(WalletRules.spend(w, "sparks", 1.5).reason, "badAmount")
	Harness.eq(WalletRules.spend(w, "scrap", 1).reason, "unknownCounter")
	Harness.eq(WalletRules.spend(w, "sparks", 5).ok, true)
	Harness.eq(w.sparks, 0)
end)

Harness.test("wallet rules: sparks pay a win most, a podium a little, the rest nothing", function()
	Harness.eq(WalletRules.sparksFor(1, true), Config.Wallet.sparks.win)
	Harness.eq(WalletRules.sparksFor(1, false), Config.Wallet.sparks.podium, "shared first")
	Harness.eq(WalletRules.sparksFor(2, false), Config.Wallet.sparks.podium)
	Harness.eq(WalletRules.sparksFor(3, false), Config.Wallet.sparks.podium)
	Harness.eq(WalletRules.sparksFor(4, false), 0)
	Harness.eq(WalletRules.sparksFor(0, false), 0)
end)

-- ===== service =====

Harness.test("wallet service: a match pays sparks once per match key", function()
	local service, sent = newService(40)
	Harness.eq(service.onMatch(P, 1, true, "m:job:1"), true)
	Harness.eq(service.balance(P, "sparks"), Config.Wallet.sparks.win)
	Harness.eq(service.onMatch(P, 1, true, "m:job:1"), false, "same match again pays nothing")
	Harness.eq(service.balance(P, "sparks"), Config.Wallet.sparks.win)
	Harness.eq(service.onMatch(P, 2, false, "m:job:2"), true)
	Harness.eq(service.balance(P, "sparks"), Config.Wallet.sparks.win + Config.Wallet.sparks.podium)
	Harness.eq(#sent, 2, "one push per real change")
end)

Harness.test("wallet service: 4th place pays nothing and sends nothing", function()
	local service, sent = newService(0)
	Harness.eq(service.onMatch(P, 4, false, "m:job:1"), false)
	Harness.eq(service.balance(P, "sparks"), 0)
	Harness.eq(#sent, 0)
end)

Harness.test(
	"wallet service: the key must be unused, and a refused grant leaves no receipt",
	function()
		local service = newService(0)
		local ok, why = service.grant(P, "sparks", Config.Wallet.maxGrant + 1, "k1")
		Harness.eq(ok, false)
		Harness.eq(why, "tooMuch")
		Harness.eq(
			service.grant(P, "sparks", 4, "k1"),
			true,
			"a refused try did not use up the key"
		)
		local again, reason = service.grant(P, "sparks", 4, "k1")
		Harness.eq(again, false)
		Harness.eq(reason, "duplicate")
		Harness.eq(service.balance(P, "sparks"), 4)
	end
)

Harness.test("wallet service: spend lowers the balance and tells the player", function()
	local service, sent = newService(0)
	service.grant(P, "sparks", 10, "k1")
	local ok = service.spend(P, "sparks", 4)
	Harness.eq(ok, true)
	Harness.eq(service.balance(P, "sparks"), 6)
	local sparks = 0
	for _, item in sent[#sent].items do
		if item.id == "sparks" then
			sparks = item.amount
		end
	end
	Harness.eq(sparks, 6)
	local ok2, why = service.spend(P, "sparks", 7)
	Harness.eq(ok2, false)
	Harness.eq(why, "tooPoor")
	Harness.eq(service.balance(P, "sparks"), 6)
end)

Harness.test("wallet service: each player has their own wallet", function()
	local service = newService(0)
	local other = { name = "other" }
	service.grant(P, "sparks", 5, "a")
	Harness.eq(service.balance(other, "sparks"), 0)
end)

Harness.test("wallet service: the list shows Scrap from piece 18 and never invents it", function()
	local service, sent = newService(125)
	service.push(P)
	local state = sent[1]
	Harness.eq(state.status, "temporary")
	Harness.eq(state.items[1].id, "scrap")
	Harness.eq(state.items[1].amount, 125)
	Harness.eq(state.items[2].id, "sparks")
	Harness.eq(state.items[2].amount, 0)
	local unloaded, sent2 = newService(nil)
	unloaded.push(P)
	Harness.eq(sent2[1].items[1].amount, 0, "Scrap not loaded yet shows 0")
	Harness.eq(unloaded.balance(P, "scrap"), nil, "scrap is not a saved counter")
end)

-- ===== bar model =====

Harness.test("wallet bar: short numbers round down and never claim more than you have", function()
	local cases: { [number]: string } = {
		[0] = "0",
		[7] = "7",
		[999] = "999",
		[1000] = "1.0K",
		[1234] = "1.2K",
		[9999] = "9.9K",
		[12345] = "12K",
		[999999] = "999K",
		[1000000] = "1.0M",
		[1500000] = "1.5M",
	}
	for n, text in cases do
		Harness.eq(WalletBarModel.compact(n), text, tostring(n))
	end
	Harness.eq(WalletBarModel.compact(-5), "0")
	Harness.eq(WalletBarModel.compact(12.9), "12")
end)

local function stateOf(scrap: number, sparks: number, status: string?): Types.WalletState
	return {
		status = status or "ready",
		items = {
			{ id = "scrap", name = "Scrap", short = "SCRAP", amount = scrap },
			{ id = "sparks", name = "Sparks", short = "SPARKS", amount = sparks },
		},
	}
end

Harness.test("wallet bar: rows follow the server's list in order", function()
	local rows = WalletBarModel.rows(stateOf(1500, 3))
	Harness.eq(#rows, 2)
	Harness.eq(rows[1].label, "SCRAP")
	Harness.eq(rows[1].text, "1.5K")
	Harness.eq(rows[2].text, "3")
	Harness.eq(#WalletBarModel.rows(nil), 0)
end)

Harness.test(
	"wallet bar: only a counter that went up pops, and never on the first state",
	function()
		Harness.eq(#WalletBarModel.rises(nil, stateOf(10, 1)), 0)
		local rises = WalletBarModel.rises(stateOf(10, 1), stateOf(10, 4))
		Harness.eq(#rises, 1)
		Harness.eq(rises[1].id, "sparks")
		Harness.eq(rises[1].delta, 3)
		Harness.eq(#WalletBarModel.rises(stateOf(10, 4), stateOf(5, 4)), 0, "spending does not pop")
		Harness.eq(#WalletBarModel.rises(stateOf(10, 4), stateOf(10, 4)), 0)
	end
)

Harness.test("wallet bar: says so when numbers are not being saved", function()
	Harness.eq(WalletBarModel.note(stateOf(0, 0)), "")
	Harness.eq(WalletBarModel.note(nil), "")
	Harness.truthy(WalletBarModel.note(stateOf(0, 0, "temporary")) ~= "")
	Harness.truthy(WalletBarModel.note(stateOf(0, 0, "failed")) ~= "")
end)

Harness.test("wallet bar: hidden while fighting, shown in the lobby and after", function()
	Harness.eq(WalletBarModel.visible(nil), true)
	for _, phase in { "Waiting", "Countdown", "Finished", "Results", "Resetting" } do
		Harness.eq(WalletBarModel.visible(phase), true, phase)
	end
	for _, phase in { "Spawning", "Active", "FinalPressure" } do
		Harness.eq(WalletBarModel.visible(phase), false, phase)
	end
end)
