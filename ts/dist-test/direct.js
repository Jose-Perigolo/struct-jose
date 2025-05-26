"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const __1 = require("..");
let out;
let errs;
// errs = []
// out = validate(1, '`$STRING`', undefined, errs)
// console.log('OUT-A0', out, errs)
// errs = []
// out = validate({ a: 1 }, { a: '`$STRING`' }, undefined, errs)
// console.log('OUT-A1', out, errs)
// errs = []
// out = validate(true, ['`$ONE`', '`$STRING`', '`$NUMBER`'], undefined, errs)
// console.log('OUT-B0', out, errs)
// errs = []
// out = validate(true, ['`$ONE`', '`$STRING`'], undefined, errs)
// console.log('OUT-B1', out, errs)
// errs = []
// out = validate(3, ['`$EXACT`', 4], undefined, errs)
// console.log('OUT', out, errs)
// errs = []
// out = validate({ a: 3 }, { a: ['`$EXACT`', 4] }, undefined, errs)
// console.log('OUT', out, errs)
// errs = []
// out = validate({}, { '`$EXACT`': 1 }, undefined, errs)
// console.log('OUT', out, errs)
// errs = []
// out = validate({}, { a: '`$EXACT`' }, undefined, errs)
// console.log('OUT', out, errs)
// errs = []
// out = validate({}, { a: [1, '`$EXACT`'] }, undefined, errs)
// console.log('OUT', out, errs)
// errs = []
// out = validate({}, { a: ['`$ONE`', '`$STRING`', '`$NUMBER`'] }, undefined, errs)
// console.log('OUT', out, errs)
errs = [];
out = (0, __1.validate)({
// kind: undefined
}, {
    // name: '`$STRING`',
    // kind: ['`$EXACT`', 'req', 'res'],
    // path: '`$STRING`',
    // entity: '`$STRING`',
    // reqform: ['`$ONE`', '`$STRING`', '`$OBJECT`', '`$FUNCTION`'],
    // resform: ['`$ONE`', '`$STRING`', '`$OBJECT`', '`$FUNCTION`'],
    // resform: ['`$ONE`', '`$STRING`', '`$OBJECT`'],
    // resform: ['`$ONE`', '`$STRING`'],
    resform: ['`$ONE`', '`$OBJECT`'],
    // params: ['`$CHILD`', '`$STRING`'],
    // alias: { '`$CHILD`': '`$STRING`' },
    // match: {},
    // data: ['`$ONE`', {}, []],
    // state: {},
    // check: {},
}, { errs });
console.log('OUT', out, errs);
//# sourceMappingURL=direct.js.map