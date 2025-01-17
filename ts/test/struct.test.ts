
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test, describe } from 'node:test'
import { equal, deepEqual } from 'node:assert'


import {
  clone,
  getpath,
  inject,
  merge,
  transform,
  walk,
} from '../dist/struct'


const TESTSPEC =
  JSON.parse(readFileSync(join(__dirname, '..', '..', 'build/test/test.json'), 'utf8'))

// function clone(obj: any): any {
//   return JSON.parse(JSON.stringify(obj))
// }


function test_set(tests: { set: any[] }, apply: Function) {
  for (let entry of tests.set) {
    deepEqual(apply(entry.in), entry.out)
  }
}


describe('struct', () => {

  test('clone-exists', () => {
    equal('function', typeof clone)
  })

  test('clone-basic', () => {
    const test = clone(TESTSPEC.clone.basic)
    deepEqual(clone(test.in), test.out)
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


  test('inject-exists', () => {
    equal('function', typeof inject)
  })

  test('inject-basic', () => {
    const test = clone(TESTSPEC.inject.basic)
    deepEqual(inject(test.in.val, test.in.store), test.out)
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
