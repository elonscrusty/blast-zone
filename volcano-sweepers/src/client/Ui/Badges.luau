--!strict
-- Red-dot state shared by the MENU button (one dot for everything) and the tiles in the menu.
-- Two sources: "manual" dots set by panels through Hud.setBadge (Book: a set to claim, Goals: a
-- goal to claim) and "auto" dots worked out by the HUD from the store (shared/Ui/MenuModel).
--
--   Badges.setManual(panelId, on)   Badges.setAuto({ [panelId]: true })
--   Badges.isOn(panelId) -> boolean Badges.anyOn() -> boolean
--   Badges.changed                  Signal: fires after any change

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)

local Badges = {}

Badges.changed = Signal.new()

local manual: { [string]: boolean } = {}
local auto: { [string]: boolean } = {}

-- Panel ids can be spelled a few ways ("cool_down", "CoolDown"): compare them squashed.
local function squash(id: string): string
	return (string.gsub(string.lower(id), "[^%w]", ""))
end

function Badges.setManual(panelId: string, on: boolean)
	local key = squash(panelId)
	if (manual[key] == true) == on then
		return
	end
	manual[key] = if on then true else nil
	Badges.changed:fire()
end

function Badges.setAuto(dots: { [string]: boolean })
	local fresh: { [string]: boolean } = {}
	for id, on in dots do
		if on then
			fresh[squash(id)] = true
		end
	end
	local same = true
	for key in fresh do
		if auto[key] ~= true then
			same = false
		end
	end
	for key in auto do
		if fresh[key] ~= true then
			same = false
		end
	end
	if same then
		return
	end
	auto = fresh
	Badges.changed:fire()
end

function Badges.isOn(panelId: string): boolean
	local key = squash(panelId)
	return manual[key] == true or auto[key] == true
end

function Badges.anyOn(): boolean
	return next(manual) ~= nil or next(auto) ~= nil
end

return Badges
