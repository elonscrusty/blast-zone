--!strict
-- Runs every test file, then prints a summary. Use (from volcano-sweepers/):  lune run tests/run
-- Each piece adds ONE line below for its own test file(s).

local Harness = require("./harness")

require("./save_retry.test")
require("./rng.test")

Harness.summary()
