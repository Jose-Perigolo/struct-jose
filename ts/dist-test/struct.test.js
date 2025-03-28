"use strict";
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = require("node:assert");
const runner_1 = require("./runner");
const sdk_js_1 = require("./sdk.js");
const TEST_JSON_FILE = '../../build/test/test.json';
// NOTE: tests are in order of increasing dependence.
(0, node_test_1.describe)('struct', async () => {
    const runner = await (0, runner_1.makeRunner)(TEST_JSON_FILE, await sdk_js_1.SDK.test());
    const { spec, runset, runsetflags, client } = await runner('struct');
    const { clone, escre, escurl, getpath, getprop, haskey, inject, isempty, isfunc, iskey, islist, ismap, isnode, items, joinurl, keysof, merge, pathify, setprop, strkey, stringify, transform, typify, validate, walk, } = client.utility().struct;
    const minorSpec = spec.minor;
    const walkSpec = spec.walk;
    const mergeSpec = spec.merge;
    const getpathSpec = spec.getpath;
    const injectSpec = spec.inject;
    const transformSpec = spec.transform;
    const validateSpec = spec.validate;
    (0, node_test_1.test)('exists', () => {
        (0, node_assert_1.equal)('function', typeof clone);
        (0, node_assert_1.equal)('function', typeof escre);
        (0, node_assert_1.equal)('function', typeof escurl);
        (0, node_assert_1.equal)('function', typeof getprop);
        (0, node_assert_1.equal)('function', typeof getpath);
        (0, node_assert_1.equal)('function', typeof haskey);
        (0, node_assert_1.equal)('function', typeof inject);
        (0, node_assert_1.equal)('function', typeof isempty);
        (0, node_assert_1.equal)('function', typeof isfunc);
        (0, node_assert_1.equal)('function', typeof iskey);
        (0, node_assert_1.equal)('function', typeof islist);
        (0, node_assert_1.equal)('function', typeof ismap);
        (0, node_assert_1.equal)('function', typeof isnode);
        (0, node_assert_1.equal)('function', typeof items);
        (0, node_assert_1.equal)('function', typeof joinurl);
        (0, node_assert_1.equal)('function', typeof keysof);
        (0, node_assert_1.equal)('function', typeof merge);
        (0, node_assert_1.equal)('function', typeof pathify);
        (0, node_assert_1.equal)('function', typeof setprop);
        (0, node_assert_1.equal)('function', typeof strkey);
        (0, node_assert_1.equal)('function', typeof stringify);
        (0, node_assert_1.equal)('function', typeof transform);
        (0, node_assert_1.equal)('function', typeof typify);
        (0, node_assert_1.equal)('function', typeof validate);
        (0, node_assert_1.equal)('function', typeof walk);
    });
    // minor tests
    // ===========
    (0, node_test_1.test)('minor-isnode', async () => {
        await runset(minorSpec.isnode, isnode);
    });
    (0, node_test_1.test)('minor-ismap', async () => {
        await runset(minorSpec.ismap, ismap);
    });
    (0, node_test_1.test)('minor-islist', async () => {
        await runset(minorSpec.islist, islist);
    });
    (0, node_test_1.test)('minor-iskey', async () => {
        await runsetflags(minorSpec.iskey, { null: false }, iskey);
    });
    (0, node_test_1.test)('minor-strkey', async () => {
        await runsetflags(minorSpec.strkey, { null: false }, strkey);
    });
    (0, node_test_1.test)('minor-isempty', async () => {
        await runsetflags(minorSpec.isempty, { null: false }, isempty);
    });
    (0, node_test_1.test)('minor-isfunc', async () => {
        await runset(minorSpec.isfunc, isfunc);
        function f0() { return null; }
        (0, node_assert_1.equal)(isfunc(f0), true);
        (0, node_assert_1.equal)(isfunc(() => null), true);
    });
    (0, node_test_1.test)('minor-clone', async () => {
        await runsetflags(minorSpec.clone, { null: false }, clone);
        const f0 = () => null;
        (0, node_assert_1.deepEqual)({ a: f0 }, clone({ a: f0 }));
    });
    (0, node_test_1.test)('minor-escre', async () => {
        await runset(minorSpec.escre, escre);
    });
    (0, node_test_1.test)('minor-escurl', async () => {
        await runset(minorSpec.escurl, escurl);
    });
    (0, node_test_1.test)('minor-stringify', async () => {
        await runset(minorSpec.stringify, (vin) => stringify((runner_1.NULLMARK === vin.val ? "null" : vin.val), vin.max));
    });
    (0, node_test_1.test)('minor-pathify', async () => {
        await runsetflags(minorSpec.pathify, { null: true }, (vin) => {
            let path = runner_1.NULLMARK == vin.path ? undefined : vin.path;
            let pathstr = pathify(path, vin.from).replace('__NULL__.', '');
            pathstr = runner_1.NULLMARK === vin.path ? pathstr.replace('>', ':null>') : pathstr;
            return pathstr;
        });
    });
    (0, node_test_1.test)('minor-items', async () => {
        await runset(minorSpec.items, items);
    });
    (0, node_test_1.test)('minor-getprop', async () => {
        await runsetflags(minorSpec.getprop, { null: false }, (vin) => null == vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('minor-edge-getprop', async () => {
        let strarr = ['a', 'b', 'c', 'd', 'e'];
        (0, node_assert_1.deepEqual)(getprop(strarr, 2), 'c');
        (0, node_assert_1.deepEqual)(getprop(strarr, '2'), 'c');
        let intarr = [2, 3, 5, 7, 11];
        (0, node_assert_1.deepEqual)(getprop(intarr, 2), 5);
        (0, node_assert_1.deepEqual)(getprop(intarr, '2'), 5);
    });
    (0, node_test_1.test)('minor-setprop', async () => {
        await runsetflags(minorSpec.setprop, { null: false }, (vin) => setprop(vin.parent, vin.key, vin.val));
    });
    (0, node_test_1.test)('minor-edge-setprop', async () => {
        let strarr0 = ['a', 'b', 'c', 'd', 'e'];
        let strarr1 = ['a', 'b', 'c', 'd', 'e'];
        (0, node_assert_1.deepEqual)(setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e']);
        (0, node_assert_1.deepEqual)(setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e']);
        let intarr0 = [2, 3, 5, 7, 11];
        let intarr1 = [2, 3, 5, 7, 11];
        (0, node_assert_1.deepEqual)(setprop(intarr0, 2, 55), [2, 3, 55, 7, 11]);
        (0, node_assert_1.deepEqual)(setprop(intarr1, '2', 555), [2, 3, 555, 7, 11]);
    });
    (0, node_test_1.test)('minor-haskey', async () => {
        await runset(minorSpec.haskey, haskey);
    });
    (0, node_test_1.test)('minor-keysof', async () => {
        await runset(minorSpec.keysof, keysof);
    });
    (0, node_test_1.test)('minor-joinurl', async () => {
        await runsetflags(minorSpec.joinurl, { null: false }, joinurl);
    });
    (0, node_test_1.test)('minor-typify', async () => {
        await runsetflags(minorSpec.typify, { null: false }, typify);
    });
    // walk tests
    // ==========
    (0, node_test_1.test)('walk-log', async () => {
        const test = clone(walkSpec.log);
        const log = [];
        function walklog(key, val, parent, path) {
            log.push('k=' + stringify(key) +
                ', v=' + stringify(val) +
                ', p=' + stringify(parent) +
                ', t=' + pathify(path));
            return val;
        }
        walk(test.in, walklog);
        (0, node_assert_1.deepEqual)(log, test.out);
    });
    (0, node_test_1.test)('walk-basic', async () => {
        function walkpath(_key, val, _parent, path) {
            return 'string' === typeof val ? val + '~' + path.join('.') : val;
        }
        await runset(walkSpec.basic, (vin) => walk(vin, walkpath));
    });
    // merge tests
    // ===========
    (0, node_test_1.test)('merge-basic', async () => {
        const test = clone(mergeSpec.basic);
        (0, node_assert_1.deepEqual)(merge(test.in), test.out);
    });
    (0, node_test_1.test)('merge-cases', async () => {
        await runset(mergeSpec.cases, merge);
    });
    (0, node_test_1.test)('merge-array', async () => {
        await runset(mergeSpec.array, merge);
    });
    (0, node_test_1.test)('merge-special', async () => {
        const f0 = () => null;
        (0, node_assert_1.deepEqual)(merge([f0]), f0);
        (0, node_assert_1.deepEqual)(merge([null, f0]), f0);
        (0, node_assert_1.deepEqual)(merge([{ a: f0 }]), { a: f0 });
        (0, node_assert_1.deepEqual)(merge([{ a: { b: f0 } }]), { a: { b: f0 } });
        // JavaScript only
        (0, node_assert_1.deepEqual)(merge([{ a: global.fetch }]), { a: global.fetch });
        (0, node_assert_1.deepEqual)(merge([{ a: { b: global.fetch } }]), { a: { b: global.fetch } });
    });
    // getpath tests
    // =============
    (0, node_test_1.test)('getpath-basic', async () => {
        await runset(getpathSpec.basic, (vin) => getpath(vin.path, vin.store));
    });
    (0, node_test_1.test)('getpath-current', async () => {
        await runset(getpathSpec.current, (vin) => getpath(vin.path, vin.store, vin.current));
    });
    (0, node_test_1.test)('getpath-state', async () => {
        const state = {
            handler: (state, val, _current, _ref, _store) => {
                let out = state.meta.step + ':' + val;
                state.meta.step++;
                return out;
            },
            meta: { step: 0 },
            mode: 'val',
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
        };
        await runset(getpathSpec.state, (vin) => getpath(vin.path, vin.store, vin.current, state));
    });
    // inject tests
    // ============
    (0, node_test_1.test)('inject-basic', async () => {
        const test = clone(injectSpec.basic);
        (0, node_assert_1.deepEqual)(inject(test.in.val, test.in.store), test.out);
    });
    (0, node_test_1.test)('inject-string', async () => {
        await runset(injectSpec.string, (vin) => inject(vin.val, vin.store, runner_1.nullModifier, vin.current));
    });
    (0, node_test_1.test)('inject-deep', async () => {
        await runset(injectSpec.deep, (vin) => inject(vin.val, vin.store));
    });
    // transform tests
    // ===============
    (0, node_test_1.test)('transform-basic', async () => {
        const test = clone(transformSpec.basic);
        (0, node_assert_1.deepEqual)(transform(test.in.data, test.in.spec, test.in.store), test.out);
    });
    (0, node_test_1.test)('transform-paths', async () => {
        await runset(transformSpec.paths, (vin) => transform(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-cmds', async () => {
        await runset(transformSpec.cmds, (vin) => transform(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-each', async () => {
        await runset(transformSpec.each, (vin) => transform(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-pack', async () => {
        await runset(transformSpec.pack, (vin) => transform(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-modify', async () => {
        await runset(transformSpec.modify, (vin) => transform(vin.data, vin.spec, vin.store, (val, key, parent) => {
            if (null != key && null != parent && 'string' === typeof val) {
                val = parent[key] = '@' + val;
            }
        }));
    });
    (0, node_test_1.test)('transform-extra', async () => {
        (0, node_assert_1.deepEqual)(transform({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' }, {
            b: 2, $UPPER: (state) => {
                const { path } = state;
                return ('' + getprop(path, path.length - 1)).toUpperCase();
            }
        }), {
            x: 1,
            b: 2,
            c: 'C'
        });
    });
    (0, node_test_1.test)('transform-funcval', async () => {
        const f0 = () => 99;
        (0, node_assert_1.deepEqual)(transform({}, { x: 1 }), { x: 1 });
        (0, node_assert_1.deepEqual)(transform({}, { x: f0 }), { x: f0 });
        (0, node_assert_1.deepEqual)(transform({ a: 1 }, { x: '`a`' }), { x: 1 });
        (0, node_assert_1.deepEqual)(transform({ f0 }, { x: '`f0`' }), { x: f0 });
    });
    // validate tests
    // ===============
    (0, node_test_1.test)('validate-basic', async () => {
        await runset(validateSpec.basic, (vin) => validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-node', async () => {
        await runset(validateSpec.node, (vin) => validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-custom', async () => {
        const errs = [];
        const extra = {
            $INTEGER: (state, _val, current) => {
                const { key } = state;
                let out = getprop(current, key);
                let t = typeof out;
                if ('number' !== t && !Number.isInteger(out)) {
                    state.errs.push('Not an integer at ' + state.path.slice(1).join('.') + ': ' + out);
                    return;
                }
                return out;
            },
        };
        const shape = { a: '`$INTEGER`' };
        let out = validate({ a: 1 }, shape, extra, errs);
        (0, node_assert_1.deepEqual)(out, { a: 1 });
        (0, node_assert_1.equal)(errs.length, 0);
        out = validate({ a: 'A' }, shape, extra, errs);
        (0, node_assert_1.deepEqual)(out, { a: 'A' });
        (0, node_assert_1.deepEqual)(errs, ['Not an integer at a: A']);
    });
});
(0, node_test_1.describe)('client', async () => {
    const runner = await (0, runner_1.makeRunner)(TEST_JSON_FILE, await sdk_js_1.SDK.test());
    const { spec, runset, subject } = await runner('check');
    (0, node_test_1.test)('client-check-basic', async () => {
        await runset(spec.basic, subject);
    });
});
//# sourceMappingURL=struct.test.js.map