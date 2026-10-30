--!strict
-- Big-moment banners (piece 44). Pure: no Roblox, no clock. The server sends a small `Moment` payload
-- when something worth shouting about happens; this file checks it and says what the banner says.
-- The words and the order of importance live here. How a banner LOOKS is Ui/MomentStyles (Claude Design).

export type Payload = {
	kind: string, -- "streak" | "zoneClosing" | "suddenDeath"
	matchId: number,
	tier: string?, -- streak only: "double" | "triple" | "spree"
	streak: number?, -- streak only
	actorId: string?, -- streak only: who got the kills
	actorName: string?,
	heal: number?, -- streak only: health the server gave
	stage: number?, -- zone only
}

export type Banner = {
	key: string, -- same key = same news (used to skip repeats)
	kind: string, -- "double" | "triple" | "spree" | "zoneClosing" | "suddenDeath"
	title: string,
	subtitle: string?,
	tone: string, -- a colour ROLE name: "accent" | "danger" | "info"
	emblem: string, -- a short sign the look draws big, e.g. "x2"
	priority: number, -- higher wins the screen
	mine: boolean, -- the local player earned it
}

local MomentRules = {}

-- The five banners. A look may restyle them; it may not add or drop one.
MomentRules.kinds = {
	zoneClosing = { priority = 1, tone = "info", emblem = "!" },
	double = { priority = 2, tone = "accent", emblem = "x2" },
	triple = { priority = 3, tone = "accent", emblem = "x3" },
	spree = { priority = 4, tone = "danger", emblem = "x5" },
	suddenDeath = { priority = 5, tone = "danger", emblem = "!!" },
} :: { [string]: { priority: number, tone: string, emblem: string } }

MomentRules.streakTiers = { "double", "triple", "spree" }
MomentRules.payloadKinds = { "streak", "zoneClosing", "suddenDeath" }

local function isString(v: any, maxLen: number): boolean
	return type(v) == "string" and #v > 0 and #v <= maxLen
end

local function isCount(v: any, max: number): boolean
	return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= max
end

-- True when a payload is well formed. Anything else is dropped, never guessed at.
function MomentRules.isValid(p: any): boolean
	if type(p) ~= "table" or not isCount(p.matchId, 2 ^ 31) then
		return false
	end
	if p.kind == "zoneClosing" or p.kind == "suddenDeath" then
		return p.stage == nil or isCount(p.stage, 99)
	end
	if p.kind == "streak" then
		return table.find(MomentRules.streakTiers, p.tier) ~= nil
			and isCount(p.streak, 99)
			and isString(p.actorId, 24)
			and isString(p.actorName, 64)
			and (p.heal == nil or isCount(p.heal, 500))
	end
	return false
end

-- Cut a name to `max` letters (whole letters, never half of one), with "..." after a cut.
function MomentRules.shortName(name: string, max: number): string
	local length = utf8.len(name)
	if length == nil then
		return "?" -- not valid text: show nothing risky
	end
	if length <= max then
		return name
	end
	local cut = utf8.offset(name, math.max(1, max - 1) + 1)
	if cut == nil then
		return name
	end
	return string.sub(name, 1, cut - 1) .. "..."
end

local function def(kind: string)
	return MomentRules.kinds[kind]
end

-- What to show for a payload. `localId` is the player's own participant id. Returns nil when the
-- payload is bad, or is news about somebody else that this tier does not announce.
function MomentRules.banner(p: any, localId: string, maxName: number): Banner?
	if not MomentRules.isValid(p) then
		return nil
	end
	local payload = p :: Payload
	if payload.kind == "zoneClosing" or payload.kind == "suddenDeath" then
		local d = def(payload.kind)
		local sudden = payload.kind == "suddenDeath"
		return {
			key = `{payload.kind}:{payload.matchId}:{payload.stage or 0}`,
			kind = payload.kind,
			title = if sudden then "SUDDEN DEATH" else "CIRCLE CLOSING",
			subtitle = if sudden then "Last one standing wins" else "Move to the middle",
			tone = d.tone,
			emblem = d.emblem,
			priority = d.priority,
			mine = false,
		}
	end
	local tier = payload.tier :: string
	local d = def(tier)
	local actorId = payload.actorId :: string
	local mine = actorId == localId
	local key = `streak:{payload.matchId}:{actorId}:{tier}`
	if mine then
		local heal = payload.heal
		return {
			key = key,
			kind = tier,
			title = if tier == "double"
				then "DOUBLE KILL"
				elseif tier == "triple" then "TRIPLE KILL"
				else "KILLING SPREE",
			subtitle = if heal ~= nil and heal > 0 then `+{heal} HP` else nil,
			tone = d.tone,
			emblem = d.emblem,
			priority = d.priority,
			mine = true,
		}
	end
	-- Somebody else: only the long streaks are worth a banner for everyone.
	if tier ~= "spree" then
		return nil
	end
	local name = MomentRules.shortName(payload.actorName :: string, maxName)
	return {
		key = key,
		kind = tier,
		title = `{name} IS ON A SPREE`,
		subtitle = `{payload.streak} in a row`,
		tone = d.tone,
		emblem = d.emblem,
		priority = d.priority,
		mine = false,
	}
end

return MomentRules
