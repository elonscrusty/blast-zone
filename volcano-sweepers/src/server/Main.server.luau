--!strict
-- Server boot. Starts every service in a fixed order; each step is wrapped in pcall so one broken
-- (or not yet written) service only prints a warning and never stops the others.
--
-- Each entry is the module's path under ServerScriptService.Server. A module is found with
-- FindFirstChild (never WaitForChild, so a missing one can't hang the boot) and loaded with
-- pcall(require). Every service exports init().

local Server = script.Parent :: Instance

local BOOT_ORDER: { { string } } = {
	{ "Core", "Net" },
	{ "Profile", "Profiles" },
	{ "Player", "PlayerState" },
	{ "World", "World" },
	{ "Ash", "AshService" },
	{ "Sweep", "SweepService" },
	{ "Sweep", "SellService" },
	{ "Finds", "FindsService" },
	{ "Burp", "BurpService" },
	{ "Player", "PurchaseService" },
	{ "Helpers", "HelperService" },
	{ "Player", "DailyService" },
	{ "Player", "GoalService" },
	{ "Player", "CoolDownService" },
}

local function findModule(path: { string }): ModuleScript?
	local node: Instance? = Server
	for _, name in path do
		node = if node ~= nil then node:FindFirstChild(name) else nil
	end
	if node ~= nil and node:IsA("ModuleScript") then
		return node
	end
	return nil
end

local started, failed = 0, 0

for _, path in BOOT_ORDER do
	local label = table.concat(path, "/")
	local module = findModule(path)
	if module == nil then
		failed += 1
		warn(`[Boot] {label} is missing, skipped`)
		continue
	end
	local okRequire, service = pcall(require, module)
	if not okRequire then
		failed += 1
		warn(`[Boot] {label} failed to load: {service}`)
		continue
	end
	local init = if type(service) == "table" then (service :: any).init else nil
	if type(init) ~= "function" then
		failed += 1
		warn(`[Boot] {label} has no init(), skipped`)
		continue
	end
	local okInit, err = pcall(init)
	if okInit then
		started += 1
	else
		failed += 1
		warn(`[Boot] {label}.init failed: {err}`)
	end
end

print(`[Boot] server ready: {started} services started, {failed} skipped`)
