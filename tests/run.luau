--!strict
-- Runs every test file, then prints a summary. Use:  lune run tests/run
-- A new piece adds its own line below for its own test file.

local Harness = require("./harness")

require("./save_retry.test")
require("./config.test")
require("./guard.test")
require("./core.test")
require("./movement.test")

Harness.summary()
