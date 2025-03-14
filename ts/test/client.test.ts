
// RUN: npm test


import { test, describe } from 'node:test'
import { equal, deepEqual } from 'node:assert'

import {
  runner,
  NULLMARK,
} from './runner'


describe('client', async () => {

  const { spec, runset, subject } =
    await runner('check', {}, '../../build/test/test.json', {
      test: async (opts: any) => ({
        utility: () => ({
          check: (_arg: string): any => {
            return { zed: 'ZED' + (null == opts ? '' : null == opts.foo ? '0' : opts.foo) }
          }
        })
      })
    })

  // console.log('CHECK', spec, runset, subject)

  test('check', async () => {
    await runset(spec.basic, subject)
  })

})

