"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = require("node:assert");
const struct_1 = require("../dist/struct");
const runner_1 = require("./runner");
function walkpath(_key, val, _parent, path) {
    return 'string' === typeof val ? val + '~' + path.join('.') : val;
}
function nullModifier(key, val, parent) {
    if ("__NULL__" === val) {
        (0, struct_1.setprop)(parent, key, null);
    }
    else if ('string' === typeof val) {
        (0, struct_1.setprop)(parent, key, val.replaceAll('__NULL__', 'null'));
    }
}
(0, node_test_1.describe)('struct', async () => {
    const { spec, runset } = await (0, runner_1.runner)('struct', {}, '../../build/test/test.json', {
        test: () => ({
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
                    walk: struct_1.walk,
                    validate: struct_1.validate,
                    joinurl: struct_1.joinurl,
                }
            })
        })
    });
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
        (0, node_assert_1.equal)('function', typeof struct_1.setprop);
        (0, node_assert_1.equal)('function', typeof struct_1.stringify);
    });
    (0, node_test_1.test)('minor-clone', async () => {
        await runset(spec.minor.clone, struct_1.clone);
    });
    (0, node_test_1.test)('minor-isnode', async () => {
        await runset(spec.minor.isnode, struct_1.isnode);
    });
    (0, node_test_1.test)('minor-ismap', async () => {
        await runset(spec.minor.ismap, struct_1.ismap);
    });
    (0, node_test_1.test)('minor-islist', async () => {
        await runset(spec.minor.islist, struct_1.islist);
    });
    (0, node_test_1.test)('minor-iskey', async () => {
        await runset(spec.minor.iskey, struct_1.iskey);
    });
    (0, node_test_1.test)('minor-isempty', async () => {
        await runset(spec.minor.isempty, struct_1.isempty);
    });
    (0, node_test_1.test)('minor-escre', async () => {
        await runset(spec.minor.escre, struct_1.escre);
    });
    (0, node_test_1.test)('minor-escurl', async () => {
        await runset(spec.minor.escurl, struct_1.escurl);
    });
    (0, node_test_1.test)('minor-stringify', async () => {
        await runset(spec.minor.stringify, (vin) => null == vin.max ? (0, struct_1.stringify)(vin.val) : (0, struct_1.stringify)(vin.val, vin.max));
    });
    (0, node_test_1.test)('minor-items', async () => {
        await runset(spec.minor.items, struct_1.items);
    });
    (0, node_test_1.test)('minor-getprop', async () => {
        await runset(spec.minor.getprop, (vin) => null == vin.alt ? (0, struct_1.getprop)(vin.val, vin.key) : (0, struct_1.getprop)(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('minor-setprop', async () => {
        await runset(spec.minor.setprop, (vin) => (0, struct_1.setprop)(vin.parent, vin.key, vin.val));
    });
    (0, node_test_1.test)('minor-haskey', async () => {
        await runset(spec.minor.haskey, struct_1.haskey);
    });
    (0, node_test_1.test)('minor-keysof', async () => {
        await runset(spec.minor.keysof, struct_1.keysof);
    });
    (0, node_test_1.test)('minor-joinurl', async () => {
        await runset(spec.minor.joinurl, struct_1.joinurl);
    });
    (0, node_test_1.test)('minor-isfunc', async () => {
        await runset(spec.minor.isfunc, struct_1.isfunc);
        function f0() { return null; }
        (0, node_assert_1.equal)((0, struct_1.isfunc)(f0), true);
        (0, node_assert_1.equal)((0, struct_1.isfunc)(() => null), true);
    });
    // walk tests
    // ==========
    (0, node_test_1.test)('walk-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('walk-basic', async () => {
        await runset(spec.walk.basic, (vin) => (0, struct_1.walk)(vin, walkpath));
    });
    // merge tests
    // ===========
    (0, node_test_1.test)('merge-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('merge-basic', async () => {
        const test = (0, struct_1.clone)(spec.merge.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-cases', async () => {
        await runset(spec.merge.cases, struct_1.merge);
    });
    (0, node_test_1.test)('merge-array', async () => {
        await runset(spec.merge.array, struct_1.merge);
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
        await runset(spec.getpath.basic, (vin) => (0, struct_1.getpath)(vin.path, vin.store));
    });
    (0, node_test_1.test)('getpath-current', async () => {
        await runset(spec.getpath.current, (vin) => (0, struct_1.getpath)(vin.path, vin.store, vin.current));
    });
    (0, node_test_1.test)('getpath-state', async () => {
        const state = {
            handler: (state, val, _current, _ref, _store) => {
                let out = state.step + ':' + val;
                state.step++;
                return out;
            },
            step: 0,
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
        await runset(spec.getpath.state, (vin) => (0, struct_1.getpath)(vin.path, vin.store, vin.current, state));
    });
    // inject tests
    // ============
    (0, node_test_1.test)('inject-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.inject);
    });
    (0, node_test_1.test)('inject-basic', async () => {
        const test = (0, struct_1.clone)(spec.inject.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.inject)(test.in.val, test.in.store), test.out);
    });
    (0, node_test_1.test)('inject-string', async () => {
        await runset(spec.inject.string, (vin) => (0, struct_1.inject)(vin.val, vin.store, nullModifier, vin.current));
    });
    (0, node_test_1.test)('inject-deep', async () => {
        await runset(spec.inject.deep, (vin) => (0, struct_1.inject)(vin.val, vin.store));
    });
    // transform tests
    // ===============
    (0, node_test_1.test)('transform-exists', async () => {
        (0, node_assert_1.equal)('function', typeof struct_1.transform);
    });
    (0, node_test_1.test)('transform-basic', async () => {
        const test = (0, struct_1.clone)(spec.transform.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.transform)(test.in.data, test.in.spec, test.in.store), test.out);
    });
    (0, node_test_1.test)('transform-paths', async () => {
        await runset(spec.transform.paths, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-cmds', async () => {
        await runset(spec.transform.cmds, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-each', async () => {
        await runset(spec.transform.each, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-pack', async () => {
        await runset(spec.transform.pack, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-modify', async () => {
        await runset(spec.transform.modify, (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store, (val, key, parent) => {
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
        await runset(spec.validate.basic, (vin) => (0, struct_1.validate)(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-node', async () => {
        await runset(spec.validate.node, (vin) => (0, struct_1.validate)(vin.data, vin.spec));
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
        (0, struct_1.validate)({ a: 1 }, { a: '`$INTEGER`' }, extra, errs);
        (0, node_assert_1.equal)(errs.length, 0);
        (0, struct_1.validate)({ a: 'A' }, { a: '`$INTEGER`' }, extra, errs);
        (0, node_assert_1.deepEqual)(errs, ['Not an integer at a: A']);
    });
});
//# sourceMappingURL=struct.test.js.map