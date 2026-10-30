--!strict
-- piece 46: big moments. Banner words and order, the one-at-a-time queue, name plate view, level-up
-- detection, and that every look (A, B, C) only asks for colour roles that exist.
local fs = require("@lune/fs")
local Harness = require("./harness")
local BannerQueue = require("../src/shared/Moments/BannerQueue")
local Config = require("../src/shared/Config")
local Layout = require("../src/client/Hud/Layout")
local MomentRules = require("../src/shared/Moments/MomentRules")
local MomentStyles = require("../src/client/Ui/MomentStyles")
local PlateRules = require("../src/shared/Moments/PlateRules")
local RemoteDefs = require("../src/shared/RemoteDefs")
local Tokens = require("../src/client/Ui/Tokens")

local function streak(tier: string, actor: string, n: number, heal: number?): any
	return {
		kind = "streak",
		matchId = 3,
		tier = tier,
		streak = n,
		actorId = actor,
		actorName = "Volt",
		heal = heal,
	}
end

local function banner(p: any, me: string?): MomentRules.Banner?
	return MomentRules.banner(p, me or "p1", 16)
end

-- ===== banner words =====

Harness.test("moments: your own double kill says DOUBLE KILL and the health you got", function()
	local b = banner(streak("double", "p1", 2, 15)) :: MomentRules.Banner
	Harness.eq(b.title, "DOUBLE KILL")
	Harness.eq(b.subtitle, "+15 HP")
	Harness.eq(b.mine, true)
	Harness.eq(b.emblem, "x2")
end)

Harness.test("moments: someone else's double or triple is not shown to you", function()
	Harness.eq(banner(streak("double", "b2", 2, 15)), nil)
	Harness.eq(banner(streak("triple", "b2", 3, 20)), nil)
end)

Harness.test("moments: a spree is shouted to everyone with the name", function()
	local other = banner(streak("spree", "b2", 5, 30)) :: MomentRules.Banner
	Harness.eq(other.title, "Volt IS ON A SPREE")
	Harness.eq(other.subtitle, "5 in a row")
	Harness.eq(other.mine, false)
	local mine = banner(streak("spree", "p1", 5, 30)) :: MomentRules.Banner
	Harness.eq(mine.title, "KILLING SPREE")
end)

Harness.test("moments: zone banners and sudden death", function()
	local z = banner({ kind = "zoneClosing", matchId = 3, stage = 2 }) :: MomentRules.Banner
	Harness.eq(z.title, "CIRCLE CLOSING")
	Harness.eq(z.tone, "info")
	local s = banner({ kind = "suddenDeath", matchId = 3, stage = 99 }) :: MomentRules.Banner
	Harness.eq(s.title, "SUDDEN DEATH")
	Harness.truthy(s.priority > z.priority, "sudden death must outrank the circle")
end)

Harness.test("moments: importance goes double < triple < spree < sudden death", function()
	local k = MomentRules.kinds
	Harness.truthy(k.zoneClosing.priority < k.double.priority)
	Harness.truthy(k.double.priority < k.triple.priority)
	Harness.truthy(k.triple.priority < k.spree.priority)
	Harness.truthy(k.spree.priority < k.suddenDeath.priority)
end)

Harness.test("moments: bad payloads are dropped, never guessed", function()
	local bad: { any } = {
		"hello",
		{},
		{ kind = "streak", matchId = 1 },
		{
			kind = "streak",
			matchId = 1,
			tier = "quad",
			streak = 4,
			actorId = "p1",
			actorName = "A",
		},
		{
			kind = "streak",
			matchId = 1,
			tier = "double",
			streak = -1,
			actorId = "p1",
			actorName = "A",
		},
		{
			kind = "streak",
			matchId = 1,
			tier = "double",
			streak = 2,
			actorId = "p1",
			actorName = "",
		},
		{ kind = "boom", matchId = 1 },
		{ kind = "zoneClosing", matchId = "1" },
		{ kind = "zoneClosing", matchId = 1, stage = 0 / 0 },
		{ kind = "zoneClosing", matchId = 1, stage = 1.5 },
	}
	for i, p in bad do
		Harness.eq(banner(p), nil, `bad payload {i} was accepted`)
	end
end)

