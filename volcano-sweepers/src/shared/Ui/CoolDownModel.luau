--!strict
-- The Cool Down panel (prestige + Spark Shop) as plain data. Pure: time is a parameter.
--   CoolDownModel.build(source) -> View        source = store view or profile
--   CoolDownModel.newConfirm() / tap / confirmView / cancel   the "tap twice" safety step
--   CoolDownModel.doneText(sparksGained) -> string
-- The client NEVER sends CoolDown without the second tap (see tap); the server checks the rules again.

local Config = require("../Config")
local Economy = require("../Rules/Economy")
local StatsCalc = require("../Rules/StatsCalc")
local SparkPerks = require("../Catalog/SparkPerks")
local Format = require("./Format")

local CoolDownModel = {}

export type Source = { [string]: any }

export type Item = { icon: string, text: string }

export type Perk = {
	id: string,
	name: string,
	desc: string,
	level: number,
	maxLevel: number,
	maxed: boolean,
	nowText: string, -- "Not bought yet" / "+10% treasure luck"
	nextText: string, -- "Next: +20% treasure luck" or ""
	cost: number?, -- Sparks for the next level, nil when maxed
	affordable: boolean,
}

export type View = {
	canCoolDown: boolean,
	justReset: boolean,
	coolDowns: number,
	runCoins: number,
	minCoins: number,
	fraction: number, -- 0..1 progress to the first allowed Cool Down
	progressText: string, -- "1.2M / 9M"
	remainingText: string, -- "Earn 7.8M more coins to unlock" ("" when allowed)
	note: string, -- the one line under the Sparks number: what to do or what you will have next
	sparksNow: number, -- Sparks a Cool Down would give right now
	sparksText: string,
	title: string,
	explain: string,
	sparks: number, -- Sparks in your pocket
	sparksBalanceText: string, -- "You have ✨ 7 Sparks"
	bonus: number, -- coin bonus from all Sparks, 0.35 = +35%
	bonusText: string, -- "+35% coins forever"
	afterBonusText: string, -- "After this: +60% coins forever" ("" when not allowed)
	keep: { Item },
	reset: { Item },
	perks: { Perk },
	perkAffordable: boolean, -- some perk can be bought right now
	badge: boolean,
}

local function num(v: any): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.max(0, v)
end

local function level(map: any, id: string): number
	if type(map) ~= "table" then
		return 0
	end
	return math.floor(num((map :: { [string]: any })[id]))
end

local function plural(n: number, one: string, many: string): string
	return if n == 1 then one else many
end

local function bonusPercent(bonus: number): string
	return `+{math.floor(bonus * 100 + 0.5)}% coins forever`
end

local KEEP: { Item } = {
	{ icon = "📖", text = "Finds Book and set bonuses" },
	{ icon = "✨", text = "Sparks and Spark perks" },
	{ icon = "🎯", text = "Goals and daily streak" },
	{ icon = "📈", text = "Your stats" },
}

local RESET: { Item } = {
	{ icon = "💰", text = "Coins" },
	{ icon = "🧹", text = "Tools" },
	{ icon = "🛠", text = "Upgrades" },
	{ icon = "🚪", text = "Open areas" },
	{ icon = "🤖", text = "Helper bots" },
}

function CoolDownModel.build(source: Source): View
	local runCoins = num(source.runCoins)
	local sparks = math.floor(num(source.sparks))
	local coolDowns = math.floor(num(source.coolDowns))
	local minCoins = Config.Economy.coolDownMinRunCoins
	local perkLevels = source.sparkPerks

	local fakeProfile: any = { runCoins = runCoins }
	local can = Economy.canCoolDown(fakeProfile)
	local sparksNow = Economy.sparksFor(runCoins)
	local fraction = math.clamp(runCoins / minCoins, 0, 1)

	-- the coin bonus counts Sparks you hold plus Sparks you already spent on perks
	local total = sparks + SparkPerks.spent(if type(perkLevels) == "table" then perkLevels else {})
	local bonus = StatsCalc.sparkBonus(total)

	local sparksText: string
	if can then
		sparksText = `You will get ✨ {sparksNow} {plural(sparksNow, "Spark", "Sparks")}!`
	else
		sparksText = `Sparks so far: ✨ {sparksNow}`
	end

	local perks: { Perk } = {}
	local anyAffordable = false
	for _, perk in SparkPerks.list do
		local lv = math.clamp(level(perkLevels, perk.id), 0, perk.maxLevel)
		local cost = SparkPerks.cost(perk.id, lv)
		local affordable = cost ~= nil and sparks >= cost
		if affordable then
			anyAffordable = true
		end
		table.insert(perks, {
			id = perk.id,
			name = perk.name,
			desc = perk.desc,
			level = lv,
			maxLevel = perk.maxLevel,
			maxed = cost == nil,
			nowText = if lv == 0 then "Not bought yet" else SparkPerks.effectText(perk.id, lv),
			nextText = if cost == nil then "" else `Next: {SparkPerks.effectText(perk.id, lv + 1)}`,
			cost = cost,
			affordable = affordable,
		})
	end

	local each = math.floor(Config.Economy.sparkBonusEach * 100 + 0.5)
	local justReset = coolDowns > 0 and fraction < 0.02
	local remaining = if can
		then ""
		else `Earn {Format.compact(math.max(0, minCoins - runCoins))} more coins to unlock`
	local afterBonus = if can
		then `After this: {bonusPercent(StatsCalc.sparkBonus(total + sparksNow))}`
		else ""
	local note = if can
		then afterBonus
		elseif justReset then "Fresh start! Your Sparks are already helping."
		else remaining
	return {
		canCoolDown = can,
		justReset = justReset,
		coolDowns = coolDowns,
		runCoins = runCoins,
		minCoins = minCoins,
		fraction = fraction,
		progressText = `{Format.compact(runCoins)} / {Format.compact(minCoins)}`,
		note = note,
		remainingText = remaining,
		sparksNow = sparksNow,
		sparksText = sparksText,
		title = "Cool the volcano!",
		explain = `Start over, keep your treasure, get Sparks. Each Spark = +{each}% coins forever.`,
		sparks = sparks,
		sparksBalanceText = `You have ✨ {sparks} {plural(sparks, "Spark", "Sparks")}`,
		bonus = bonus,
		bonusText = bonusPercent(bonus),
		afterBonusText = afterBonus,
		keep = KEEP,
		reset = RESET,
		perks = perks,
		perkAffordable = anyAffordable,
		badge = can,
	}
