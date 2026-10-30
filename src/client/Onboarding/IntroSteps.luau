--!strict
-- The four things a new player is told: move, aim, fire, slide. Pure data so Lune can test it.
-- Key names come from the caller (Controls/Bindings) so the words can never drift from the real bindings.

export type Device = "touch" | "keyboard" | "gamepad"

export type Context = {
	slideKey: string, -- Bindings.actions.slide.keyboard[1], e.g. "Space"
	slideButton: string, -- Bindings.actions.slide.gamepad[1], e.g. "ButtonA"
	slideSeconds: number, -- Config.Slide.cooldown
}

export type Step = {
	id: string,
	title: string,
	text: string,
}

local IntroSteps = {}

IntroSteps.order = { "move", "aim", "fire", "slide" }

local function plainName(code: string): string
	-- "ButtonA" -> "A", "Space" -> "Space"
	local button = string.match(code, "^Button(%w+)$")
	return button or code
end

local function seconds(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.1f", n)
end

local TITLES: { [string]: string } = { move = "MOVE", aim = "AIM", fire = "FIRE", slide = "SLIDE" }

local function text(id: string, device: Device, ctx: Context): string
	if id == "move" then
		if device == "touch" then
			return "Left thumb walks you."
		elseif device == "gamepad" then
			return "Left stick walks you."
		end
		return "W A S D walks you."
	elseif id == "aim" then
		if device == "touch" then
			return "Right thumb turns you."
		elseif device == "gamepad" then
			return "Right stick turns you."
		end
		return "Point the mouse to aim."
	elseif id == "fire" then
		if device == "touch" then
			return "Push the right thumb to shoot."
		elseif device == "gamepad" then
			return "Pull the right trigger."
		end
		return "Click to shoot."
	end
	-- slide
	local wait = seconds(ctx.slideSeconds)
	if device == "touch" then
		return `Tap SLIDE to dash. {wait} s wait.`
	elseif device == "gamepad" then
		return `Press {plainName(ctx.slideButton)} to dash. {wait} s wait.`
	end
	return `Press {plainName(ctx.slideKey)} to dash. {wait} s wait.`
end

function IntroSteps.build(device: Device, ctx: Context): { Step }
	local out: { Step } = {}
	for _, id in IntroSteps.order do
		table.insert(out, { id = id, title = TITLES[id], text = text(id, device, ctx) })
	end
	return out
end

return IntroSteps
