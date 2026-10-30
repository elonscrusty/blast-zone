--!strict
-- One warning on screen at a time (carter: the first HUD was "way too cluttered").
-- Order comes from the brief: danger first, then health/control, weapon readiness, zone news.

export type Inputs = {
	outsideZone: boolean, -- standing outside the safe circle while it is hurting
	suddenDeath: boolean,
	lowHealth: boolean,
	weaponEmpty: boolean, -- magazine empty and not already reloading
	reloading: boolean,
	zoneWarningSeconds: number?, -- a closure is announced; seconds until it starts
	zoneClosing: boolean,
	notice: string?, -- text from the Notice remote
}

export type Warning = { key: string, text: string, severity: "danger" | "warn" | "info" }

local Warnings = {}

-- Strongest first. Each rule returns a warning or nil.
local rules: { (Inputs) -> Warning? } = {
	function(i)
		if i.outsideZone then
			return { key = "outside", text = "OUTSIDE THE ZONE", severity = "danger" }
		end
		return nil
	end,
	function(i)
		if i.suddenDeath then
			return { key = "suddenDeath", text = "SUDDEN DEATH", severity = "danger" }
		end
		return nil
	end,
	function(i)
		if i.lowHealth then
			return { key = "lowHealth", text = "LOW HEALTH", severity = "danger" }
		end
		return nil
	end,
	function(i)
		if i.weaponEmpty then
			return { key = "empty", text = "RELOAD!", severity = "warn" }
		end
		return nil
	end,
	function(i)
		local s = i.zoneWarningSeconds
		if s ~= nil then
			return {
				key = "zoneWarning",
				text = "ZONE CLOSING IN " .. math.max(0, math.ceil(s)),
				severity = "warn",
			}
		end
		return nil
	end,
	function(i)
		if i.zoneClosing then
			return { key = "zoneClosing", text = "ZONE CLOSING", severity = "warn" }
		end
		return nil
	end,
	function(i)
		if i.notice ~= nil and i.notice ~= "" then
			return { key = "notice", text = i.notice, severity = "info" }
		end
		return nil
	end,
}

function Warnings.pick(inputs: Inputs): Warning?
	for _, rule in rules do
		local w = rule(inputs)
		if w then
			return w
		end
	end
	return nil
end

return Warnings
