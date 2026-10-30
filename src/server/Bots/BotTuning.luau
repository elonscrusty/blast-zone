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
	-- auto-fill
	aloneBelow: number, -- fewer people than this counts as "alone"
	autoFillDelay: number, -- seconds waiting alone before bots join
	fillTo: number, -- bots top the match up to this many participants
	maxParticipants: number,
	tapGap: number, -- seconds between "Add bots now" taps
	-- thinking
	thinkInterval: number,
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
	},
	Match: {
		minToStart: number,
		targetParticipants: number,
		maxParticipants: number,
	},
}

function BotTuning.from(config: ConfigLike): Tuning
	assert(
		config.Bots.hiddenStatAdvantage == false,
		"Config.Bots.hiddenStatAdvantage must stay false: bots use player rules"
	)
	return {
		labelPrefix = config.Bots.labelPrefix,
		names = config.Bots.names,
		sightRange = config.Bots.sightRange,
		reactionTime = config.Bots.reactionSeconds,
		aimErrorDegrees = config.Bots.aimErrorDegrees,

		aloneBelow = config.Match.minToStart,
		autoFillDelay = 10,
		fillTo = math.min(config.Match.targetParticipants, config.Match.maxParticipants),
		maxParticipants = config.Match.maxParticipants,
		tapGap = 2,

		thinkInterval = 0.1,
		pickupRange = 40,
		memoryTime = 2, -- keeps heading to where a target was last seen
		idealRangeFraction = 0.6, -- fights at this share of the weapon range
		closeRange = 14, -- backs away when closer than this
		strafeMin = 0.8,
		strafeMax = 1.6,
		reloadBelowFraction = 0.35, -- reloads early when nobody is in sight
		fleeAtFraction = 0.3, -- runs and slides away at low health
		zoneMargin = 6, -- heads inward before the edge touches it
		goalReached = 4,
		goalTime = 8, -- gives up on a roam goal after this long
		roamDistance = 40, -- roam goal distance when there is no zone to aim for
		stuckCheck = 1,
		stuckDistance = 3,
		sidestepTime = 0.6,
	}
end

return BotTuning
