--!strict
-- The one list of every RemoteEvent. All are RemoteEvents (no RemoteFunctions: a client must never
-- be able to make the server wait). Each piece edits ONLY its own block; add fields to your payload
-- types in Types.luau (ask piece 01 if a type is shared).
--
--   toServer: client asks. Needs `schema` and `rate`. The server re-checks everything else.
--   toClient: server tells. Payload types are named in `payload` (see Types.luau); times are server time.

local Config = require("./Config")
local Guard = require("./Guard")

export type Def = {
	name: string,
	direction: "toServer" | "toClient",
	owner: string, -- piece number
	schema: { Guard.Field }?,
	rate: { perSecond: number, burst: number }?,
	payload: string?, -- doc only
}

local function ask(
	owner: string,
	name: string,
	schema: { Guard.Field },
	perSecond: number,
	burst: number
): Def
	return {
		name = name,
		direction = "toServer",
		owner = owner,
		schema = schema,
		rate = { perSecond = perSecond, burst = burst },
	}
end

local function tell(owner: string, name: string, payload: string): Def
	return { name = name, direction = "toClient", owner = owner, payload = payload }
end

-- The fastest gun sets the fire-request limit (the server still checks each gun's own fire rate).
local fireRate = Config.Weapons.Firearm.fireRate
for _, gun in Config.Weapons.Guns do
	fireRate = math.max(fireRate, 1 / gun.fireInterval)
end

local Defs: { Def } = {
	-- ===== 01 core =====
	tell("01", "Notice", "{ text: string, kind: 'info'|'warn' }"),

	-- ===== 02 movement + slide =====
	ask(
		"02",
		"SlideRequest",
		{ { name = "dir", kind = "vector3", optional = true, maxMagnitude = 2 } },
		3,
		3
	),
	tell("02", "SlideFx", "{ participantId, fromPos, toPos, duration }"),
	tell("02", "SlideState", "{ cooldownEndsAt: number, serverNow: number }"),
	tell("02", "SlideDenied", "{}"),

	-- ===== 03 aiming + weapons + health =====
	ask("03", "FireRequest", {
		{ name = "origin", kind = "vector3" },
		{ name = "dir", kind = "unit3" },
		{ name = "seq", kind = "integer", min = 0, max = 2147483647 },
	}, fireRate * 2, 10),
	ask("03", "ReloadRequest", {}, 3, 3),
	ask(
		"03",
		"SwitchWeaponRequest",
		{ { name = "slot", kind = "integer", min = 1, max = 2 } },
		5,
		5
	),
	tell(
		"03",
		"ShotFx",
		"{ shooterId, weaponId, origin, endPos, hitKind: 'target'|'wall'|'container'|'none' }"
	),
	tell("03", "HitConfirm", "{ targetId, amount, killed, pos? }"),
	tell("03", "DamageTaken", "{ sourceId?, amount, cause, fromDir?, weaponId?, health }"),
	tell(
		"03",
		"AmmoState",
		"{ slot, weaponId, weaponName, fireInterval, reloadSeconds, muzzleOffset, ammo, magazine, reloadEndsAt?, serverNow }"
	),
	tell("03", "HealthState", "{ health, max }"),
	tell("03", "ExplosionFx", "{ pos, radius, shooterId?, warnEndsAt? }"),
	tell(
		"03",
		"DefeatSummary",
		"{ killerId?, killerName?, cause, weaponId?, hitters: { { name, damage } } }"
	),

	-- ===== 05 match, spectate, results =====
	ask("05", "PlayRequest", {}, 1, 2),
	ask("05", "ReplayRequest", {}, 1, 2),
	ask("05", "ReturnToLobbyRequest", {}, 1, 2),
	ask("05", "ClaimResults", { { name = "matchId", kind = "integer", min = 0 } }, 1, 2),
	ask("05", "SpectateCycle", { { name = "step", kind = "integer", min = -1, max = 1 } }, 4, 4),
	tell("05", "MatchState", "PublicMatchState"),
	tell(
		"05",
		"Eliminated",
		"{ matchId, victimId, victimName, killerId?, killerName?, cause, placement, eliminations, survivedSeconds }"
	),
	tell("05", "Announce", "{ kind: 'banner'|'kill'|'win', text: string }"),
	tell("05", "SpectateTarget", "{ participantId? }"),
	tell("05", "Results", "ResultsPayload"),

	-- ===== 06 zone =====
	tell("06", "ZoneState", "ZoneState"),
	ask("06", "ZoneStateRequest", {}, 1, 2), -- a client that joined late asks for the live circle

	-- ===== 07 containers, pickups, run xp =====
	ask("07", "PickupRequest", { { name = "pickupId", kind = "id" } }, 10, 10),
	tell("07", "ContainerHit", "{ containerId, health, max }"),
	tell("07", "ContainerBroken", "{ containerId, pos }"),
	tell("07", "PickupSpawned", "{ pickupId, kind, pos }"),
	tell("07", "PickupRemoved", "{ pickupId, collectedBy?, pos }"),
	tell("07", "XpState", "XpState"),

	-- ===== 08 upgrades =====
	ask("08", "UpgradeChoose", {
		{ name = "offerId", kind = "id" },
		{ name = "optionIndex", kind = "integer", min = 1, max = Config.Upgrades.offerSize },
	}, 4, 3),
	tell("08", "UpgradeOffer", "UpgradeOffer? (nil closes the cards)"),
	tell("08", "UpgradeApplied", "{ upgradeId, stacks, text }"),

	-- ===== 09 bots =====
	ask("09", "AddBotsRequest", {}, 1, 2),
	tell("09", "BotFillState", "{ secondsLeft: number? } (nil hides the banner)"),

	-- ===== 10 hud: add here only if you truly need a new remote =====
}

local Index: { [string]: Def } = {}
for _, def in Defs do
	Index[def.name] = def
end

return {
	list = Defs,
	byName = Index,
}