Harness.test("moments: long names are cut on letters, never in the middle of one", function()
	Harness.eq(MomentRules.shortName("Volt", 16), "Volt")
	Harness.eq(MomentRules.shortName("ABCDEFGHIJKLMNOPQRST", 10), "ABCDEFGHI...")
	Harness.eq(MomentRules.shortName("ÅÅÅÅÅÅÅÅÅÅÅÅ", 5), "ÅÅÅÅ...")
	Harness.eq(MomentRules.shortName("\xff\xfe", 5), "?")
end)

Harness.test("moments: every streak tier names a banner that exists", function()
	for _, tier in Config.Streaks.tiers do
		Harness.truthy(
			MomentRules.kinds[tier.moment] ~= nil,
			"tier at " .. tier.at .. " has no banner"
		)
		Harness.eq(type(tier.announceAll), "boolean")
	end
end)

-- ===== one banner at a time =====

local function queue()
	return BannerQueue.new(Config.Moments)
end

local function news(key: string, priority: number): MomentRules.Banner
	return {
		key = key,
		kind = "double",
		title = key,
		tone = "accent",
		emblem = "x2",
		priority = priority,
		mine = true,
	}
end

Harness.test("banner queue: first banner shows at once, then ends on time", function()
	local q = queue()
	BannerQueue.push(q, news("a", 2), 10)
	local shown, fresh = BannerQueue.update(q, 10)
	Harness.eq((shown :: MomentRules.Banner).key, "a")
	Harness.eq(fresh, true)
	local _, again = BannerQueue.update(q, 10.1)
	Harness.eq(again, false, "fresh must be told once")
	local gone = BannerQueue.update(q, 10 + Config.Moments.bannerSeconds + 0.01)
	Harness.eq(gone, nil)
end)

Harness.test("banner queue: a weaker banner waits, a stronger one takes the screen", function()
	local q = queue()
	BannerQueue.push(q, news("a", 2), 10)
	BannerQueue.update(q, 10)
	BannerQueue.push(q, news("weak", 1), 10.5)
	Harness.eq((BannerQueue.update(q, 10.6) :: any).key, "a")
	BannerQueue.push(q, news("strong", 5), 10.7)
	local shown, fresh = BannerQueue.update(q, 10.8)
	Harness.eq((shown :: MomentRules.Banner).key, "strong")
	Harness.eq(fresh, true)
end)

Harness.test(
	"banner queue: waiting banners come in order of importance after a quiet gap",
	function()
		local q = queue()
		BannerQueue.push(q, news("first", 3), 0)
		BannerQueue.update(q, 0)
		BannerQueue.push(q, news("low", 1), 0.5)
		BannerQueue.push(q, news("mid", 2), 0.6)
		local endsAt = Config.Moments.bannerSeconds
		Harness.eq(BannerQueue.update(q, endsAt + 0.01), nil, "the gap between banners was skipped")
		local shown = BannerQueue.update(q, endsAt + Config.Moments.minGapSeconds + 0.01)
		Harness.eq((shown :: MomentRules.Banner).key, "mid")
	end
)

