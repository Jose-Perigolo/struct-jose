
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test, describe } from 'node:test'
import { equal, deepEqual, fail } from 'node:assert'


import {
  clone,
  isnode,
  ismap,
  islist,
  iskey,
  items,
  getprop,
  setprop,

  getpath,
  inject,
  merge,
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
      if (null != entry.err) {
        if (true === entry.err || (err.message.includes(entry.err))) {
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


describe('struct', () => {

  test('minor-exists', () => {
    equal('function', typeof clone)
    equal('function', typeof isnode)
    equal('function', typeof ismap)
    equal('function', typeof islist)
    equal('function', typeof iskey)
    equal('function', typeof items)
    equal('function', typeof getprop)
    equal('function', typeof setprop)
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



  test('merge-exists', () => {
    equal('function', typeof merge)
  })

  test('merge-basic', () => {
    const test = clone(TESTSPEC.merge.basic)
    deepEqual(merge(test.in), test.out)
  })

  test('merge-children', () => {
    const test = clone(TESTSPEC.merge.children)
    deepEqual(merge(test.in), test.out)
  })

  test('merge-array', () => {
    test_set(clone(TESTSPEC.merge.array), merge)
  })


  test('walk-exists', () => {
    equal('function', typeof merge)
  })

  test('walk-basic', () => {
    test_set(clone(TESTSPEC.walk.basic), (vin: any) => walk(vin, walkpath))
  })


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
      handler: (val: any, parts: string[], _store: any, _current: any, state: any) => {
        state.last = state.step + ':' + parts.join('.') + ':' + val
        state.step++
        return state.last
      },
      step: 0,
      last: undefined
    }
    test_set(clone(TESTSPEC.getpath.state), (vin: any) =>
      getpath(vin.path, vin.store, vin.current, state))
  })



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
        (key: any, _val: any, newval: any, parent: any) => {
          if (null != key && null != parent && 'string' === typeof newval) {
            parent[key] = '@' + newval
          }
        }
      ))
  })

})


function walkpath(_key: string | undefined, val: any, _parent: any, path: string[]) {
  return 'string' === typeof val ? val + '~' + path.join('.') : val
}
