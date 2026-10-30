--!strict
-- Builds the arena once at server start. Other pieces find it by tag (Config.Tags), so there is
-- nothing to call. The layout is picked by Config.Arena.layout.
local ArenaBuilder = require("./ArenaBuilder")
local ArtBuilder = require("./ArtBuilder")
local ArtPlan = require("./ArtPlan")
local Layout = require("./Layout")

local specs: { [string]: Layout.Spec } = {
	A = require("./LayoutA"),
	B = require("./LayoutB"),
	C = require("./LayoutC"),
}

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local ArenaSystem = {}
ArenaSystem.order = 10 -- before anything that looks for spawns or crate spots

local built: ArenaBuilder.Built? = nil

function ArenaSystem.start()
	local spec = specs[Config.Arena.layout]
	if not spec then
		warn(`[arena] no layout called {Config.Arena.layout}, using A`)
		spec = specs.A
	end
	local layout = Layout.compile(spec)
	built = ArenaBuilder.build(layout)
	if Config.Features.cityArt then
		-- Paint only. A failure here must never stop the match, so the plain graybox stays.
		local ok, err = pcall(function()
			local art = Config.Art
			local result = ArtPlan.build(layout, {
				seed = art.seed,
				towers = art.skyline.towers,
				innerGap = art.skyline.innerGap,
				outerReach = art.skyline.outerReach,
			})
			local folder = (built :: ArenaBuilder.Built).folder
			ArtBuilder.build(result, folder)
			-- the art redraws these boxes, so the bare gray ones go invisible (still solid)
			local solids = folder:FindFirstChild("Solids")
			for _, s in layout.solids do
				local box = if solids and ArtPlan.replaces(s)
					then solids:FindFirstChild(s.id)
					else nil
				if box and box:IsA("BasePart") then
					box.Transparency = 1
				end
			end
		end)
		if not ok then
			warn(`[arena] city art skipped: {err}`)
		end
	end
end

function ArenaSystem.getLayout(): Layout.Layout?
	return if built then built.layout else nil
end

return ArenaSystem
