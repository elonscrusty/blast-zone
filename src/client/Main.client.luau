--!strict
-- Client start. Phone first: every control needs a touch button too.
-- Starts every "...System" module under this folder (see shared/Boot.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)
local Config = require(Shared.Config)

type System = { order: number?, start: () -> () }
local found: { { name: string, order: number?, module: System } } = {}

for _, inst in script.Parent:GetDescendants() do
	if inst:IsA("ModuleScript") and Boot.isSystemName(inst.Name) then
		local ok, result = pcall(require, inst)
		if ok then
			table.insert(found, { name = inst.Name, order = result.order, module = result })
		else
			warn(`[client] could not load {inst.Name}: {result}`)
		end
	end
end

for _, entry in Boot.sort(found) do
	local ok, err = pcall(entry.module.start)
	if ok then
		print(`[client] started {entry.name}`)
	else
		warn(`[client] {entry.name} failed to start: {err}`)
	end
end

print(`[client] {Config.Game.Name} up ({#found} systems)`)
