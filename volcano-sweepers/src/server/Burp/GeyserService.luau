--!strict
-- Gem Geysers: treasure pops out of vents, anyone who runs close grabs it for coins.
--
--   GeyserService.init()
--   GeyserService.spawnWave(spots: { {x:number, z:number} })   BurpService calls this for a "geysers" event
--   GeyserService.clear()
--   GeyserService.liveCount() -> number
--
-- Where gems come from: each director spot is moved onto the nearest unused vent of
-- World.ventPositions (a Vector3 list, or a function returning one; looked up with a pcall-require so
-- a missing World never breaks us). With no vents the director's own spots are used, and with no
-- spots at all random cells of zones 3..5 are used.
--
-- Pickup is decided ONLY here: 5 times a second every ready player's trusted position (MoveWatch)
-- is compared to every landed gem (BurpGlue.inPickupRange, 6 studs). The client never claims anything.
--
-- GeyserGems remote payloads (server -> all clients; one remote, two shapes):
--   appeared:  { { x = number, z = number, id = number, rarity = string } , ... }   a plain list
--   gone:      { removed = id }      picked up by someone, expired after 25 s, or pushed out by the cap
-- Also sent as a plain list to a player who joins while gems are lying around.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BurpGlue = require(Shared.Burp.BurpGlue)
local BurpTuning = require(Shared.Burp.BurpTuning)
local Config = require(Shared.Config)
local Finds = require(Shared.Catalog.Finds)
local Layout = require(Shared.Ash.Layout)
local Rng = require(Shared.Rng)

local MoveWatch = require(script.Parent.Parent.Core.MoveWatch)
local Net = require(script.Parent.Parent.Core.Net)
local PlayerState = require(script.Parent.Parent.Player.PlayerState)
local FindsService = require(script.Parent.Parent.Finds.FindsService)

local FOLDER_NAME = "VSGems"
local GEM_LIFETIME = 25 -- seconds
local POP_SECONDS = 0.5 -- the gem flies from the vent to its spot; not pickable until it lands
local POLL_SECONDS = 0.2 -- 5 Hz
local MAX_GEMS = 60
local GEM_SIZE = 1.6
local HOVER_Y = 2.5
local SCATTER_MIN, SCATTER_MAX = 5, 9

type Spot = { x: number, z: number }

type Gem = {
	id: number,
	part: Part,
	x: number,
	y: number,
	z: number,
	zone: number,
	rarity: string,
	readyAt: number,
	expiresAt: number,
	tweens: { Tween },
}

local GeyserService = {}

local rng = Rng.new(os.time() + 7919 + math.floor(os.clock() * 1000))
local gems: { [number]: Gem } = {}
local order: { number } = {} -- gem ids, oldest first (may hold ids that are already gone)
local orderHead = 1
local liveN = 0
local nextId = 0
local folder: Folder? = nil
local started = false
local worldModule: any = nil
local lastWarn = -10

local function getFolder(): Folder
	local cached = folder
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = workspace
	folder = made
	return made
end

local function loadWorld(): any
	if worldModule ~= nil then
		return worldModule
	end
	local ok, mod = pcall(function(): any
		local parent = script.Parent.Parent
		local holder = parent:FindFirstChild("World")
		local m = holder
		if holder ~= nil and not holder:IsA("ModuleScript") then
			m = holder:FindFirstChild("World")
		end
		if m ~= nil and m:IsA("ModuleScript") then
			return require(m)
		end
		return nil
	end)
	if ok and mod ~= nil then
		worldModule = mod
	end
	return worldModule
end

-- Vent positions as plain {x, z}; empty when World is missing or has none.
local function ventSpots(): { Spot }
	local out: { Spot } = {}
	local world = loadWorld()
	if world == nil then
		return out
	end
	local ok, vents = pcall(function(): any
		local v = world.ventPositions
		if type(v) == "function" then
			return v()
		end
		return v
	end)
	if not ok or type(vents) ~= "table" then
		return out
	end
	for _, v in vents do
		if typeof(v) == "Vector3" then
			table.insert(out, { x = v.X, z = v.Z })
		elseif type(v) == "table" and BurpGlue.finite(v.x) and BurpGlue.finite(v.z) then
			table.insert(out, { x = v.x, z = v.z })
		end
	end
	return out
end

-- Random cells of zones 3..5 for when the director gave nothing and there are no vents.
local function fallbackSpots(count: number): { Spot }
	local out: { Spot } = {}
	for _ = 1, count do
		local list = Layout.zoneCells[rng:int(3, 5)]
		if list ~= nil and #list > 0 then
			local i = rng:pick(list)
			table.insert(out, { x = Layout.cx[i], z = Layout.cz[i] })
		end
	end
	return out
end

local function removeGem(gem: Gem, tell: boolean)
	if gems[gem.id] ~= gem then
		return
	end
	gems[gem.id] = nil
	liveN -= 1
	for _, tw in gem.tweens do
		tw:Cancel()
	end
	gem.part:Destroy()
	if tell then
		Net.fireAll("GeyserGems", { removed = gem.id })
	end
end

