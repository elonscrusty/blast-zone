--!strict
-- Client bootstrap. Loads every client module in order, each inside its own pcall so one broken
-- module cannot stop the rest, then tells the server we are ready (it answers with the full state
-- and the ash snapshot, so every handler must be attached BEFORE that).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
if Shared == nil then
	warn("[Main] ReplicatedStorage.Shared never appeared")
	return
end
local Config = require(Shared:WaitForChild("Config") :: ModuleScript) :: any
local waitSeconds: number = Config.Net.clientWaitSeconds
if ReplicatedStorage:WaitForChild("Remotes", waitSeconds) == nil then
	warn("[Main] ReplicatedStorage.Remotes never appeared")
	return
end

local root = script.Parent

local function load(label: string, inst: Instance?): any?
	if inst == nil or not inst:IsA("ModuleScript") then
		warn(`[Main] module {label} not found`)
		return nil
	end
	local ok, result = pcall(require, inst)
	if not ok then
		warn(`[Main] {label} failed to load: {result}`)
		return nil
	end
	return result
end

local function loadFrom(folderName: string, moduleName: string): any?
	local folder = root:FindFirstChild(folderName)
	local mod = if folder ~= nil then folder:FindFirstChild(moduleName) else nil
	return load(`{folderName}.{moduleName}`, mod)
end

-- Safe to call: a module that errors in init() is reported and skipped.
local function init(label: string, mod: any?)
	if type(mod) == "table" and type((mod :: any).init) == "function" then
		local ok, err = pcall((mod :: any).init)
		if not ok then
			warn(`[Main] {label}.init failed: {err}`)
		end
	end
end

-- 1. my core modules, in the order the contract lists them
loadFrom("Core", "Store")
loadFrom("Core", "Net")
loadFrom("Core", "Sfx")
loadFrom("Core", "Haptics")
loadFrom("Core", "Controls")
loadFrom("Ash", "AshRenderer")
loadFrom("Vfx", "Vfx")
loadFrom("Core", "CameraFx")
loadFrom("Vfx", "HeldTool") -- the tool in every hand + the swing
loadFrom("Vfx", "BotAnim") -- helper bots' spinning brushes and bobbing bulbs
loadFrom("Vfx", "WorldFeel") -- "+N" per swing, FULL!, footstep dust

-- 2. UI written by other pieces (all optional): the panel host first, then every panel (each one
--    registers itself on require), then the HUD
local panelHostFolder = root:FindFirstChild("Ui")
if panelHostFolder ~= nil then
	load("Ui.PanelHost", panelHostFolder:FindFirstChild("PanelHost"))
end

local panels = root:FindFirstChild("Panels")
if panels ~= nil then
	local found: { ModuleScript } = {}
	if panels:IsA("ModuleScript") then
		table.insert(found, panels)
	end
	for _, inst in panels:GetDescendants() do
		if inst:IsA("ModuleScript") then
			table.insert(found, inst)
		end
	end
	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	for _, mod in found do
		load(`Panels.{mod.Name}`, mod)
	end
end

init("Hud.Hud", loadFrom("Hud", "Hud"))

-- 3. first-time hints
init("Core.Tutorial", loadFrom("Core", "Tutorial"))

-- 4. no Roblox backpack bar (our own HUD has the pack bar and tools are chosen in a panel)
task.spawn(function()
	for _ = 1, 8 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(1)
	end
end)

-- 5. everything is attached: ask for the full state and the ash snapshot. A lost message would leave
--    the player frozen (no sweep, no sell), so ask again every few seconds until the first State
--    arrives (the server treats a repeat as a no-op and rate-limits it).
local net = loadFrom("Core", "Net")
local store = loadFrom("Core", "Store")
if net ~= nil then
	net.send("ClientReady")
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(3)
			if store ~= nil and store.ready == true then
				return
			end
			net.send("ClientReady")
		end
	end)
else
	warn("[Main] Net missing: cannot send ClientReady")
end
