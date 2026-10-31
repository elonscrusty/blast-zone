--!strict
-- Every number the bots use. Shared tuning is read from Config (Config.Bots, Config.Match); the few
-- bot-only numbers live here. There are NO health, damage, speed or ammo numbers: bots get exactly
-- what a player gets (brief section 18). Pure (Config is passed in) so Lune can test it.

export type Tuning = {
	labelPrefix: string,
	names: { string },
	sightRange: number,
	reactionTime: number,
	aimErrorDegrees: number,
	-- calm start (BotWarmup): values at the very start of the fight
	warmupSeconds: number,
	warmupSightRange: number,
	warmupReactionTime: number,
	warmupAimErrorDegrees: number,
	-- auto-fill
	aloneBelow: number, -- fewer people than this counts as "alone"
	autoFillDelay: number, -- seconds waiting alone before bots join
	fillTo: number, -- bots top the match up to this many participants
	topUpDelay: number, -- seconds a part-full lobby waits before bots top it up
	maxParticipants: number,
	tapGap: number, -- seconds between "Add bots now" taps
	-- spread start: bots leave a human alone this long unless they are this close (studs)
	spreadSeconds: number,
	spreadHumanRange: number,
	-- thinking
	thinkInterval: number,
	crowdFrom: number, -- with more bots than this, each one thinks a little less often
	crowdMaxSlowdown: number, -- thinking gap at a full match is this many times thinkInterval
	pickupRange: number,
	memoryTime: number,
	idealRangeFraction: number,
	closeRange: number,
	strafeMin: number,
	strafeMax: number,
	reloadBelowFraction: number,
	fleeAtFraction: number,
	zoneMargin: number,
	goalReached: number,
	goalTime: number,
	roamDistance: number,
	stuckCheck: number,
	stuckDistance: number,
	sidestepTime: number,
	-- difficulty tier (piece 35); forTier() fills these in for one bot
	tierName: string,
	coverSkill: number, -- 0..1 chance it ducks behind cover when it must reload or is hurt
	seekGuns: boolean,
	zoneExtra: number, -- extra studs it keeps from the zone wall
	tiers: { [string]: Tier },
	tierCycle: { string },
	-- cover and guns
	coverProbe: number, -- first look-around distance for a spot the enemy cannot see
	coverHold: number, -- most seconds it stays behind one cover spot
	coverRetry: number, -- seconds before it looks for cover again after giving up
	coverReached: number,
	zoneLookahead: number, -- extra margin while the zone is closing
	zoneSlideDistance: number, -- slides toward the zone when this far outside it
	gunSeekRange: number, -- walks to a found gun this close
	gunGrabRange: number, -- asks for the swap this close (less than the prompt distance)
}

export type Tier = {
	sightScale: number,
	reactionScale: number,
	aimErrorScale: number,
	coverSkill: number,
	seekGuns: boolean,
	zoneExtra: number,
}

local BotTuning = {}

