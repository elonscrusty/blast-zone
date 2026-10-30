--!strict
-- Turns off the Roblox menu's Reset button. In a fight a reset now counts as a knock-out (the server
-- decides that, see server/AntiCheat), so this only stops a player tapping it by mistake.

local StarterGui = game:GetService("StarterGui")

local ResetButtonSystem = {}

function ResetButtonSystem.start()
	task.spawn(function()
		-- SetCore fails until the Roblox menu has loaded, so try for a little while.
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

return ResetButtonSystem
