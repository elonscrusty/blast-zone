--!strict
-- Turns off the Roblox buttons that sit where our own screen lives: the player list (top right), the backpack,
-- the emote menu (we have our own EMOTE wheel) and the health bar (the HUD draws health). The Roblox menu and
-- chat buttons stay (top left); Ui/DeviceZones says where they are and the phone audit keeps our UI clear of them.
-- Roblox may not be ready for this on the first frame, so it tries again a few times.

local StarterGui = game:GetService("StarterGui")

local CoreGuiSystem = {}
CoreGuiSystem.order = 5

local HIDE = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.Health,
}

local function hideAll(): boolean
	local ok = true
	for _, kind in HIDE do
		local done = pcall(function()
			StarterGui:SetCoreGuiEnabled(kind, false)
		end)
		ok = ok and done
	end
	return ok
end

function CoreGuiSystem.start()
	task.spawn(function()
		for attempt = 1, 6 do
			if hideAll() then
				return
			end
			task.wait(attempt) -- waits longer each time
		end
		warn(
			"[coregui] could not hide the Roblox player list and backpack; the top right may be crowded"
		)
	end)
end

return CoreGuiSystem
