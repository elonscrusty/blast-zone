--!strict
-- Builds the arena at server start, then swaps to the next map in Config.Arena.rotation (or a
-- vote's pick) as each match starts. Other pieces find the arena by tag (Config.Tags) and read the tags fresh
-- every match, so there is nothing to call. Workspace.Arena carries LayoutId, LayoutName and
-- NextLayoutName attributes for any screen that wants to show the map.
local ArenaBuilder = require("./ArenaBuilder")
local ArtBuilder = require("./ArtBuilder")
local ArtPlan = require("./ArtPlan")
local Layout = require("./Layout")
local MapRotation = require("./MapRotation")

local specs: { [string]: Layout.Spec } = {
	A = require("./LayoutA"),
	B = require("./LayoutB"),
	C = require("./LayoutC"),
	D = require("./LayoutD"),
	E = require("./LayoutE"),
	F = require("./LayoutF"),
}

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)

local ArenaSystem = {}
ArenaSystem.order = 10 -- before anything that looks for spawns or crate spots

local built: ArenaBuilder.Built? = nil
local rotation: MapRotation.MapRotation? = nil
local chooser: (() -> string?)? = nil

local function buildMap(id: string)
	local spec = specs[id] or specs.C
	built = ArenaBuilder.build(Layout.compile(spec))
	local folder = (built :: ArenaBuilder.Built).folder
	folder:SetAttribute("LayoutName", spec.name)
	if rotation then
		local nextSpec = specs[rotation:peekNext()]
		folder:SetAttribute("NextLayoutName", if nextSpec then nextSpec.name else nil)
	end
end

function ArenaSystem.start()
	local list = Config.Arena.rotation or { Config.Arena.layout }
	rotation = MapRotation.new(list, specs, Config.Arena.layout)
	local r = rotation :: MapRotation.MapRotation
	for _, id in r.dropped do
		warn(`[arena] no layout called {id} in Config.Arena.rotation, skipping it`)
	end
<<<<<<< HEAD
	buildMap(r:current())

	-- Pick the map for each match as it goes Countdown -> Spawning. The phase signal fires before
	-- the match reads spawn points, so containers and spawns follow the new map. The first match
	-- plays the map built at start, unless a vote already chose another.
	local firstMatch = true
	MatchContext.PhaseChanged:connect(function(phase: string)
		if phase ~= "Spawning" then
			return
		end
		local winner = if chooser then chooser() else nil
		local before = r:current()
		local changed = false
		if winner and r:select(winner) then
			changed = r:current() ~= before
		elseif not firstMatch and #r.order >= 2 then
			r:advance()
			changed = true
		end
		firstMatch = false
		if changed then
			buildMap(r:current())
		end
	end)
end

-- A vote (or anything else) can name the next map: fn returns a map id, or nil to keep rotating.
-- Called once per match, right before the map is built.
function ArenaSystem.setChooser(fn: (() -> string?)?)
	chooser = fn
=======
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
>>>>>>> origin/claude/project-thread-wkrr14
end

function ArenaSystem.getLayout(): Layout.Layout?
	return if built then built.layout else nil
end

return ArenaSystem
