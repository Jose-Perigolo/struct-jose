
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=check


import { test, describe } from 'node:test'

import {
  runner,
} from './runner'


describe('client', async () => {

  const { spec, runset, subject } =
    await runner('check', {}, '../../build/test/test.json')

  test('check-basic', async () => {
    await runset(spec.basic, subject)
  })

})
