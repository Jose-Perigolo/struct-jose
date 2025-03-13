const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { deepEqual, fail, AssertionError } = require('node:assert')


async function runner(name, store, testfile, provider) {

  const client = await provider.test()
  const utility = client.utility()
  const structUtils = utility.struct

  let spec = resolveSpec(name, testfile)

  let clients = await resolveClients(spec, store, provider, structUtils)

  let subject = utility[name]

  let runset = async (testspec, testsubject) => {
    subject = testsubject || subject

    for (let entry of testspec.set) {
      try {
        let testpack = resolveTestPack(name, entry, subject, client, clients)
        let args = resolveArgs(entry, testpack)

        let res = await testpack.subject(...args)
        entry.res = res

        checkResult(entry, res, structUtils)
      }
      catch (err) {
        handleError(entry, err, structUtils)
      }
    }
  }

  return {
    spec,
    runset,
    subject,
  }
}


// Handle errors from test execution
function handleError(entry, err, structUtils) {
  entry.thrown = err
  
  const entry_err = entry.err

  // If the test expects an error
  if (null != entry_err) {
    // If the test just expects any error, or if the error message matches what's expected
    if (true === entry_err || matchval(entry_err, err.message, structUtils)) {
      // If there's a match pattern, try to match it against the error
      if (entry.match) {
        match(
          entry.match,
          { in: entry.in, out: entry.res, ctx: entry.ctx, err },
          structUtils
        )
      }
      
      // Error was expected and matched, so we're done with this test
      return true
    }

    // Expected error didn't match the actual error
    fail('ERROR MATCH: [' + structUtils.stringify(entry_err) +
      '] <=> [' + err.message + ']')
  }
  // Unexpected error (test didn't specify an error expectation)
  else if (err instanceof AssertionError) {
    fail(err.message + '\n\nENTRY: ' + JSON.stringify(entry, null, 2))
  }
  else {
    fail(err.stack + '\\nnENTRY: ' + JSON.stringify(entry, null, 2))
  }
  
  return false
}


function checkResult(entry, res, structUtils) {
  if (undefined === entry.match || undefined !== entry.out) {
    // NOTE: don't use clone as we want to strip functions
    deepEqual(null != res ? JSON.parse(JSON.stringify(res)) : res, entry.out)
  }

  if (entry.match) {
    match(
      entry.match,
      { in: entry.in, out: entry.res, ctx: entry.ctx },
      structUtils
    )
  }

}


function resolveArgs(entry, testpack) {
  const structUtils = testpack.utility.struct
  let args = [structUtils.clone(entry.in)]

  if (entry.ctx) {
    args = [entry.ctx]
  }
  else if (entry.args) {
    args = entry.args
  }

  if (entry.ctx || entry.args) {
    let first = args[0]
    if ('object' === typeof first && null != first) {
      entry.ctx = first = args[0] = structUtils.clone(args[0])
      first.client = testpack.client
      first.utility = testpack.utility
    }
  }

  return args
}


function resolveTestPack(
  name,
  entry,
  subject,
  client,
  clients
) {
  const pack = {
    client,
    subject,
    utility: client.utility(),
  }

  if (entry.client) {
    pack.client = clients[entry.client]
    pack.utility = pack.client.utility()
    pack.subject = pack.utility[name]
  }

  return pack
}


function resolveSpec(name, testfile) {
  const alltests =
    JSON.parse(readFileSync(join(
      __dirname, testfile), 'utf8'))

  let spec = alltests.primary?.[name] || alltests[name] || alltests
  return spec
}


async function resolveClients(
  spec,
  store,
  provider,
  structUtils
) {

  const clients = {}
  if (spec.DEF) {
    for (let cdef of structUtils.items(spec.DEF.client)) {
      const copts = cdef[1].test.options || {}
      if ('object' === typeof store) {
        structUtils.inject(copts, store)
      }

      clients[cdef[0]] = await provider.test(copts)
    }
  }
  return clients
}


function match(
  check,
  base,
  structUtils
) {
  structUtils.walk(check, (_key, val, _parent, path) => {
    let scalar = 'object' != typeof val
    if (scalar) {
      let baseval = structUtils.getpath(path, base)

      if (!matchval(val, baseval, structUtils)) {
        fail('MATCH: ' + path.join('.') +
          ': [' + structUtils.stringify(val) + '] <=> [' + structUtils.stringify(baseval) + ']')
      }
    }
  })
}


function matchval(
  check,
  base,
  structUtils
) {
  check = '__UNDEF__' === check ? undefined : check

  let pass = check === base

  if (!pass) {

    if ('string' === typeof check) {
      let basestr = structUtils.stringify(base)

      let rem = check.match(/^\/(.+)\/$/)
      if (rem) {
        pass = new RegExp(rem[1]).test(basestr)
      }
      else {
        pass = basestr.toLowerCase().includes(structUtils.stringify(check).toLowerCase())
      }
    }
    else if ('function' === typeof check) {
      pass = true
    }
  }

  return pass
}



module.exports = {
  runner
}

