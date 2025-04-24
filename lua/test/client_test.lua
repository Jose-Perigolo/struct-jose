--[[
  Client test suite for the struct module.
  This matches the structure and tests found in client.test.ts.
  Run with: busted client_test.lua
]]

-- Update package.path to include the current directory for module loading
package.path = package.path .. ";./test/?.lua"

local assert = require("luassert")

-- Import the runner module
local runnerModule = require("runner")
local makeRunner = runnerModule.makeRunner

-- Import the SDK module
local SDK = require("sdk")

local TEST_JSON_FILE = "../build/test/test.json"

----------------------------------------------------------
-- Client Tests
----------------------------------------------------------

describe('client', function()
  -- This test matches the TypeScript implementation in client.test.ts
  local runner = makeRunner(TEST_JSON_FILE, SDK:test())
  local runpack = runner('check')
  local spec, runset, subject = runpack.spec, runpack.runset, runpack.subject

  test('client-check-basic', function()
    runset(spec.basic, subject)
  end)
end)
