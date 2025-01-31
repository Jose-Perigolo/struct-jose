
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test, describe } from 'node:test'
import { equal, deepEqual, fail } from 'node:assert'


import {
  clone,
  escre,
  escurl,
  getpath,
  getprop,
  inject,
  isempty,
  iskey,
  islist,
  ismap,
  isnode,
  items,
  merge,
  setprop,
  stringify,
  transform,
  walk,
} from '../dist/struct'


const TESTSPEC =
  JSON.parse(readFileSync(join(__dirname, '..', '..', 'build/test/test.json'), 'utf8'))


function test_set(tests: { set: any[] }, apply: Function) {
  for (let entry of tests.set) {
    try {
      deepEqual(apply(entry.in), entry.out)
    }
    catch (err: any) {
      const entry_err = entry.err
      if (null != entry_err) {
        if (true === entry_err || (err.message.includes(entry_err))) {
          break
        }
        entry.thrown = err.message
        fail(JSON.stringify(entry))
      }
      else {
        throw err
      }
    }
  }
}

function walkpath(_key: string | undefined, val: any, _parent: any, path: string[]) {
  return 'string' === typeof val ? val + '~' + path.join('.') : val
}


describe('struct', () => {

  // minor tests
  // ===========

  test('minor-exists', () => {
    equal('function', typeof clone)
    equal('function', typeof escre)
    equal('function', typeof escurl)
    equal('function', typeof getprop)
    equal('function', typeof isempty)
    equal('function', typeof iskey)
    equal('function', typeof islist)
    equal('function', typeof ismap)
    equal('function', typeof isnode)
    equal('function', typeof items)
    equal('function', typeof setprop)
    equal('function', typeof stringify)
  })

  test('minor-clone', () => {
    test_set(clone(TESTSPEC.minor.clone), clone)
  })

  test('minor-isnode', () => {
    test_set(clone(TESTSPEC.minor.isnode), isnode)
  })

  test('minor-ismap', () => {
    test_set(clone(TESTSPEC.minor.ismap), ismap)
  })

  test('minor-islist', () => {
    test_set(clone(TESTSPEC.minor.islist), islist)
  })

  test('minor-iskey', () => {
    test_set(clone(TESTSPEC.minor.iskey), iskey)
  })

  test('minor-isempty', () => {
    test_set(clone(TESTSPEC.minor.isempty), isempty)
  })

  test('minor-escre', () => {
    test_set(clone(TESTSPEC.minor.escre), escre)
  })

  test('minor-escurl', () => {
    test_set(clone(TESTSPEC.minor.escurl), escurl)
  })

  test('minor-stringify', () => {
    test_set(clone(TESTSPEC.minor.stringify), (vin: any) =>
      null == vin.max ? stringify(vin.val) : stringify(vin.val, vin.max))
  })

  test('minor-items', () => {
    test_set(clone(TESTSPEC.minor.items), items)
  })

  test('minor-getprop', () => {
    test_set(clone(TESTSPEC.minor.getprop), (vin: any) =>
      null == vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt))
  })

  test('minor-setprop', () => {
    test_set(clone(TESTSPEC.minor.setprop), (vin: any) =>
      setprop(vin.parent, vin.key, vin.val))
  })


  // walk tests
  // ==========

  test('walk-exists', () => {
    equal('function', typeof merge)
  })

  test('walk-basic', () => {
    test_set(clone(TESTSPEC.walk.basic), (vin: any) => walk(vin, walkpath))
  })


  // merge tests
  // ===========

  test('merge-exists', () => {
    equal('function', typeof merge)
  })

  test('merge-basic', () => {
    const test = clone(TESTSPEC.merge.basic)
    deepEqual(merge(test.in), test.out)
  })

  test('merge-cases', () => {
    test_set(clone(TESTSPEC.merge.cases), merge)
  })

  test('merge-array', () => {
    test_set(clone(TESTSPEC.merge.array), merge)
  })


  // getpath tests
  // =============

  test('getpath-exists', () => {
    equal('function', typeof getpath)
  })

  test('getpath-basic', () => {
    test_set(clone(TESTSPEC.getpath.basic), (vin: any) => getpath(vin.path, vin.store))
  })

  test('getpath-current', () => {
    test_set(clone(TESTSPEC.getpath.current), (vin: any) =>
      getpath(vin.path, vin.store, vin.current))
  })

  test('getpath-state', () => {
    const state = {
      handler: (state: any, val: any, _current: any, _store: any) => {
        let out = state.step + ':' + val
        state.step++
        return out
      },
      step: 0,
      mode: ('val' as any),
      full: false,
      keyI: 0,
      keys: ['$TOP'],
      key: '$TOP',
      val: '',
      parent: {},
      path: ['$TOP'],
      nodes: [{}],
      base: '$TOP'
    }
    test_set(clone(TESTSPEC.getpath.state), (vin: any) =>
      getpath(vin.path, vin.store, vin.current, state))
  })


  // inject tests
  // ============

  test('inject-exists', () => {
    equal('function', typeof inject)
  })

  test('inject-basic', () => {
    const test = clone(TESTSPEC.inject.basic)
    deepEqual(inject(test.in.val, test.in.store), test.out)
  })

  test('inject-string', () => {
    test_set(clone(TESTSPEC.inject.string), (vin: any) =>
      inject(vin.val, vin.store, vin.current))
  })

  test('inject-deep', () => {
    test_set(clone(TESTSPEC.inject.deep), (vin: any) => inject(vin.val, vin.store))
  })


  // transform tests
  // ===============

  test('transform-exists', () => {
    equal('function', typeof transform)
  })

  test('transform-basic', () => {
    const test = clone(TESTSPEC.transform.basic)
    deepEqual(transform(test.in.data, test.in.spec, test.in.store), test.out)
  })

  test('transform-paths', () => {
    test_set(clone(TESTSPEC.transform.paths), (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-cmds', () => {
    test_set(clone(TESTSPEC.transform.cmds), (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-each', () => {
    test_set(clone(TESTSPEC.transform.each), (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-pack', () => {
    test_set(clone(TESTSPEC.transform.pack), (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })


  test('transform-modify', () => {
    test_set(clone(TESTSPEC.transform.modify), (vin: any) =>
      transform(vin.data, vin.spec, vin.store,
        (key: any, val: any, parent: any) => {
          if (null != key && null != parent && 'string' === typeof val) {
            val = parent[key] = '@' + val
          }
        }
      ))
  })

  test('transform-extra', () => {
    deepEqual(transform(
      { a: 1 },
      { x: '`a`', b: '`$COPY`', c: '`$UPPER`' },
      {
        b: 2, $UPPER: (state: any) => {
          const { path } = state
          return ('' + getprop(path, path.length - 1)).toUpperCase()
        }
      }
    ), {
      x: 1,
      b: 2,
      c: 'C'
    })
  })

})


