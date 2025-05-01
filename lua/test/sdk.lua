local StructUtility = require("src.struct").StructUtility

-- Define the SDK "class"
local SDK = {}
SDK.__index = SDK

-- Constructor
function SDK:new(opts)
  -- Create a new instance (object)
  local instance = setmetatable({}, SDK)

  -- Initialize fields
  -- Lua does not have a built-in way to define private variables,
  -- but we can use a convention of prefixing with an underscore
  -- to indicate that these are intended to be private
  instance._opts = opts or {}
  instance._utility = {
    struct = StructUtility:new(),
    contextify = function(ctxmap)
      return ctxmap
    end,
    check = function(ctx)
      return {
        zed = "ZED" ..
            (instance._opts == nil and "" or
              (instance._opts.foo == nil and "" or instance._opts.foo)) ..
            "_" ..
            (ctx.meta and ctx.meta.bar or "0")
      }
    end
  }

  return instance
end

function SDK:test(opts)
  local sdkInstance = SDK:new(opts)
  return sdkInstance
end

function SDK:tester(opts)
  return SDK:new(opts or self._opts)
end

function SDK:utility()
  return self._utility
end

return {
  SDK = SDK
}
