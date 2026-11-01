--!strict
-- The one list of every RemoteEvent. All RemoteEvents (no RemoteFunctions: a client must never be
-- able to make the server wait). The server re-checks everything the client sends.
--   toServer: client asks. Needs `schema` and `rate`.
--   toClient: server tells. Payload types are named in `payload` (see Types.luau).

local Guard = require("./Guard")

export type Def = {
	name: string,
	direction: "toServer" | "toClient",
	schema: { Guard.Field }?,
	rate: { perSecond: number, burst: number }?,
	payload: string?, -- doc only
}

local function ask(name: string, schema: { Guard.Field }, perSecond: number, burst: number): Def
	return {
		name = name,
		direction = "toServer",
		schema = schema,
		rate = { perSecond = perSecond, burst = burst },
	}
end

local function tell(name: string, payload: string): Def
	return { name = name, direction = "toClient", payload = payload }
end

local Defs: { Def } = {
	-- client -> server
	ask("ClientReady", {}, 1, 3), -- client finished loading; server sends full state + ash snapshot
	ask("Sweep", {}, 10, 14), -- one swing; server uses its OWN copy of position/facing, never the client's
	ask("Sell", {}, 4, 6),
	ask("Buy", {
		{ name = "kind", kind = "string", maxLen = 16 }, -- upgrade|tool|zone|helper|helperUp|sparkPerk
		{ name = "id", kind = "string", maxLen = 32 },
	}, 10, 14),
	ask("EquipTool", { { name = "id", kind = "string", maxLen = 32 } }, 4, 6),
	ask("CoolDown", {}, 1, 2),
	ask("ClaimDaily", {}, 1, 2),
	ask("ClaimGoal", { { name = "id", kind = "string", maxLen = 32 } }, 4, 6),
	ask("ClaimSet", { { name = "id", kind = "string", maxLen = 32 } }, 4, 6),
	ask("SetSetting", {
		{ name = "key", kind = "string", maxLen = 16 },
		{ name = "value", kind = "boolean" },
	}, 4, 8),
	ask("TutorialDone", {}, 1, 2),

	-- server -> client
	tell(
		"State",
		"partial View: { [key]: value } merged into the client store (offline = save not loaded, offlineRetrying = still trying to load it)"
	),
	tell(
		"AshSnapshot",
		"string: one char per cell, level = byte - 48 ('0'..'9'); sent on ClientReady"
	),
	tell("AshDelta", "{ number }: flat pairs { cellIndex, newLevel, ... }, batched ~10 per second"),
	tell(
		"SweepFx",
		"SweepFxInfo: other players' swings, for their puffs (not sent to the sweeper)"
	),
	tell("Sold", "SoldInfo"),
	tell("Toast", "ToastInfo"),
	tell("Burp", "BurpInfo"),
	tell("Bombs", "BombsInfo: lava bomb telegraphs (circle on the ground, lands at landsAt)"),
	tell("BurpHit", "BurpHitInfo: someone got bounced (for the splat effect)"),
	tell("Progress", "ProgressInfo: clean fractions, ~1 per second when changed"),
	tell("Party", "PartyInfo: island party started (fireworks)"),
	tell("FindFound", "FindInfo"),
	tell("CoolDownDone", "CoolDownInfo"),
	tell(
		"Golden",
		"{ cells: {number}, endsAt: number }: cell indices flagged golden (5x ash). cells = {} means all gold is gone. A cell stops being gold when its level reaches 0."
	),
	tell(
		"GeyserGems",
		"two shapes: { {x:number,z:number,id:number,rarity:string} } = gems appeared (touch to grab, server checks); { removed = id } = that gem is gone"
	),
}

local byName: { [string]: Def } = {}
for _, d in Defs do
	assert(byName[d.name] == nil, "duplicate remote " .. d.name)
	byName[d.name] = d
end

return { list = Defs, byName = byName }
