local json = require("dkjson")
local lfs = require("lfs")
local luassert = require("luassert")

-- Custom null value as a string
local NULL_STRING = "null"

local function readFileSync(path)
  local file = io.open(path, "r")
  if not file then
    error("Cannot open file: " .. path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function join(...)
  return table.concat({...}, "/")
end

local function fail(msg)
  luassert(false, msg)
end

local function deepEqual(actual, expected)
  luassert.same(expected, actual)
end

local function resolveArgs(entry, testpack)
  local structUtils = testpack.utility.struct
  local args = {structUtils.clone(entry["in"])}

  if entry.ctx then
    args = {entry.ctx}
  end

  if entry.args then
    args = entry.args
  end

  if entry.ctx or entry.args then
    local first = args[1]
    if type(first) == "table" and first ~= nil then
      local cloned_value = structUtils.clone(args[1]) -- Note: Lua arrays are 1-indexed
      args[1] = cloned_value
      first = cloned_value
      entry.ctx = cloned_value

      first.client = testpack.client
      first.utility = testpack.utility
    end
  end

  return args
end

local function resolveTestPack(name, entry, subject, client, clients)
  local pack = {
    client = client,
    subject = subject,
    utility = client.utility()
  }

  if entry.client then
    pack.client = clients[entry.client]
    pack.utility = pack.client.utility()
    pack.subject = pack.utility[name]
  end

  return pack
end

local function resolveSpec(name, testfile)
  local alltests = json.decode(readFileSync(join(lfs.currentdir(), testfile)),
    1, NULL_STRING)
  local spec =
    (alltests.primary and alltests.primary[name]) or (alltests[name]) or
      alltests
  return spec
end

local function resolveClients(spec, store, provider, structUtils)
  local clients = {}

  if spec.DEF then
    for _, cdef in ipairs(structUtils.items(spec.DEF.client)) do
      local copts = cdef[2].test.options or {}
      if type(store) == "table" then
        structUtils.inject(copts, store)
      end

      clients[cdef[1]] = provider.test(copts)
    end
  end

  return clients
end

local function matchval(check, base, structUtils)
  if check == '__UNDEF__' then
    check = nil
  end

  local pass = check == base

  if not pass then
    if type(check) == "string" then
      local basestr = structUtils.stringify(base)

      -- Check if string starts and ends with '/'
      local rem = check:match("^/(.+)/$")
      if rem then
        -- Lua pattern matching instead of RegExp
        pass = basestr:match(rem) ~= nil
      else
        -- Convert both strings to lowercase and check if one contains the other
        pass = basestr:lower():find(structUtils.stringify(check):lower(), 1,
          true) ~= nil
      end
    elseif type(check) == "function" then
      pass = true
    end
  end

  return pass
end

local function match(check, base, structUtils)
  structUtils.walk(check, function(_key, val, _parent, path)
    local scalar = type(val) ~= "table"
    if scalar then
      local baseval = structUtils.getpath(path, base)

      if not matchval(val, baseval, structUtils) then
        fail("MATCH: " .. table.concat(path, ".") .. ": [" ..
               structUtils.stringify(val) .. "] <=> [" ..
               structUtils.stringify(baseval) .. "]")
      end
    end
  end)
end

local function handleError(entry, err, structUtils)
  entry.thrown = err

  local entry_err = entry.err
  local err_message = (type(err) == "table" and err.message) or tostring(err)

  -- Handle expected errors
  if entry_err ~= nil then
    if entry_err == true or matchval(entry_err, err_message, structUtils) then
      if entry.match then
        match(entry.match, {
          ["in"] = entry["in"],
          out = entry.res,
          ctx = entry.ctx,
          err = err
        }, structUtils)
      end
      return true
    end

    -- DO NOT USE fail() here - it throws an error
    print("ERROR MATCH FAILED: [" .. structUtils.stringify(entry_err) ..
            "] <=> [" .. err_message .. "]")

    -- Return false to indicate failure, but don't throw
    return false
  end

  -- DO NOT USE fail() here - it throws an error
  print("UNEXPECTED ERROR: " .. err_message .. "\n\nENTRY: " ..
          structUtils.stringify(entry))

  -- Return false to indicate failure, but don't throw
  return false
end

local function checkResult(entry, res, structUtils)
  if entry.match == nil or entry.out ~= nil then
    -- NOTE: don't use clone as we want to strip functions
    if res ~= nil then
      local json_str = json.encode(res)
      local decoded = json.decode(json_str, 1, NULL_STRING) -- Use NULL_STRING for null values
      deepEqual(decoded, entry.out)
    else
      deepEqual(res, entry.out)
    end
  end

  if entry.match then
    match(entry.match, {
      ["in"] = entry["in"],
      out = entry.res,
      ctx = entry.ctx
    }, structUtils)
  end
end

local function runner(name, store, testfile, provider)
  local client = provider.test()
  local utility = client.utility()
  local structUtils = utility.struct

  local spec = resolveSpec(name, testfile)

  local clients = resolveClients(spec, store, provider, structUtils)

  local subject = utility[name]

  local function runset(testspec, testsubject)
    subject = testsubject or subject

    for _, entry in ipairs(testspec.set) do
      local success, err = pcall(function()
        local testpack = resolveTestPack(name, entry, subject, client, clients)
        local args = resolveArgs(entry, testpack)

        local res, validation_error = testpack.subject(table.unpack(args))

        if validation_error then
          -- Return here to prevent further execution if validation error is handled
          local handled = handleError(entry, validation_error, structUtils)
          if not handled then
            -- Only use luassert here, at the top level
            luassert(false, "Test failed: " .. tostring(validation_error))
          end
          return
        end

        entry.res = res
        checkResult(entry, res, structUtils)
      end)

      if not success then
        local handled = handleError(entry, err, structUtils)
        if not handled then
          -- Only use luassert here, at the top level
          luassert(false, "Test failed: " .. tostring(err))
        end
      end
    end
  end

  return {
    spec = spec,
    runset = runset,
    subject = subject
  }
end

return runner
