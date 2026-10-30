--!strict
-- Found guns. A container broken by a shot or blast may drop a gun (odds in Config.Weapons.Drops).
-- The gun lies on the ground with a "Swap" button (a ProximityPrompt: tap on phones, E on keyboards,
-- X on controllers). The server checks every swap: combat phase, alive, same match, close enough,
-- the gun is still there. The old gun (unless it is the Volt Pistol) drops where the fighter stands.
-- The server part is invisible; every client draws the gun from its WeaponId attribute.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local Participants = require(script.Parent.Parent.Core.Participants)
local Combatants = require("./Combatants")
local ContainerLink = require("./ContainerLink")
local Firing = require("./Firing")
local WeaponCatalog = require("./WeaponCatalog")

local drops = Config.Weapons.Drops

type Drop = { id: number, gunId: string, matchId: number, part: BasePart, expiresAt: number }

local WeaponDrops = {}

local live: { Drop } = {} -- oldest first
local nextId = 0
local lastSwapAt: { [string]: number } = {}
local rng = Random.new()

local function folder(): Folder
	local found = Workspace:FindFirstChild(drops.folder)
	if found ~= nil and found:IsA("Folder") then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = drops.folder
	made.Parent = Workspace
	return made
end

local function remove(drop: Drop)
	local i = table.find(live, drop)
	if i ~= nil then
		table.remove(live, i)
	end
	drop.part:Destroy()
end

local onTrigger: (drop: Drop, player: Player) -> ()

-- Puts gun `gunId` on the floor at `floor` (a point on the ground). Returns the drop, or nil.
function WeaponDrops.spawn(gunId: string, floor: Vector3, matchId: number): Drop?
	if Config.Weapons.Guns[gunId] == nil or not MatchContext:isCurrent(matchId) then
		return nil
	end
	while #live >= drops.maxActive do
		remove(live[1])
	end
	nextId += 1
	local part = Instance.new("Part")
	part.Name = "WeaponDrop" .. nextId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 1, 2)
	part.CFrame = CFrame.new(floor + Vector3.new(0, drops.height, 0))
	part:SetAttribute("WeaponId", gunId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Swap"
	prompt.ObjectText = WeaponCatalog.displayName(Config, gunId)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = drops.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = part
	part.Parent = folder()
	local drop: Drop = {
		id = nextId,
		gunId = gunId,
		matchId = matchId,
		part = part,
		expiresAt = os.clock() + drops.lifetimeSeconds,
	}
	table.insert(live, drop)
	prompt.Triggered:Connect(function(player: Player)
		onTrigger(drop, player)
	end)
	return drop
end

-- The swap. Everything is checked here; the prompt only says "this player pressed it", and a bot
-- asks through WeaponDrops.claimFor. Both end up in the same checks.
local function trySwap(drop: Drop, p: { id: string, matchId: number })
	if table.find(live, drop) == nil or not MatchContext:isCombat() then
		return
	end
	if not MatchContext:isCurrent(drop.matchId) then
		remove(drop)
		return
	end
	if not Participants:isAlive(p.id) or p.matchId ~= drop.matchId then
		return
	end
	local root = Combatants.root(p.id)
	if root == nil then
		return
	end
	local here, there = root.Position, drop.part.Position
	local flat = Vector3.new(here.X - there.X, 0, here.Z - there.Z).Magnitude
	if flat > drops.promptDistance + drops.claimSlack then
		return
	end
	local now = os.clock()
	if now - (lastSwapAt[p.id] or -math.huge) < drops.swapCooldown then
		return
	end
	local old = Combatants.setPrimary(p.id, drop.gunId, now)
	if old == nil then
		return
	end
	lastSwapAt[p.id] = now
	remove(drop)
	if old ~= Config.Weapons.Firearm.id then
		WeaponDrops.spawn(old, Vector3.new(here.X, there.Y - drops.height, here.Z), drop.matchId)
	end
	Firing.sendAmmo(p.id)
end

onTrigger = function(drop: Drop, player: Player)
	local p = Participants:ofPlayer(player)
	if p ~= nil then
		trySwap(drop, p)
	end
end

export type GunOnGround = { dropId: string, gunId: string, x: number, z: number }

-- Guns lying around right now, for bots to walk to (bots see what a player sees).
function WeaponDrops.list(): { GunOnGround }
	local out: { GunOnGround } = {}
	for _, d in live do
		local at = d.part.Position
		table.insert(out, { dropId = tostring(d.id), gunId = d.gunId, x = at.X, z = at.Z })
	end
	return out
end

-- A bot asks for the swap. Same checks as a player's button press (phase, alive, match, distance,
-- gun still there, cooldown).
function WeaponDrops.claimFor(participantId: string, dropId: string)
	local p = Participants:get(participantId)
	if p == nil then
		return
	end
	for _, d in live do
		if tostring(d.id) == dropId then
			trySwap(d, p)
			return
		end
	end
end

function WeaponDrops.clear()
	for i = #live, 1, -1 do
		live[i].part:Destroy()
	end
	table.clear(live)
	table.clear(lastSwapAt)
end

function WeaponDrops.step()
	local now = os.clock()
	for i = #live, 1, -1 do
		local d = live[i]
		if now >= d.expiresAt or not MatchContext:isCurrent(d.matchId) then
			remove(d)
		end
	end
end

function WeaponDrops.start()
	ContainerLink.onBroken(function(pos: Vector3, _breakerId: string, matchId: number)
		local gunId = WeaponCatalog.rollDrop(Config, rng:NextNumber(), rng:NextNumber())
		if gunId ~= nil then
			WeaponDrops.spawn(gunId, pos - Vector3.new(0, Config.Containers.size / 2, 0), matchId)
		end
	end)
end

return WeaponDrops
