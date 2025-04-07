
import {
  validate
} from '..'


let out: any
let errs: any

errs = []
out = validate(1, '`$STRING`', undefined, errs)
console.log('OUT-A0', out, errs)

errs = []
out = validate({ a: 1 }, { a: '`$STRING`' }, undefined, errs)
console.log('OUT-A1', out, errs)


errs = []
out = validate(true, ['`$ONE`', '`$STRING`', '`$NUMBER`'], undefined, errs)
console.log('OUT-B0', out, errs)

errs = []
out = validate(true, ['`$ONE`', '`$STRING`'], undefined, errs)
console.log('OUT-B1', out, errs)


errs = []
out = validate(3, ['`$EXACT`', 4], undefined, errs)
console.log('OUT', out, errs)

errs = []
out = validate({ a: 3 }, { a: ['`$EXACT`', 4] }, undefined, errs)
console.log('OUT', out, errs)

errs = []
out = validate({}, { '`$EXACT`': 1 }, undefined, errs)
console.log('OUT', out, errs)

errs = []
out = validate({}, { a: '`$EXACT`' }, undefined, errs)
console.log('OUT', out, errs)

errs = []
out = validate({}, { a: [1, '`$EXACT`'] }, undefined, errs)
console.log('OUT', out, errs)

