--[[
  SDK utility for the Lua implementation of the struct module.
  This matches the structure found in ts/test/sdk.ts.
]]

-- Update to use the correct path for the struct module
local struct = require("src.struct")

-- StructUtility class - wrapper for struct functions
local StructUtility = {}
StructUtility.__index = StructUtility

function StructUtility:new()
  local instance = {}
  setmetatable(instance, StructUtility)
  
  -- Add all struct functions to the utility
  for k, v in pairs(struct) do
    instance[k] = v
  end
  
  return instance
end

-- Utility class
local Utility = {}
Utility.__index = Utility

function Utility:new(opts)
  local instance = {}
  setmetatable(instance, Utility)
  
  instance._opts = opts or {}
  instance._struct = StructUtility:new()
  
  return instance
end

function Utility:contextify(ctxmap)
  return ctxmap
end

function Utility:check(ctx)
  return {
    zed = "ZED" .. 
      (self._opts == nil and "" or self._opts.foo == nil and "" or self._opts.foo) ..
      "_" ..
      (ctx.meta == nil or ctx.meta.bar == nil and "0" or ctx.meta.bar)
  }
end

function Utility:struct()
  return self._struct
end

-- SDK class
local SDK = {}
SDK.__index = SDK

-- Create a new SDK instance
function SDK:new(opts)
  local instance = {}
  setmetatable(instance, SDK)
  
  instance._opts = opts or {}
  instance._utility = Utility:new(opts)
  
  return instance
end

-- Static test function
function SDK.test(opts)
  return SDK:new(opts)
end

-- Tester method
function SDK:tester(opts)
  return SDK:new(opts or self._opts)
end

-- Get the utility
function SDK:utility()
  return self._utility
end

return SDK 