end

function CoolDownModel.doneText(sparksGained: number): string
	local n = math.floor(num(sparksGained))
	if n > 0 then
		return `You got ✨ {n} {plural(n, "Spark", "Sparks")}! The volcano is cooler now.`
	end
	return "The volcano is cooler now."
end

-- The one line in the Cool Down footer, right above the big button (the footer never scrolls
-- away, so the button and its explanation are always on screen together).
--   armed        -> "Are you sure? ... you get ✨ 12 Sparks!"
--   allowed      -> "✨ 12 Sparks now! After this: +60% coins forever"
--   not allowed  -> "Earn 7.8M more coins to unlock"
function CoolDownModel.footerText(view: View, armedNow: boolean): string
	local word = plural(view.sparksNow, "Spark", "Sparks")
	if view.canCoolDown and armedNow then
		return `Are you sure? You start over, but you keep your treasure and get ✨ {view.sparksNow} {word}!`
	elseif view.canCoolDown then
		return `✨ {view.sparksNow} {word} now! {view.afterBonusText}`
	elseif view.justReset then
		return "Fresh start! Your Sparks are already helping."
	end
	return view.remainingText
end

-- ===== the "tap twice" safety step =====
-- idle --tap--> armed (wait 1 s) --tap--> sent.   Armed for too long = back to idle.
CoolDownModel.CONFIRM_DELAY = 1
CoolDownModel.CONFIRM_TIMEOUT = 10

export type Confirm = { armedAt: number? }

function CoolDownModel.newConfirm(): Confirm
	return { armedAt = nil }
end

function CoolDownModel.cancel(c: Confirm)
	c.armedAt = nil
end

local function armed(c: Confirm, now: number): boolean
	local at = c.armedAt
	if at == nil then
		return false
	end
	if now - at >= CoolDownModel.CONFIRM_TIMEOUT or now < at then
		c.armedAt = nil -- stale (or the clock went backwards)
		return false
	end
	return true
end

-- A tap on the big lava button. Returns what to do:
--   "none"   nothing (not allowed, or the second tap came too fast)
--   "armed"  first tap: show the warning and start the 1 second wait
--   "send"   confirmed: send CoolDown to the server (the state goes back to idle)
function CoolDownModel.tap(c: Confirm, now: number, canCoolDown: boolean): string
	if not canCoolDown then
		c.armedAt = nil
		return "none"
	end
	if not armed(c, now) then
		c.armedAt = now
		return "armed"
	end
	local at = c.armedAt :: number
	if now - at < CoolDownModel.CONFIRM_DELAY then
		return "none"
	end
	c.armedAt = nil
	return "send"
end

export type ConfirmView = {
	armed: boolean,
	enabled: boolean, -- false while locked or during the 1 second wait
	text: string,
	warn: boolean, -- show the "are you sure" box and the Not now button
}

function CoolDownModel.confirmView(c: Confirm, now: number, canCoolDown: boolean): ConfirmView
	if not canCoolDown then
		c.armedAt = nil
		return { armed = false, enabled = false, text = "Not yet", warn = false }
	end
	if not armed(c, now) then
		return { armed = false, enabled = true, text = "COOL DOWN", warn = false }
	end
	local at = c.armedAt :: number
	if now - at < CoolDownModel.CONFIRM_DELAY then
		return { armed = true, enabled = false, text = "Wait...", warn = true }
	end
	return { armed = true, enabled = true, text = "YES! COOL DOWN!", warn = true }
end

return CoolDownModel
