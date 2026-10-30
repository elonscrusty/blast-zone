--!strict
-- Which screen sits on top of which. Every ScreenGui sets DisplayOrder from this list, never a
-- bare number, so a new lobby button or panel cannot end up under (or over) the wrong screen.
-- Pure numbers so Lune can check them. The rule is written in plans/CONTRACTS.md ("Screen layers").

local UiLayers = {}

UiLayers.ZoneTint = 5 -- red screen edges and the zone arrow; never takes taps
UiLayers.TouchControls = 9 -- thumb sticks and buttons
UiLayers.Hud = 10 -- health, minimap, timer, gear
UiLayers.Calm = 15 -- widgets shown between fights that are not lobby buttons
UiLayers.Moments = 17 -- big banners (double kill, circle closing); over the HUD, under upgrade cards
UiLayers.Popups = 20 -- upgrade cards, bots banner
UiLayers.Spectate = 30 -- spectate arrows
UiLayers.MatchFlow = 50 -- lobby (PLAY, SETTINGS, every LobbyMenu slot), countdown, banners, results
UiLayers.MatchFlowBanner = 52 -- winner banner, over the results screen
UiLayers.MatchFlowExtra = 55 -- add-ons drawn over the results screen (coins strip)
UiLayers.Modal = 100 -- full panels with a dim behind them: settings, track, loadout, shop
UiLayers.Onboarding = 110 -- first-time intro; blocks everything under it
UiLayers.Toast = 120 -- short messages (saved, error); never takes taps

-- Bottom to top.
UiLayers.order = {
	"ZoneTint",
	"TouchControls",
	"Hud",
	"Calm",
	"Moments",
	"Popups",
	"Spectate",
	"MatchFlow",
	"MatchFlowBanner",
	"MatchFlowExtra",
	"Modal",
	"Onboarding",
	"Toast",
}

function UiLayers.get(name: string): number
	local value = (UiLayers :: any)[name]
	assert(type(value) == "number", "unknown UI layer " .. name)
	return value
end

return UiLayers
