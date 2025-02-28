local lu = require("luaunit")
local json = require("dkjson")
local path = require("pl.path")
local io = io


local function matchval(check, base)
  if check == '__UNDEF__' then
    check = nil
  end

  local pass = (check == base)

  if not pass then
    if type(check) == "string" then
      local basestr = tostring(base)
      local rem = string.match(check, "^/(.+)/$")

      if rem then
        pass = string.find(basestr, rem) ~= nil
      else
        pass = string.find(string.lower(basestr), string.lower(tostring(check))) ~= nil
      end
    elseif type(check) == "function" then
      pass = true
    end
  end
  return pass
end

local function runner(name, store, testfile, provider)
  local client     = provider.test()
  local utility    = client.utility()
  local struct     = utility.struct

  local clone      = struct.clone
  local getpath    = struct.getpath
  local inject     = struct.inject
  local ismap      = struct.ismap
  local items      = struct.items
  local stringify  = struct.stringify
  local walk       = struct.walk
  local isnode     = struct.isnode

  local currentDir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
  local filename   = path.join(currentDir, testfile)

  local f          = io.open(filename, "r")
  if not f then error("Cannot open file: " .. filename) end
  local alltestsStr = f:read("*a")
  f:close()
  local alltests, pos, err = json.decode(alltestsStr, 1, nil)

  if err then error(err) end

  local spec = nil
  if alltests.primary and alltests.primary[name] then
    spec = alltests.primary[name]
  elseif alltests[name] then
    spec = alltests[name]
  else
    spec = alltests
  end

  local clients = {}
  if spec.DEF then
    for _, cdef in ipairs(items(spec.DEF.client)) do
      local copts = (cdef[2].test and cdef[2].test.options) or {}
      if ismap(store) then
        inject(copts, store)
      end

      clients[cdef[1]] = provider.test(copts)
    end
  end

  local subject = utility[name]

  local function match(check, base, struct)
    walk(check, function(_key, val, _parent, path)
      if not isnode(val) then
        local baseval = getpath(path, base)

        if not matchval(val, baseval) then
          lu.fail("MATCH: " .. table.concat(path, ".") ..
            ": [" .. stringify(val) .. "] <=> [" .. stringify(baseval) .. "]")
        end
      end
    end)
  end


  local function runset(testspec, testsubject, makesubject)
    testsubject = testsubject or subject

    for _, entry in ipairs(testspec.set) do
      local ok, err = pcall(function()
        local testclient = client

        if entry.client then
          testclient = clients[entry.client]
          testsubject = client.utility()[name]
        end

        if makesubject then
          testsubject = makesubject(testsubject)
        end

        local args = { clone(entry["in"]) }

        if entry.ctx then
          args = { entry.ctx }
        elseif entry.args then
          args = entry.args
        end

        if entry.ctx or entry.args then
          local first = args[1]
          if ismap(first) then
            entry.ctx = clone(first)
            args[1] = entry.ctx
            entry.ctx.client = testclient
            entry.ctx.utility = testclient.utility()
          end
        end

        local res = testsubject(table.unpack(args))
        entry.res = res

        if entry.match == nil or entry.out ~= nil then
          local resComparable = (res ~= nil) and json.decode(json.encode(res)) or res
          lu.assertEquals(resComparable, entry.out)
        end

        if entry.match then
          match(entry.match, { ["in"] = entry["in"], out = entry.res, ctx = entry.ctx }, struct)
        end
      end)

      if not ok then
        entry.thrown = err
        local entry_err = entry.err

        if entry_err ~= nil then
          if entry_err == true or matchval(entry_err, err) then
            if entry.match then
              match(entry.match, { ["in"] = entry["in"], out = entry.res, ctx = entry.ctx, err = err })
            end
          else
            lu.fail("ERROR MATCH: [" .. stringify(entry_err) .. "] <=> [" .. err .. "]")
          end
        else
          lu.fail(err)
        end
      end
    end
  end

  return {
    spec = spec,
    runset = runset,
    subject = subject,
  }
end

return { runner = runner }
