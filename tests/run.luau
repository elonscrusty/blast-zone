--!strict
-- Runs every test file, then prints a summary. Use:  lune run tests/run

local Harness = require("./harness")

require("./save_retry.test")
require("./arena.test")

Harness.summary()
