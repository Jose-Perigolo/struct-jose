
const { test, describe } = require('node:test')
const { equal, deepEqual } = require('node:assert')


const {
  // transform,
  merge,
} = require('../')


const TESTSPEC = require('../../build/test/test.json')

function clone(obj) {
  return JSON.parse(JSON.stringify(obj))
}


describe('struct', ()=>{
  test('exists', ()=>{
    equal('function', typeof merge)
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

  test('merge-basic', ()=>{
    const test = clone(TESTSPEC.merge.basic)
    deepEqual(merge(test.in), test.out)
  })


  test('merge-children', ()=>{
    const test = clone(TESTSPEC.merge.children)
    deepEqual(merge(test.in), test.out)
  })

  
  test('merge-array', ()=>{
    const test = clone(TESTSPEC.merge.array)
    let i = 0
    
    for(set of test.set) {
      deepEqual(merge(set.in) || '$UNDEFINED', set.out)
    }
  })
  
})