-- Look: Crash Dummy (carter's pick). Hex text; Roblox code turns it into Color3.
BotTuning.LOOK = {
	body = "#FFC44D",
	legs = "#2A2A2E",
	tagBack = "#1B1B1F",
	tagText = "#FFC44D",
	target = "#F15B64",
	targetRing = "#FFFFFF",
}

export type ConfigLike = {
	Bots: {
		labelPrefix: string,
		names: { string },
		sightRange: number,
		reactionSeconds: number,
		aimErrorDegrees: number,
		hiddenStatAdvantage: boolean,
		warmup: {
			seconds: number,
			sightRange: number,
			reactionSeconds: number,
			aimErrorDegrees: number,
		}?,
		tiers: { [string]: Tier }?,
		tierCycle: { string }?,
	},
	Match: {
		minToStart: number,
		targetParticipants: number,
		maxParticipants: number,
	},
}

-- Seconds between one bot's thinks when `bots` bots are running. A few bots think at the full rate; as the
-- number grows toward a full match the gap stretches (to crowdMaxSlowdown times) so 24 bots cost the
-- server about what 15 did. Walking and shooting still run every frame.
function BotTuning.thinkGap(tuning: Tuning, bots: number, fullMatch: number): number
	local span = math.max(1, fullMatch - 1 - tuning.crowdFrom)
	local over = math.clamp((bots - tuning.crowdFrom) / span, 0, 1)
	return tuning.thinkInterval * (1 + over * (tuning.crowdMaxSlowdown - 1))
end

function BotTuning.from(config: ConfigLike): Tuning
	assert(
		config.Bots.hiddenStatAdvantage == false,
		"Config.Bots.hiddenStatAdvantage must stay false: bots use player rules"
	)
	local warmup = config.Bots.warmup
	local normalTier: Tier = { -- used when the config has no tiers (older tests)
		sightScale = 1,
		reactionScale = 1,
		aimErrorScale = 1,
		coverSkill = 0.7,
		seekGuns = true,
		zoneExtra = 4,
	}
	local tiers: { [string]: Tier } = config.Bots.tiers or { normal = normalTier }
	local normal = tiers.normal or normalTier
	local cycle = config.Bots.tierCycle or { "normal" }
	return {
		labelPrefix = config.Bots.labelPrefix,
		names = config.Bots.names,
		sightRange = config.Bots.sightRange,
		reactionTime = config.Bots.reactionSeconds,
		aimErrorDegrees = config.Bots.aimErrorDegrees,
		warmupSeconds = if warmup then warmup.seconds else 0,
		warmupSightRange = if warmup then warmup.sightRange else config.Bots.sightRange,
		warmupReactionTime = if warmup then warmup.reactionSeconds else config.Bots.reactionSeconds,
		warmupAimErrorDegrees = if warmup
			then warmup.aimErrorDegrees
			else config.Bots.aimErrorDegrees,

		aloneBelow = config.Match.minToStart,
		autoFillDelay = 10,
		topUpDelay = 8,
		fillTo = math.min(config.Match.targetParticipants, config.Match.maxParticipants),
		maxParticipants = config.Match.maxParticipants,
		tapGap = 2,

		spreadSeconds = 15,
		spreadHumanRange = 7, -- video-feel pass: was 14 (distances halve with the camera and the guns)

		thinkInterval = 0.1,
		crowdFrom = 10,
		crowdMaxSlowdown = 1.6, -- 24 bots think every 0.16 s instead of 0.1 s; the walking stays every frame
		pickupRange = 20, -- was 40
		memoryTime = 2, -- keeps heading to where a target was last seen
		idealRangeFraction = 0.6, -- fights at this share of the weapon range
		closeRange = 7, -- backs away when closer than this (was 14)
		strafeMin = 0.8,
		strafeMax = 1.6,
		reloadBelowFraction = 0.35, -- reloads early when nobody is in sight
		fleeAtFraction = 0.3, -- runs and slides away at low health
		zoneMargin = 6, -- heads inward before the edge touches it
		goalReached = 4,
		goalTime = 8, -- gives up on a roam goal after this long
		roamDistance = 20, -- roam goal distance when there is no zone to aim for (was 40)
		stuckCheck = 1,
		stuckDistance = 3,
		sidestepTime = 0.6,

		tierName = "normal",
		coverSkill = normal.coverSkill,
		seekGuns = normal.seekGuns,
		zoneExtra = normal.zoneExtra,
		tiers = tiers,
		tierCycle = cycle,
		coverProbe = 7,
		coverHold = 3,
		coverRetry = 2,
		coverReached = 1.5,
		zoneLookahead = 8,
		zoneSlideDistance = 8, -- (was 12; the slide is 9 studs now)
		gunSeekRange = 22, -- (was 45)
		gunGrabRange = 5, -- the swap prompt works from 7 studs
	}
end

-- Which tier bot `id` plays ("b3" is the third bot). Same bot number, same tier, every match.
function BotTuning.tierOf(tuning: Tuning, id: string): string
	local n = tonumber(string.match(id, "%d+")) or 1
	local cycle = tuning.tierCycle
	local name = cycle[(n - 1) % #cycle + 1]
	if tuning.tiers[name] then
		return name
	end
	return "normal"
end

-- A copy of `tuning` for one tier. Only the full-strength sight, reaction and aim move; the calm
-- start numbers stay put, so every tier starts a match equally gentle (carter's spawn rule).
function BotTuning.forTier(tuning: Tuning, tierName: string): Tuning
	local tier = tuning.tiers[tierName]
	if not tier then
		return tuning
	end
	local out = table.clone(tuning)
	out.tierName = tierName
	out.sightRange = math.max(tuning.sightRange * tier.sightScale, tuning.warmupSightRange)
	out.reactionTime = math.min(tuning.reactionTime * tier.reactionScale, tuning.warmupReactionTime)
	out.aimErrorDegrees =
		math.min(tuning.aimErrorDegrees * tier.aimErrorScale, tuning.warmupAimErrorDegrees)
	out.coverSkill = tier.coverSkill
	out.seekGuns = tier.seekGuns
	out.zoneExtra = tier.zoneExtra
	return out
end

return BotTuning
