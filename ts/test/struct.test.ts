
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test, describe } from 'node:test'
import { equal, deepEqual } from 'node:assert'


import {
  walk,
  merge,
  getpath,
  inject,
  transform,
} from '../dist/struct'


const TESTSPEC =
  JSON.parse(readFileSync(join(__dirname, '..', '..', 'build/test/test.json'), 'utf8'))

function clone(obj: any): any {
  return JSON.parse(JSON.stringify(obj))
}


function test_set(tests: { set: any[] }, apply: Function) {
  for (let entry of tests.set) {
    deepEqual(apply(entry.in), entry.out)
  }
}


describe('struct', () => {

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



  // test('transform', async ()=>{
  //   // deepEqual(transform({a:1},{a:'`a`'}), {a:1})

  //   const src = {
  //     a: 1,
  //     c: {x:'X',y:'Y'},
  //     d: 'D',
  //     e: 2,
  //     f: {m:'M',n:'N'},
  //     ff: {m:'MM',l:'LL'},
  //     x: {x0:{y:0}, x1:{y:1}},
  //     y:[{k:'x0',x:0},{k:'x1',x:1}]
  //   }

  //   const pat = {
  //     a:'`$COPY`',
  //     aa:'`a`',
  //     b: 'B',
  //     q: '<`a``d`>',
  //     '`d`': '`c`',
  //     e: '`$DELETE`',
  //     o:{p:'`$KEY`'},
  //     '`$MERGE`': ['`f`','`ff`'],
  //     g: { '`$MERGE`': '`f`' },
  //     '`$EACH`x': {z:'Z', y:'`$COPY`',k:'`$KEY`'},
  //     '`$PACK`y': {z:'Z', x:'`$COPY`','`$KEY`':'k',i:'`$KEY`',ii:'`.k`'},
  //   }

  //   console.log('src',src)
  //   console.log('pat',pat)
  //   console.log('out',transform(src,pat))
  //   // console.log('src',src)
  // })


  /*
 
 
 
    */


})


function walkpath(_key: string | undefined, val: any, _parent: any, path: string[]) {
  return 'string' === typeof val ? val + '~' + path.join('.') : val
}