local function dropOldest(): boolean
	local dropped = false
	while orderHead <= #order do
		local gem = gems[order[orderHead]]
		orderHead += 1
		if gem ~= nil then
			removeGem(gem, true)
			dropped = true
			break
		end
	end
	if orderHead > 64 then
		order = table.move(order, orderHead, #order, 1, {})
		orderHead = 1
	end
	return dropped
end

-- One gem pops from (vx, vz) to (gx, gz). Returns its remote entry, or nil if it could not be made.
local function addGem(vx: number, vz: number, gx: number, gz: number): { [string]: any }?
	if
		not (
			BurpGlue.finite(vx)
			and BurpGlue.finite(vz)
			and BurpGlue.finite(gx)
			and BurpGlue.finite(gz)
		)
	then
		return nil
	end
	while liveN >= MAX_GEMS do
		if not dropOldest() then
			return nil
		end
	end
	nextId += 1
	local id = nextId
	local rarity = BurpGlue.gemRarity(rng:next())
	local rdef = Finds.rarityById[rarity]
	local groundY = Config.World.groundY
	local tilt = CFrame.Angles(math.rad(45), math.rad(45), 0) -- a cube on its corner looks like a diamond

	local part = Instance.new("Part")
	part.Name = "GeyserGem"
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromHex(rdef.colorHex)
	part.Size = Vector3.new(GEM_SIZE, GEM_SIZE, GEM_SIZE)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(vx, groundY + 1, vz) * tilt
	part.Parent = getFolder()
	Debris:AddItem(part, GEM_LIFETIME + 2) -- backup; the poll loop removes it at GEM_LIFETIME

	local t = os.clock()
	local gem: Gem = {
		id = id,
		part = part,
		x = gx,
		y = groundY + HOVER_Y,
		z = gz,
		zone = BurpGlue.zoneOf(gx, gz),
		rarity = rarity,
		readyAt = t + POP_SECONDS,
		expiresAt = t + GEM_LIFETIME,
		tweens = {},
	}
	gems[id] = gem
	liveN += 1
	table.insert(order, id)

	local pop = TweenService:Create(
		part,
		TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = Vector3.new(gx, gem.y + 2, gz) }
	)
	local settle = TweenService:Create(
		part,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = Vector3.new(gx, gem.y, gz) }
	)
	local bob = TweenService:Create(
		part,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = Vector3.new(gx, gem.y + 1, gz) }
	)
	gem.tweens = { pop, settle, bob }
	pop.Completed:Once(function()
		if gems[id] == gem then
			settle:Play()
		end
	end)
	settle.Completed:Once(function()
		if gems[id] == gem then
			bob:Play()
		end
	end)
	pop:Play()
	return { x = gx, z = gz, id = id, rarity = rarity }
end

function GeyserService.liveCount(): number
	return liveN
end

function GeyserService.spawnWave(spots: { Spot })
	local chosen = BurpGlue.snapSpots(spots, ventSpots())
	if #chosen == 0 then
		chosen = fallbackSpots(BurpTuning.geyserSpotsBase)
	end
	local payload: { { [string]: any } } = {}
	for _, v in chosen do
		for _, o in BurpGlue.gemOffsets(rng, BurpTuning.geyserGemsPerSpot, SCATTER_MIN, SCATTER_MAX) do
			local entry = addGem(v.x, v.z, v.x + o.x, v.z + o.z)
			if entry ~= nil then
				table.insert(payload, entry)
			end
		end
	end
	if #payload > 0 then
		Net.fireAll("GeyserGems", payload)
	end
end

function GeyserService.clear()
	for _, gem in gems do
		removeGem(gem, true)
	end
end

-- Where the server believes the player is (MoveWatch). A player who just moved faster than
-- possible cannot grab gems until the trusted spot caught up.
local function rootPosition(player: Player): Vector3?
	local pos, trusted = MoveWatch.position(player)
	if pos == nil or not trusted then
		return nil
	end
	return pos
end

local function poll()
	if next(gems) == nil then
		return
	end
	local t = os.clock()
	for _, gem in gems do
		if t >= gem.expiresAt then
			removeGem(gem, true)
		end
	end
	if next(gems) == nil then
		return
	end
	for _, state in PlayerState.all() do
		local pos = rootPosition(state.player)
		if pos ~= nil then
			for _, gem in gems do
				if
					t >= gem.readyAt
					and BurpGlue.inPickupRange(pos.X, pos.Y, pos.Z, gem.x, gem.y, gem.z)
				then
					local rdef = Finds.rarityById[gem.rarity]
					local coins = BurpGlue.geyserCoins(gem.zone, state.profile.zones, rdef.coinMult)
					if FindsService.grantGeyserGem(state.player, coins) > 0 then
						removeGem(gem, true)
					end
				end
			end
		end
	end
end

function GeyserService.init()
	if started then
		return
	end
	started = true
	getFolder()
	PlayerState.onReady:connect(function(player: Player)
		if liveN == 0 then
			return
		end
		local list: { { [string]: any } } = {}
		for _, gem in gems do
			table.insert(list, { x = gem.x, z = gem.z, id = gem.id, rarity = gem.rarity })
		end
		Net.fire("GeyserGems", player, list)
	end)
	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			local ok, err = pcall(poll)
			if not ok and os.clock() - lastWarn > 5 then
				lastWarn = os.clock()
				warn("[GeyserService] poll failed: " .. tostring(err))
			end
		end
	end)
end

return GeyserService
