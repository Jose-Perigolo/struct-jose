
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


type RunSet = (testspec: any, testsubject: Function) => Promise<any>
type RunSetFlags = (testspec: any, flags: Record<string, boolean>, testsubject: Function)
  => Promise<any>

type RunPack = {
  spec: Record<string, any>
  runset: RunSet
  runsetflags: RunSetFlags
  subject: Subject
}

type TestPack = {
  client: Client,
  subject: Subject
  utility: Utility,
}

type Flags = Record<string, boolean>


const NULLMARK = '__NULL__'


async function runner(
  name: string,
  store: any,
  testfile: string,
  provider: Provider
): Promise<RunPack> {

  const client = await provider.test()
  const utility = client.utility()
  const structUtils = utility.struct

  let spec = resolveSpec(name, testfile)
  let clients = await resolveClients(spec, store, provider, structUtils)

  // let subject = (utility as any)[name]
  let subject = resolveSubject(name, utility)

  let runsetflags: RunSetFlags = async (
    testspec: any,
    flags: Flags,
    testsubject: Function
  ) => {
    subject = testsubject || subject
    flags = resolveFlags(flags)
    const testspecmap = fixJSON(testspec, flags)

    const testset: any[] = testspecmap.set
    for (let entry of testset) {
      try {
        entry = resolveEntry(entry, flags)

        let testpack = resolveTestPack(name, entry, subject, client, clients)
        let args = resolveArgs(entry, testpack)

        let res = await testpack.subject(...args)
        res = fixJSON(res, flags)
        entry.res = res

        checkResult(entry, res, structUtils)
      }
      catch (err: any) {
        handleError(entry, err, structUtils)
      }
    }
  }

  let runset: RunSet = async (
    testspec: any,
    testsubject: Function
  ) => runsetflags(testspec, {}, testsubject)

  let runpack: RunPack = {
    spec,
    runset,
    runsetflags,
    subject,
  }

  return runpack
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


function resolveSubject(name: string, container: any) {
  return container?.[name]
}


function resolveFlags(flags?: Flags): Flags {
  if (null == flags) {
    flags = {}
  }
  flags.null = null == flags.null ? true : !!flags.null
  return flags
}


function resolveEntry(entry: any, flags: Flags): any {
  entry.out = null == entry.out && flags.null ? NULLMARK : entry.out
  return entry
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
  const testpack: TestPack = {
    client,
    subject,
    utility: client.utility(),
  }

  if (entry.client) {
    testpack.client = clients[entry.client]
    testpack.utility = testpack.client.utility()
    testpack.subject = resolveSubject(name, testpack.utility)
  }

  return testpack
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


function fixJSON(val: any, flags: Flags): any {
  if (null == val) {
    return flags.null ? NULLMARK : val
  }

  const replacer: any = (_k: any, v: any) => null == v && flags.null ? NULLMARK : v
  return JSON.parse(JSON.stringify(val, replacer))
}


function nullModifier(
  val: any,
  key: any,
  parent: any
) {
  if ("__NULL__" === val) {
    parent[key] = null
  }
  else if ('string' === typeof val) {
    parent[key] = val.replaceAll('__NULL__', 'null')
  }
}




export {
  NULLMARK,
  nullModifier,
  runner
}

