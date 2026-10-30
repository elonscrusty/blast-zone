--!strict
-- Runs every test file, then prints a summary. Use:  lune run tests/run
-- A new piece adds its own line below for its own test file.

local Harness = require("./harness")

require("./save_retry.test")
require("./bots.test")
require("./combat.test")
require("./arena.test")
require("./config.test")
require("./guard.test")
require("./pickups.test")
require("./profile.test")
require("./core.test")
require("./zone.test")
require("./upgrades.test")
require("./controls_input.test")
require("./hud_layout.test")
require("./hud_model.test")
require("./settings_model.test")
require("./movement.test")
require("./match_controller.test")
require("./match_results_text.test")
require("./match_rules.test")

Harness.summary()
