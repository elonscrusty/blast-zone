--!strict
-- Server start. The server decides everything: the client only asks.
-- Order: remotes -> core services -> every "...System" module (see shared/Boot.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)
local Config = require(Shared.Config)

local Core = script.Parent:WaitForChild("Core")

require(Core.Net).init()
for _, name in { "Participants", "MatchContext", "Damage", "RunXp", "EffectiveStats" } do
	require(Core:WaitForChild(name))
end
require(Core.CollisionGroups).setup()

type System = { order: number?, start: () -> () }
local found: { { name: string, order: number?, module: System } } = {}

for _, inst in script.Parent:GetDescendants() do
	if inst:IsA("ModuleScript") and Boot.isSystemName(inst.Name) then
		local ok, result = pcall(require, inst)
		if ok then
			table.insert(found, { name = inst.Name, order = result.order, module = result })
		else
			warn(`[server] could not load {inst.Name}: {result}`)
		end
	end
end

for _, entry in Boot.sort(found) do
	local ok, err = pcall(entry.module.start)
	if ok then
		print(`[server] started {entry.name}`)
	else
		warn(`[server] {entry.name} failed to start: {err}`)
	end
end

print(`[server] {Config.Game.Name} up ({#found} systems)`)
