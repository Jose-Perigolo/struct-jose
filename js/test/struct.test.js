const { test, describe } = require('node:test')
const { equal, deepEqual } = require('node:assert')


const {
  // transform,
  merge,
} = require('../')




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
    deepEqual(merge([
      {a:1,b:2},
      {b:3,d:4},
    ]),{
      a: 1, b: 3, d: 4
    })
  })

  test('merge-children', ()=>{
    deepEqual(merge([
      {a:1,b:2},
      {b:3,d:{e:4,ee:5},f:6},
      {x:{y:{z:7,zz:8}},q:{u:9,uu:10},v:11},
    ]),{
      a: 1,
      b: 3,
      d: { e: 4, ee: 5 },
      f: 6,
      x: { y: { z: 7, zz: 8 } },
      q: { u: 9, uu: 10 },
      v: 11
    })
  })

  
  test('merge-array', ()=>{
    deepEqual(merge([
    ]), undefined)

    deepEqual(merge([
      [1],
    ]), [ 1 ])

    deepEqual(merge([
      [1],
      [11],
    ]), [ 11 ])

    deepEqual(merge([
      {},
      {a:[1]},
    ]), { a: [ 1 ] })

    deepEqual(merge([
      {},
      {a:[{b:1}], c:[{d:[2]}]},
    ]), { a: [ { b: 1 } ], c: [ { d: [2] } ] })

    deepEqual(merge([
      {a:[1,2], b:{c:3,d:4}},
      {a:[11],  b:{c:33}},
    ]), { a: [ 11, 2 ], b: { c: 33, d: 4 } })
  })
  
})
