
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { deepEqual, fail, AssertionError } from 'node:assert'


type Provider = {
  test: (opts?: Record<string, any>) => Promise<Client>
}

type Client = {
  utility: () => Utility
}

type Utility = {
  struct: StructUtility
}

type StructUtility = {
  clone: (val: any) => any,
  getpath: (path: string | string[], store: any) => any,
  inject: (val: any, store: any) => any,
  items: (val: any) => [number | string, any][],
  stringify: (val: any, maxlen?: number) => string
  walk: (
    val: any,
    apply: (
      key: string | number | undefined,
      val: any,
      parent: any,
      path: string[]
    ) => any
  ) => any
}


type Subject = (...args: any[]) => any

type TestPack = {
  client: Client,
  subject: Subject
  utility: Utility,
}


async function runner(name: string, store: any, testfile: string, provider: Provider) {

  const client = await provider.test()
  const utility = client.utility()
  const structUtils = utility.struct

  let spec = resolveSpec(name, testfile)

  let clients = await resolveClients(spec, store, provider, structUtils)

  let subject = (utility as any)[name]

  let runset = async (testspec: any, testsubject: Function) => {
    subject = testsubject || subject

    for (let entry of testspec.set) {
      try {
        let testpack = resolveTestPack(name, entry, subject, client, clients)
        let args = resolveArgs(entry, testpack)

        let res = await testpack.subject(...args)
        entry.res = res

        checkResult(entry, res, structUtils)
      }
      catch (err: any) {
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


function checkResult(entry: any, res: any, structUtils: StructUtility) {
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


// Handle errors from test execution
function handleError(entry: any, err: any, structUtils: StructUtility) {
  entry.thrown = err

  const entry_err = entry.err

  if (null != entry_err) {
    if (true === entry_err || matchval(entry_err, err.message, structUtils)) {
      if (entry.match) {
        match(
          entry.match,
          { in: entry.in, out: entry.res, ctx: entry.ctx, err },
          structUtils
        )
      }
      return
    }

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
}


function resolveArgs(entry: any, testpack: TestPack): any[] {
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
  name: string,
  entry: any,
  subject: Subject,
  client: Client,
  clients: Record<string, Client>
) {
  const pack: TestPack = {
    client,
    subject,
    utility: client.utility(),
  }

  if (entry.client) {
    pack.client = clients[entry.client]
    pack.utility = pack.client.utility()
    pack.subject = (pack.utility as any)[name]
  }

  return pack
}


function resolveSpec(name: string, testfile: string): Record<string, any> {
  const alltests =
    JSON.parse(readFileSync(join(
      __dirname, testfile), 'utf8'))

  let spec = alltests.primary?.[name] || alltests[name] || alltests
  return spec
}


async function resolveClients(
  spec: Record<string, any>,
  store: any,
  provider: Provider,
  structUtils: StructUtility
):
  Promise<Record<string, Client>> {

  const clients: Record<string, Client> = {}
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
  check: any,
  base: any,
  structUtils: StructUtility
) {
  structUtils.walk(check, (_key: any, val: any, _parent: any, path: any) => {
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
  check: any,
  base: any,
  structUtils: StructUtility
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



export {
  runner
}

