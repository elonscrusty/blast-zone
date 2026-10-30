--!strict
-- When the big map is open. Pure Luau so Lune can check it.
-- It opens from the minimap tap, the map key or the pad's Y, and only while the HUD shows (a live
-- fight and you are still in it). It closes on another tap, on its own after `autoCloseSeconds`
-- (0 = stays), and the moment the HUD goes away. The map never stops the game; you keep moving.

local BigMapModel = {}

export type Model = {
	open: boolean,
	openedAt: number,
}

function BigMapModel.new(): Model
	return { open = false, openedAt = 0 }
end

function BigMapModel.close(m: Model)
	m.open = false
end

-- Tap again to close. `allowed` is false when the HUD is hidden, so it cannot open then.
function BigMapModel.toggle(m: Model, now: number, allowed: boolean)
	if m.open then
		m.open = false
	elseif allowed then
		m.open = true
		m.openedAt = now
	end
end

-- Call every frame. Returns whether the map should be drawn.
function BigMapModel.step(
	m: Model,
	now: number,
	allowed: boolean,
	autoCloseSeconds: number
): boolean
	if m.open then
		if not allowed then
			m.open = false
		elseif autoCloseSeconds > 0 and now - m.openedAt >= autoCloseSeconds then
			m.open = false
		end
	end
	return m.open
end

return BigMapModel
