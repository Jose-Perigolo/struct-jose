--[[
  Client test suite for the struct module.
  This matches the structure and tests found in client.test.ts.
  Run with: busted client_test.lua
]]

package.path = package.path .. ";./test/?.lua"

local runnerModule = require("runner")
local makeRunner = runnerModule.makeRunner

local SDK = require("sdk")

local TEST_JSON_FILE = "../build/test/test.json"

describe('client', function()
  local runner = makeRunner(TEST_JSON_FILE, SDK:test())
  local runnerCheck = runner('check')
  local spec, runset, subject = runnerCheck.spec, runnerCheck.runset, runnerCheck.subject

  test('client-check-basic', function()
    runset(spec.basic, subject)
  end)
end)
