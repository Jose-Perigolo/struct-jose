
import { test, describe } from 'node:test'
import { equal, deepEqual } from 'node:assert'

import {
  clone,
  escre,
  escurl,
  getpath,
  getprop,
  haskey,
  inject,
  isempty,
  isfunc,
  iskey,
  islist,
  ismap,
  isnode,
  items,
  joinurl,
  keysof,
  merge,
  setprop,
  stringify,
  transform,
  validate,
  walk,
} from '../dist/struct'

import type {
  InjectState
} from '../dist/struct'

import { runner } from './runner'


function walkpath(_key: any, val: any, _parent: any, path: any) {
  return 'string' === typeof val ? val + '~' + path.join('.') : val
}


function nullModifier(
  key: any,
  val: any,
  parent: any
) {
  if ("__NULL__" === val) {
    setprop(parent, key, null)
  }
  else if ('string' === typeof val) {
    setprop(parent, key, val.replaceAll('__NULL__', 'null'))
  }
}


describe('struct', async () => {

  const { spec, runset } =
    await runner('struct', {}, '../../build/test/test.json', {
      test: () => ({
        utility: () => ({
          struct: {
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
            haskey,
            keysof,
            merge,
            setprop,
            stringify,
            transform,
            walk,
            validate,
            joinurl,
          }
        })
      })
    })


  // minor tests
  // ===========

  test('minor-exists', () => {
    equal('function', typeof clone)
    equal('function', typeof escre)
    equal('function', typeof escurl)
    equal('function', typeof getprop)
    equal('function', typeof haskey)
    equal('function', typeof isempty)
    equal('function', typeof isfunc)
    equal('function', typeof iskey)
    equal('function', typeof islist)
    equal('function', typeof ismap)
    equal('function', typeof isnode)
    equal('function', typeof items)
    equal('function', typeof joinurl)
    equal('function', typeof keysof)
    equal('function', typeof setprop)
    equal('function', typeof stringify)
  })

  test('minor-isnode', async () => {
    await runset(spec.minor.isnode, isnode)
  })

  test('minor-ismap', async () => {
    await runset(spec.minor.ismap, ismap)
  })

  test('minor-islist', async () => {
    await runset(spec.minor.islist, islist)
  })

  test('minor-iskey', async () => {
    await runset(spec.minor.iskey, iskey)
  })

  test('minor-isempty', async () => {
    await runset(spec.minor.isempty, isempty)
  })

  test('minor-isfunc', async () => {
    await runset(spec.minor.isfunc, isfunc)
    function f0() { return null }
    equal(isfunc(f0), true)
    equal(isfunc(() => null), true)
  })

  test('minor-clone', async () => {
    await runset(spec.minor.clone, clone)
    const f0 = () => null
    deepEqual({ a: f0 }, clone({ a: f0 }))
  })

  test('minor-escre', async () => {
    await runset(spec.minor.escre, escre)
  })

  test('minor-escurl', async () => {
    await runset(spec.minor.escurl, escurl)
  })

  test('minor-stringify', async () => {
    await runset(spec.minor.stringify, (vin: any) =>
      null == vin.max ? stringify(vin.val) : stringify(vin.val, vin.max))
  })

  test('minor-items', async () => {
    await runset(spec.minor.items, items)
  })

  test('minor-getprop', async () => {
    await runset(spec.minor.getprop, (vin: any) =>
      null == vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt))
  })

  test('minor-setprop', async () => {
    await runset(spec.minor.setprop, (vin: any) =>
      setprop(vin.parent, vin.key, vin.val))
  })

  test('minor-haskey', async () => {
    await runset(spec.minor.haskey, haskey)
  })

  test('minor-keysof', async () => {
    await runset(spec.minor.keysof, keysof)
  })

  test('minor-joinurl', async () => {
    await runset(spec.minor.joinurl, joinurl)
  })



  // walk tests
  // ==========

  test('walk-exists', async () => {
    equal('function', typeof walk)
  })

  test('walk-basic', async () => {
    await runset(spec.walk.basic, (vin: any) => walk(vin, walkpath))
  })


  // merge tests
  // ===========

  test('merge-exists', async () => {
    equal('function', typeof merge)
  })

  test('merge-basic', async () => {
    const test = clone(spec.merge.basic)
    deepEqual(merge(test.in), test.out)
  })

  test('merge-cases', async () => {
    await runset(spec.merge.cases, merge)
  })

  test('merge-array', async () => {
    await runset(spec.merge.array, merge)
  })

  test('merge-special', async () => {
    const f0 = () => null
    deepEqual(merge([f0]), f0)
    deepEqual(merge([null, f0]), f0)
    deepEqual(merge([{ a: f0 }]), { a: f0 })
    deepEqual(merge([{ a: { b: f0 } }]), { a: { b: f0 } })

    // JavaScript only
    deepEqual(merge([{ a: global.fetch }]), { a: global.fetch })
    deepEqual(merge([{ a: { b: global.fetch } }]), { a: { b: global.fetch } })
  })


  // getpath tests
  // =============

  test('getpath-exists', async () => {
    equal('function', typeof getpath)
  })

  test('getpath-basic', async () => {
    await runset(spec.getpath.basic, (vin: any) => getpath(vin.path, vin.store))
  })

  test('getpath-current', async () => {
    await runset(spec.getpath.current, (vin: any) =>
      getpath(vin.path, vin.store, vin.current))
  })

  test('getpath-state', async () => {
    const state: InjectState = {
      handler: (state: any, val: any, _current: any, _ref: any, _store: any) => {
        let out = state.meta.step + ':' + val
        state.meta.step++
        return out
      },
      meta: { step: 0 },
      mode: ('val' as any),
      full: false,
      keyI: 0,
      keys: ['$TOP'],
      key: '$TOP',
      val: '',
      parent: {},
      path: ['$TOP'],
      nodes: [{}],
      base: '$TOP',
      errs: [],
    }
    await runset(spec.getpath.state, (vin: any) =>
      getpath(vin.path, vin.store, vin.current, state))
  })


  // inject tests
  // ============

  test('inject-exists', async () => {
    equal('function', typeof inject)
  })

  test('inject-basic', async () => {
    const test = clone(spec.inject.basic)
    deepEqual(inject(test.in.val, test.in.store), test.out)
  })

  test('inject-string', async () => {
    await runset(spec.inject.string, (vin: any) =>
      inject(vin.val, vin.store, nullModifier, vin.current))
  })

  test('inject-deep', async () => {
    await runset(spec.inject.deep, (vin: any) => inject(vin.val, vin.store))
  })


  // transform tests
  // ===============

  test('transform-exists', async () => {
    equal('function', typeof transform)
  })

  test('transform-basic', async () => {
    const test = clone(spec.transform.basic)
    deepEqual(transform(test.in.data, test.in.spec, test.in.store), test.out)
  })

  test('transform-paths', async () => {
    await runset(spec.transform.paths, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-cmds', async () => {
    await runset(spec.transform.cmds, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-each', async () => {
    await runset(spec.transform.each, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-pack', async () => {
    await runset(spec.transform.pack, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })

  test('transform-modify', async () => {
    await runset(spec.transform.modify, (vin: any) =>
      transform(vin.data, vin.spec, vin.store,
        (val, key, parent) => {
          if (null != key && null != parent && 'string' === typeof val) {
            val = parent[key] = '@' + val
          }
        }
      ))
  })

  test('transform-extra', async () => {
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

  test('transform-funcval', async () => {
    const f0 = () => 99
    deepEqual(transform({}, { x: 1 }), { x: 1 })
    deepEqual(transform({}, { x: f0 }), { x: f0 })
    deepEqual(transform({ a: 1 }, { x: '`a`' }), { x: 1 })
    deepEqual(transform({ f0 }, { x: '`f0`' }), { x: f0 })
  })


  // validate tests
  // ===============

  test('validate-exists', async () => {
    equal('function', typeof validate)
  })


  test('validate-basic', async () => {
    await runset(spec.validate.basic, (vin: any) => validate(vin.data, vin.spec))
  })


  test('validate-node', async () => {
    await runset(spec.validate.node, (vin: any) => validate(vin.data, vin.spec))
  })


  test('validate-custom', async () => {
    const errs: any[] = []
    const extra = {
      $INTEGER: (state: any, _val: any, current: any) => {
        const { key } = state
        let out = getprop(current, key)

        let t = typeof out
        if ('number' !== t && !Number.isInteger(out)) {
          state.errs.push('Not an integer at ' + state.path.slice(1).join('.') + ': ' + out)
          return
        }

        return out
      },
    }

    validate({ a: 1 }, { a: '`$INTEGER`' }, extra, errs)
    equal(errs.length, 0)

    validate({ a: 'A' }, { a: '`$INTEGER`' }, extra, errs)
    deepEqual(errs, ['Not an integer at a: A'])
  })

})

