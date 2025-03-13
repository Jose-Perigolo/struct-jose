"use strict";
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = require("node:assert");
const struct_1 = require("../dist/struct");
const runner_1 = require("./runner");
// NOTE: tests are in order of increasing dependence.
(0, node_test_1.describe)('struct', async () => {
    const { spec, runset, runsetflags } = await (0, runner_1.runner)('struct', {}, '../../build/test/test.json', {
        test: async () => ({
            utility: () => ({
                struct: {
                    clone: struct_1.clone,
                    escre: struct_1.escre,
                    escurl: struct_1.escurl,
                    getpath: struct_1.getpath,
                    getprop: struct_1.getprop,
                    inject: struct_1.inject,
                    isempty: struct_1.isempty,
                    iskey: struct_1.iskey,
                    islist: struct_1.islist,
                    ismap: struct_1.ismap,
                    isnode: struct_1.isnode,
                    items: struct_1.items,
                    haskey: struct_1.haskey,
                    keysof: struct_1.keysof,
                    merge: struct_1.merge,
                    setprop: struct_1.setprop,
                    stringify: struct_1.stringify,
                    transform: struct_1.transform,
                    typify: struct_1.typify,
                    walk: struct_1.walk,
                    validate: struct_1.validate,
                    joinurl: struct_1.joinurl,
                }
            })
        })
    });
    const minorSpec = spec.minor;
    const walkSpec = spec.walk;
    const mergeSpec = spec.merge;
    const getpathSpec = spec.getpath;
    const injectSpec = spec.inject;
    const transformSpec = spec.transform;
    const validateSpec = spec.validate;
    // minor tests
    // ===========
    (0, node_test_1.test)('minor-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.clone);
        (0, node_assert_1.equal)('function', typeof struct_1.escre);
        (0, node_assert_1.equal)('function', typeof struct_1.escurl);
        (0, node_assert_1.equal)('function', typeof struct_1.getprop);
        (0, node_assert_1.equal)('function', typeof struct_1.haskey);
        (0, node_assert_1.equal)('function', typeof struct_1.isempty);
        (0, node_assert_1.equal)('function', typeof struct_1.isfunc);
        (0, node_assert_1.equal)('function', typeof struct_1.iskey);
        (0, node_assert_1.equal)('function', typeof struct_1.islist);
        (0, node_assert_1.equal)('function', typeof struct_1.ismap);
        (0, node_assert_1.equal)('function', typeof struct_1.isnode);
        (0, node_assert_1.equal)('function', typeof struct_1.items);
        (0, node_assert_1.equal)('function', typeof struct_1.joinurl);
        (0, node_assert_1.equal)('function', typeof struct_1.keysof);
        (0, node_assert_1.equal)('function', typeof struct_1.pathify);
        (0, node_assert_1.equal)('function', typeof struct_1.setprop);
        (0, node_assert_1.equal)('function', typeof struct_1.stringify);
        (0, node_assert_1.equal)('function', typeof struct_1.typify);
    });
    (0, node_test_1.test)('minor-isnode', async () => {
        await runset(minorSpec.isnode, struct_1.isnode);
    });
    (0, node_test_1.test)('minor-ismap', async () => {
        await runset(minorSpec.ismap, struct_1.ismap);
    });
    (0, node_test_1.test)('minor-islist', async () => {
        await runset(minorSpec.islist, struct_1.islist);
    });
    (0, node_test_1.test)('minor-iskey', async () => {
        await runsetflags(minorSpec.iskey, { null: false }, struct_1.iskey);
    });
    (0, node_test_1.test)('minor-isempty', async () => {
        await runsetflags(minorSpec.isempty, { null: false }, struct_1.isempty);
    });
    (0, node_test_1.test)('minor-isfunc', async () => {
        await runset(minorSpec.isfunc, struct_1.isfunc);
        function f0() { return null; }
        (0, node_assert_1.equal)((0, struct_1.isfunc)(f0), true);
        (0, node_assert_1.equal)((0, struct_1.isfunc)(() => null), true);
    });
    (0, node_test_1.test)('minor-clone', async () => {
        await runsetflags(minorSpec.clone, { null: false }, struct_1.clone);
        const f0 = () => null;
        (0, node_assert_1.deepEqual)({ a: f0 }, (0, struct_1.clone)({ a: f0 }));
    });
    (0, node_test_1.test)('minor-escre', async () => {
        await runset(minorSpec.escre, struct_1.escre);
    });
    (0, node_test_1.test)('minor-escurl', async () => {
        await runset(minorSpec.escurl, struct_1.escurl);
    });
    (0, node_test_1.test)('minor-stringify', async () => {
        await runset(minorSpec.stringify, (vin) => (0, struct_1.stringify)((runner_1.NULLMARK === vin.val ? "null" : vin.val), vin.max));
    });
    (0, node_test_1.test)('minor-pathify', async () => {
        await runsetflags(minorSpec.pathify, { null: true }, (vin) => {
            let path = runner_1.NULLMARK == vin.path ? undefined : vin.path;
            let pathstr = (0, struct_1.pathify)(path, vin.from).replace('__NULL__.', '');
            pathstr = runner_1.NULLMARK === vin.path ? pathstr.replace('>', ':null>') : pathstr;
            return pathstr;
        });
    });
    (0, node_test_1.test)('minor-items', async () => {
        await runset(minorSpec.items, struct_1.items);
    });
    (0, node_test_1.test)('minor-getprop', async () => {
        await runsetflags(minorSpec.getprop, { null: false }, (vin) => null == vin.alt ? (0, struct_1.getprop)(vin.val, vin.key) : (0, struct_1.getprop)(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('minor-edge-getprop', async () => {
        let strarr = ['a', 'b', 'c', 'd', 'e'];
        (0, node_assert_1.deepEqual)((0, struct_1.getprop)(strarr, 2), 'c');
        (0, node_assert_1.deepEqual)((0, struct_1.getprop)(strarr, '2'), 'c');
        let intarr = [2, 3, 5, 7, 11];
        (0, node_assert_1.deepEqual)((0, struct_1.getprop)(intarr, 2), 5);
        (0, node_assert_1.deepEqual)((0, struct_1.getprop)(intarr, '2'), 5);
    });
    (0, node_test_1.test)('minor-setprop', async () => {
        await runsetflags(minorSpec.setprop, { null: false }, (vin) => (0, struct_1.setprop)(vin.parent, vin.key, vin.val));
    });
    (0, node_test_1.test)('minor-edge-setprop', async () => {
        let strarr0 = ['a', 'b', 'c', 'd', 'e'];
        let strarr1 = ['a', 'b', 'c', 'd', 'e'];
        (0, node_assert_1.deepEqual)((0, struct_1.setprop)(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e']);
        (0, node_assert_1.deepEqual)((0, struct_1.setprop)(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e']);
        let intarr0 = [2, 3, 5, 7, 11];
        let intarr1 = [2, 3, 5, 7, 11];
        (0, node_assert_1.deepEqual)((0, struct_1.setprop)(intarr0, 2, 55), [2, 3, 55, 7, 11]);
        (0, node_assert_1.deepEqual)((0, struct_1.setprop)(intarr1, '2', 555), [2, 3, 555, 7, 11]);
    });
    (0, node_test_1.test)('minor-haskey', async () => {
        await runset(minorSpec.haskey, struct_1.haskey);
    });
    (0, node_test_1.test)('minor-keysof', async () => {
        await runset(minorSpec.keysof, struct_1.keysof);
    });
    (0, node_test_1.test)('minor-joinurl', async () => {
        await runsetflags(minorSpec.joinurl, { null: false }, struct_1.joinurl);
    });
    (0, node_test_1.test)('minor-typify', async () => {
        await runsetflags(minorSpec.typify, { null: false }, struct_1.typify);
    });
    // walk tests
    // ==========
    (0, node_test_1.test)('walk-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.walk);
    });
    (0, node_test_1.test)('walk-log', async () => {
        const test = (0, struct_1.clone)(walkSpec.log);
        const log = [];
        function walklog(key, val, parent, path) {
            log.push('k=' + (0, struct_1.stringify)(key) +
                ', v=' + (0, struct_1.stringify)(val) +
                ', p=' + (0, struct_1.stringify)(parent) +
                ', t=' + (0, struct_1.pathify)(path));
            return val;
        }
        (0, struct_1.walk)(test.in, walklog);
        (0, node_assert_1.deepEqual)(log, test.out);
    });
    (0, node_test_1.test)('walk-basic', async () => {
        function walkpath(_key, val, _parent, path) {
            return 'string' === typeof val ? val + '~' + path.join('.') : val;
        }
        await runset(walkSpec.basic, (vin) => (0, struct_1.walk)(vin, walkpath));
    });
    // merge tests
    // ===========
    (0, node_test_1.test)('merge-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('merge-basic', async () => {
        const test = (0, struct_1.clone)(mergeSpec.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-cases', async () => {
        await runset(mergeSpec.cases, struct_1.merge);
    });
    (0, node_test_1.test)('merge-array', async () => {
        await runset(mergeSpec.array, struct_1.merge);
    });
    (0, node_test_1.test)('merge-special', async () => {
        const f0 = () => null;
        (0, node_assert_1.deepEqual)((0, struct_1.merge)([f0]), f0);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)([null, f0]), f0);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)([{ a: f0 }]), { a: f0 });
        (0, node_assert_1.deepEqual)((0, struct_1.merge)([{ a: { b: f0 } }]), { a: { b: f0 } });
        // JavaScript only
        (0, node_assert_1.deepEqual)((0, struct_1.merge)([{ a: global.fetch }]), { a: global.fetch });
        (0, node_assert_1.deepEqual)((0, struct_1.merge)([{ a: { b: global.fetch } }]), { a: { b: global.fetch } });
    });
    // getpath tests
    // =============
    (0, node_test_1.test)('getpath-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.getpath);
    });
    (0, node_test_1.test)('getpath-basic', async () => {
        await runset(getpathSpec.basic, (vin) => (0, struct_1.getpath)(vin.path, vin.store));
    });
    (0, node_test_1.test)('getpath-current', async () => {
        await runset(getpathSpec.current, (vin) => (0, struct_1.getpath)(vin.path, vin.store, vin.current));
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
        await runset(getpathSpec.state, (vin) => (0, struct_1.getpath)(vin.path, vin.store, vin.current, state));
    });
    // inject tests
    // ============
    (0, node_test_1.test)('inject-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.inject);
    });
    (0, node_test_1.test)('inject-basic', async () => {
        const test = (0, struct_1.clone)(injectSpec.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.inject)(test.in.val, test.in.store), test.out);
    });
    (0, node_test_1.test)('inject-string', async () => {
        await runset(injectSpec.string, (vin) => (0, struct_1.inject)(vin.val, vin.store, runner_1.nullModifier, vin.current));
    });
    (0, node_test_1.test)('inject-deep', async () => {
        await runset(injectSpec.deep, (vin) => (0, struct_1.inject)(vin.val, vin.store));
    });
    // transform tests
    // ===============
    (0, node_test_1.test)('transform-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.transform);
    });
    (0, node_test_1.test)('transform-basic', async () => {
        const test = (0, struct_1.clone)(transformSpec.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.transform)(test.in.data, test.in.spec, test.in.store), test.out);
    });
    (0, node_test_1.test)('transform-paths', async () => {
        await runset(transformSpec.paths, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-cmds', async () => {
        await runset(transformSpec.cmds, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-each', async () => {
        await runset(transformSpec.each, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-pack', async () => {
        await runset(transformSpec.pack, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-modify', async () => {
        await runset(transformSpec.modify, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store, (val, key, parent) => {
            if (null != key && null != parent && 'string' === typeof val) {
                val = parent[key] = '@' + val;
            }
        }));
    });
    (0, node_test_1.test)('transform-extra', async () => {
        (0, node_assert_1.deepEqual)((0, struct_1.transform)({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' }, {
            b: 2, $UPPER: (state) => {
                const { path } = state;
                return ('' + (0, struct_1.getprop)(path, path.length - 1)).toUpperCase();
            }
        }), {
            x: 1,
            b: 2,
            c: 'C'
        });
    });
    (0, node_test_1.test)('transform-funcval', async () => {
        const f0 = () => 99;
        (0, node_assert_1.deepEqual)((0, struct_1.transform)({}, { x: 1 }), { x: 1 });
        (0, node_assert_1.deepEqual)((0, struct_1.transform)({}, { x: f0 }), { x: f0 });
        (0, node_assert_1.deepEqual)((0, struct_1.transform)({ a: 1 }, { x: '`a`' }), { x: 1 });
        (0, node_assert_1.deepEqual)((0, struct_1.transform)({ f0 }, { x: '`f0`' }), { x: f0 });
    });
    // validate tests
    // ===============
    (0, node_test_1.test)('validate-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.validate);
    });
    (0, node_test_1.test)('validate-basic', async () => {
        await runset(validateSpec.basic, (vin) => (0, struct_1.validate)(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-node', async () => {
        await runset(validateSpec.node, (vin) => (0, struct_1.validate)(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-custom', async () => {
        const errs = [];
        const extra = {
            $INTEGER: (state, _val, current) => {
                const { key } = state;
                let out = (0, struct_1.getprop)(current, key);
                let t = typeof out;
                if ('number' !== t && !Number.isInteger(out)) {
                    state.errs.push('Not an integer at ' + state.path.slice(1).join('.') + ': ' + out);
                    return;
                }
                return out;
            },
        };
        const shape = { a: '`$INTEGER`' };
        let out = (0, struct_1.validate)({ a: 1 }, shape, extra, errs);
        (0, node_assert_1.deepEqual)(out, { a: 1 });
        (0, node_assert_1.equal)(errs.length, 0);
        out = (0, struct_1.validate)({ a: 'A' }, shape, extra, errs);
        (0, node_assert_1.deepEqual)(out, { a: 'A' });
        (0, node_assert_1.deepEqual)(errs, ['Not an integer at a: A']);
    });
});
//# sourceMappingURL=struct.test.js.map