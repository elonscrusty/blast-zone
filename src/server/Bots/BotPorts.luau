--!strict
-- The doors into the other pieces. Bots do not reach into their code: each piece may share a small
-- `BotPort` module that works by ParticipantId (so "b1" works like "p123"). A missing port is not an
-- error; that part of bot behaviour just waits until the piece lands.
--   Server/Combat/BotPort    (piece 03)  fire, reload, state, registerBotBody, shotParams?
--   Server/Movement/BotPort  (piece 02)  slide, slideReady, registerBotBody
-- Zone (piece 06) and pickups (piece 07) already publish what bots need on their own systems:
--   Server/Zone/ZoneSystem.getSample()              the live safe circle
--   Server/Pickups/PickupSystem.tryClaim(id, pos, pickupId)   how a bot collects an orb

local ServerScriptService = game:GetService("ServerScriptService")

export type CombatState = {
	health: number,
	maxHealth: number,
	ammo: number,
	magazine: number,
	reloading: boolean,
	canFire: boolean, -- the server would accept a shot right now
	gunId: string?, -- the gun in hand
	range: number?, -- how far that gun reaches
}

export type CombatPort = {
	-- Same checks as a player's FireRequest (phase, ammo, fire interval, muzzle in a wall).
	fire: (id: string, dirX: number, dirZ: number) -> boolean,
	reload: (id: string) -> boolean,
	state: (id: string) -> CombatState?, -- nil = dead or unknown
	registerBotBody: (id: string, model: Model) -> (),
	shotParams: (() -> RaycastParams)?, -- the params shots use, so sight matches shooting
	gunDrops: (() -> { { dropId: string, gunId: string, x: number, z: number } })?,
	claimGun: ((id: string, dropId: string) -> ())?,
}

export type MovementPort = {
	slide: (id: string, dirX: number, dirZ: number) -> boolean,
	slideReady: (id: string) -> boolean,
	registerBotBody: (id: string, model: Model) -> (), -- sets walk speed like a player
}

export type ZoneSystem = {
	getSample: () -> { centerX: number, centerZ: number, radius: number, toRadius: number }?,
}

export type PickupSystem = {
	tryClaim: (participantId: string, position: Vector3, pickupId: string) -> (boolean, string?),
}

local BotPorts = {}

local loaded: { [string]: any } = {}
local lastTry: { [string]: number } = {}
local RETRY_SECONDS = 3

local function find(folderName: string, moduleName: string): any?
	local key = folderName .. "/" .. moduleName
	if loaded[key] ~= nil then
		return loaded[key]
	end
	local now = os.clock()
	if lastTry[key] and now - lastTry[key] < RETRY_SECONDS then
		return nil
	end
	lastTry[key] = now
	local server = ServerScriptService:FindFirstChild("Server")
	local folder = server and server:FindFirstChild(folderName)
	local module = folder and folder:FindFirstChild(moduleName)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			loaded[key] = result
			return result
		end
		warn(`[bots] {key} failed to load: {result}`)
	end
	return nil
end

function BotPorts.combat(): CombatPort?
	return find("Combat", "BotPort")
end

function BotPorts.movement(): MovementPort?
	return find("Movement", "BotPort")
end

function BotPorts.zone(): ZoneSystem?
	return find("Zone", "ZoneSystem")
end

function BotPorts.pickups(): PickupSystem?
	return find("Pickups", "PickupSystem")
end

return BotPorts
