--!strict
local Harness = require("./harness")
local FriendInvite = require("../src/shared/FriendInvite")

Harness.test("invite launch data round-trips a userId", function()
	local data = FriendInvite.makeLaunchData(330641194)
	Harness.eq(data, "inv:330641194")
	Harness.eq(FriendInvite.parseLaunchData(data), 330641194)
end)

Harness.test("odd launch data is ignored", function()
	for _, bad in
		{ nil, 42, {}, "", "inv:", "inv:-5", "inv:0", "inv:12x", "xinv:12", "inv:1.5", "inv:12 " }
	do
		Harness.eq(FriendInvite.parseLaunchData(bad), nil, `bad: {tostring(bad)}`)
	end
	Harness.eq(FriendInvite.parseLaunchData("inv:" .. string.rep("9", 40)), nil, "too long")
	Harness.eq(FriendInvite.parseLaunchData("inv:1234567890123456"), nil, "too many digits")
end)

Harness.test("host must be in this server and not the joiner", function()
	local here = { [1] = true, [2] = true }
	Harness.eq(FriendInvite.findHost(2, "inv:1", nil, here), 1, "invite")
	Harness.eq(FriendInvite.findHost(2, nil, 1, here), 1, "followed from profile")
	Harness.eq(FriendInvite.findHost(2, "inv:9", nil, here), nil, "host not here")
	Harness.eq(FriendInvite.findHost(2, "inv:2", nil, here), nil, "self")
	Harness.eq(FriendInvite.findHost(2, "inv:9", 1, here), 1, "falls back to follow")
	Harness.eq(FriendInvite.findHost(2, nil, 0, here), nil, "follow 0 means nobody")
	Harness.eq(FriendInvite.findHost(2, nil, nil, here), nil, "plain join")
end)

Harness.test("friend is queued only when the host is playing", function()
	Harness.eq(FriendInvite.shouldQueue({ queued = true, inMatch = false }), true)
	Harness.eq(FriendInvite.shouldQueue({ queued = false, inMatch = true }), true)
	Harness.eq(FriendInvite.shouldQueue({ queued = false, inMatch = false }), false)
end)

Harness.test("invite button shows in the lobby and while watching, not while fighting", function()
	Harness.eq(FriendInvite.showButton("Waiting", false), true)
	Harness.eq(FriendInvite.showButton("Countdown", false), true)
	Harness.eq(
		FriendInvite.showButton("Active", false),
		false,
		"watching: no invite over the spectate bar"
	)
	Harness.eq(FriendInvite.showButton("Active", true), false, "fighting")
	Harness.eq(FriendInvite.showButton("FinalPressure", true), false)
	Harness.eq(FriendInvite.showButton("Results", false), false, "results screen")
end)

Harness.test("feed lines", function()
	Harness.eq(FriendInvite.hostLine("Sam"), "Sam joined you!")
	Harness.eq(FriendInvite.friendLine("Carter", true), "You joined Carter! Next match soon")
	Harness.eq(FriendInvite.friendLine("Carter", false), "You joined Carter!")
end)