Harness.test("banner queue: old news is dropped, repeats are ignored, the line is short", function()
	local q = queue()
	BannerQueue.push(q, news("a", 3), 0)
	BannerQueue.update(q, 0)
	BannerQueue.push(q, news("a", 3), 0.2) -- same news again
	Harness.eq(#q.waiting, 0)
	BannerQueue.push(q, news("old", 1), 0.5)
	local late = Config.Moments.bannerSeconds + Config.Moments.staleSeconds + 1
	Harness.eq(BannerQueue.update(q, late), nil, "stale news was shown")
	for i = 1, 10 do
		BannerQueue.push(q, news("k" .. i, 1), late + 0.1)
	end
	Harness.truthy(#q.waiting <= Config.Moments.queueMax, "line grew past queueMax")
end)

Harness.test("banner queue: progress runs 0 to 1 and clear empties it", function()
	local q = queue()
	BannerQueue.push(q, news("a", 2), 5)
	BannerQueue.update(q, 5)
	Harness.near(BannerQueue.progress(q, 5), 0)
	Harness.near(BannerQueue.progress(q, 5 + Config.Moments.bannerSeconds / 2), 0.5)
	BannerQueue.clear(q)
	Harness.eq(BannerQueue.update(q, 5.1), nil)
end)

-- ===== name plates =====

local plateCfg: PlateRules.Config =
	{ maxNameLength = 8, lowHealthFraction = 0.3, showOwnPlate = false }

local function attrs(over: { [string]: any }?): PlateRules.Attributes
	local a: any = { Health = 80, MaxHealth = 100, Alive = true, Level = 4, PlateName = "Volt" }
	for k, v in over or {} do
		a[k] = v
	end
	return a
end

Harness.test("plates: a living enemy shows name, level and bar", function()
	local v = PlateRules.view(attrs(), false, plateCfg)
	Harness.eq(v.visible, true)
	Harness.eq(v.name, "Volt")
	Harness.eq(v.levelText, "4")
	Harness.near(v.fraction, 0.8)
	Harness.eq(v.low, false)
end)

Harness.test("plates: always on at full health (not only after a hit)", function()
	Harness.eq(PlateRules.view(attrs({ Health = 100 }), false, plateCfg).visible, true)
end)

Harness.test("plates: hidden for the dead, for yourself, and before the server speaks", function()
	Harness.eq(PlateRules.view(attrs({ Alive = false }), false, plateCfg).visible, false)
	Harness.eq(PlateRules.view(attrs(), true, plateCfg).visible, false)
	Harness.eq(
		PlateRules.view(
			attrs(),
			true,
			{ maxNameLength = 8, lowHealthFraction = 0.3, showOwnPlate = true }
		).visible,
		true
	)
	Harness.eq(PlateRules.view(attrs({ Health = false }), false, plateCfg).visible, false)
	Harness.eq(PlateRules.view(attrs({ MaxHealth = 0 }), false, plateCfg).visible, false)
end)

Harness.test("plates: low health, odd numbers and odd names stay safe", function()
	Harness.eq(PlateRules.view(attrs({ Health = 25 }), false, plateCfg).low, true)
	Harness.near(PlateRules.view(attrs({ Health = 500 }), false, plateCfg).fraction, 1)
	Harness.near(PlateRules.view(attrs({ Health = -5 }), false, plateCfg).fraction, 0)
	Harness.eq(PlateRules.view(attrs({ PlateName = false }), false, plateCfg).name, "?")
	Harness.eq(
		PlateRules.view(attrs({ PlateName = "VeryLongPlayerName" }), false, plateCfg).name,
		"VeryLon..."
	)
	Harness.eq(PlateRules.levelText(nil), "1")
	Harness.eq(PlateRules.levelText(0 / 0), "1")
	Harness.eq(PlateRules.levelText(12.7), "12")
	Harness.eq(PlateRules.levelText(500), "99+")
end)

Harness.test("plates: only a rising level bursts, and the first number seen never does", function()
	Harness.eq(PlateRules.leveledUp(nil, 1), false, "arrival counted as a level-up")
	Harness.eq(PlateRules.leveledUp(3, 3), false)
	Harness.eq(PlateRules.leveledUp(4, 3), false)
	Harness.eq(PlateRules.leveledUp(3, 4), true)
	Harness.eq(PlateRules.leveledUp(3, nil), false)
	Harness.eq(PlateRules.leveledUp("3", 4), false)
end)

Harness.test("plates: the ring sits on the floor, own ring and enemy rings are separate", function()
	-- root 5 studs up, 2 tall, hips 2: the floor is at 5 - 2 - 1 = 2
	Harness.near(PlateRules.floorY(5, 2, 2), 2)
	Harness.eq(PlateRules.wantsRing(true, true, false), true)
	Harness.eq(PlateRules.wantsRing(false, true, false), false)
	Harness.eq(PlateRules.wantsRing(false, true, true), true)
	Harness.eq(PlateRules.wantsRing(true, false, true), false)
	Harness.near(PlateRules.burstProgress(0.35, 0.7), 0.5)
	Harness.near(PlateRules.burstProgress(5, 0.7), 1)
	Harness.near(PlateRules.easeOut(0), 0)
	Harness.near(PlateRules.easeOut(1), 1)
end)

-- ===== looks and wiring =====

Harness.test("looks: A, B and C only ask for colour roles that exist", function()
	local known: { [string]: boolean } = {}
	for _, key in Tokens.COLOR_KEYS do
		known[key] = true
	end
	local function role(style: string, where: string, name: any)
		Harness.truthy(
			type(name) == "string" and known[name],
			`{style}.{where} uses unknown colour role {name}`
		)
	end
	Harness.eq(#MomentStyles.ids, 3)
	for _, id in MomentStyles.ids do
		local s: any = MomentStyles.list[id]
		Harness.eq(s.id, id)
		for _, key in
			{ "fill", "outline", "ink", "barFill", "barLow", "barTrack", "badgeFill", "badgeInk" }
		do
			role(id, "plate." .. key, s.plate[key])
		end
		role(id, "ring.mine", s.ring.mine)
		role(id, "ring.other", s.ring.other)
		for _, key in { "fill", "ink", "outline", "subtitleInk" } do
			role(id, "banner." .. key, s.banner[key])
		end
		role(id, "burst.ring", s.burst.ring)
		role(id, "burst.arrowInk", s.burst.arrowInk)
		role(id, "burst.arrowOutline", s.burst.arrowOutline)
		Harness.truthy(#s.burst.colors >= 1)
		for _, c in s.burst.colors do
			role(id, "burst.colors", c)
		end
		Harness.truthy(s.plate.badgeSide == "left" or s.plate.badgeSide == "top")
		Harness.truthy(s.plate.fillAlpha >= 0 and s.plate.fillAlpha <= 1)
		Harness.truthy(s.plate.corner >= 0 and s.plate.corner <= 0.5)
		Harness.truthy(s.banner.corner >= 0 and s.banner.corner <= 0.5)
		Harness.truthy(s.ring.transparency >= 0 and s.ring.transparency < 1)
	end
	Harness.eq(MomentStyles.get("nope").id, "A", "an unknown style must fall back")
	Harness.truthy(
		MomentStyles.list[Config.Moments.style] ~= nil,
		"Config.Moments.style is not a look"
	)
end)

Harness.test("looks: banner tones are colour roles too", function()
	local known: { [string]: boolean } = {}
	for _, key in Tokens.COLOR_KEYS do
		known[key] = true
	end
	for kind, def in MomentRules.kinds do
		Harness.truthy(known[def.tone], kind .. " tone is not a colour role")
	end
end)

Harness.test(
	"wiring: the Moment remote exists, goes to clients, and the banner has room on the HUD",
	function()
		local def = RemoteDefs.byName.Moment
		Harness.truthy(def ~= nil)
		Harness.eq(def.direction, "toClient")
		Harness.truthy(Layout.regions.moment ~= nil)
	end
)

Harness.test("wiring: plate and burst settings are sane", function()
	local p = Config.Plates
	Harness.truthy(p.maxDistance > 10 and p.maxDistance <= 300)
	Harness.truthy(p.maxNameLength >= 6 and p.maxNameLength <= 24)
	Harness.truthy(p.burst.particles >= 0 and p.burst.particles <= 60)
	Harness.truthy(p.burst.maxAtOnce >= 1 and p.burst.maxAtOnce <= 8)
	Harness.truthy(Config.Moments.bannerSeconds >= 1 and Config.Moments.bannerSeconds <= 5)
	Harness.truthy(Config.Moments.queueMax >= 1)
end)

Harness.test(
	"wiring: the client never trusts itself with these (no remote sends from the moment files)",
	function()
		for _, path in
			{
				"src/client/Moments/MomentBannerSystem.luau",
				"src/client/Moments/PlateSystem.luau",
				"src/client/Moments/LevelBurst.luau",
			}
		do
			local source = fs.readFile(path)
			Harness.eq(string.find(source, "Net.send", 1, true), nil, path .. " sends a request")
			Harness.truthy(string.find(source, "--!strict", 1, true), path .. " is not strict")
		end
	end
)
