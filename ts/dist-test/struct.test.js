"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_test_1 = require("node:test");
const node_assert_1 = require("node:assert");
const struct_1 = require("../dist/struct");
const TESTSPEC = JSON.parse((0, node_fs_1.readFileSync)((0, node_path_1.join)(__dirname, '..', '..', 'build/test/test.json'), 'utf8'));
function test_set(tests, apply) {
    for (let entry of tests.set) {
        try {
            (0, node_assert_1.deepEqual)(apply(entry.in), entry.out);
        }
        catch (err) {
            const entry_err = entry.err;
            if (null != entry_err) {
                if (true === entry_err || (err.message.includes(entry_err))) {
                    break;
                }
                entry.thrown = err.message;
                (0, node_assert_1.fail)(JSON.stringify(entry));
            }
            else {
                throw err;
            }
        }
    }
}
function walkpath(_key, val, _parent, path) {
    return 'string' === typeof val ? val + '~' + path.join('.') : val;
}
(0, node_test_1.describe)('struct', () => {
    // minor tests
    // ===========
    (0, node_test_1.test)('minor-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.clone);
        (0, node_assert_1.equal)('function', typeof struct_1.isnode);
        (0, node_assert_1.equal)('function', typeof struct_1.ismap);
        (0, node_assert_1.equal)('function', typeof struct_1.islist);
        (0, node_assert_1.equal)('function', typeof struct_1.iskey);
        (0, node_assert_1.equal)('function', typeof struct_1.items);
        (0, node_assert_1.equal)('function', typeof struct_1.getprop);
        (0, node_assert_1.equal)('function', typeof struct_1.setprop);
    });
    (0, node_test_1.test)('minor-clone', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.clone), struct_1.clone);
    });
    (0, node_test_1.test)('minor-isnode', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.isnode), struct_1.isnode);
    });
    (0, node_test_1.test)('minor-ismap', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.ismap), struct_1.ismap);
    });
    (0, node_test_1.test)('minor-islist', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.islist), struct_1.islist);
    });
    (0, node_test_1.test)('minor-iskey', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.iskey), struct_1.iskey);
    });
    (0, node_test_1.test)('minor-items', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.items), struct_1.items);
    });
    (0, node_test_1.test)('minor-getprop', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.getprop), (vin) => null == vin.alt ? (0, struct_1.getprop)(vin.val, vin.key) : (0, struct_1.getprop)(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('minor-setprop', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.setprop), (vin) => (0, struct_1.setprop)(vin.parent, vin.key, vin.val));
    });
    // walk tests
    // ==========
    (0, node_test_1.test)('walk-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('walk-basic', () => {
        test_set((0, struct_1.clone)(TESTSPEC.walk.basic), (vin) => (0, struct_1.walk)(vin, walkpath));
    });
    // merge tests
    // ===========
    (0, node_test_1.test)('merge-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('merge-basic', () => {
        const test = (0, struct_1.clone)(TESTSPEC.merge.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-cases', () => {
        test_set((0, struct_1.clone)(TESTSPEC.merge.cases), struct_1.merge);
    });
    (0, node_test_1.test)('merge-array', () => {
        test_set((0, struct_1.clone)(TESTSPEC.merge.array), struct_1.merge);
    });
    (0, node_test_1.test)('getpath-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.getpath);
    });
    (0, node_test_1.test)('getpath-basic', () => {
        test_set((0, struct_1.clone)(TESTSPEC.getpath.basic), (vin) => (0, struct_1.getpath)(vin.path, vin.store));
    });
    (0, node_test_1.test)('getpath-current', () => {
        test_set((0, struct_1.clone)(TESTSPEC.getpath.current), (vin) => (0, struct_1.getpath)(vin.path, vin.store, vin.current));
    });
    (0, node_test_1.test)('getpath-state', () => {
        const state = {
            handler: (state, val, _current, _store) => {
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
            base: '$TOP'
        };
        test_set((0, struct_1.clone)(TESTSPEC.getpath.state), (vin) => (0, struct_1.getpath)(vin.path, vin.store, vin.current, state));
    });
    (0, node_test_1.test)('inject-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.inject);
    });
    (0, node_test_1.test)('inject-basic', () => {
        const test = (0, struct_1.clone)(TESTSPEC.inject.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.inject)(test.in.val, test.in.store), test.out);
    });
    (0, node_test_1.test)('inject-string', () => {
        test_set((0, struct_1.clone)(TESTSPEC.inject.string), (vin) => (0, struct_1.inject)(vin.val, vin.store, vin.current));
    });
    (0, node_test_1.test)('inject-deep', () => {
        test_set((0, struct_1.clone)(TESTSPEC.inject.deep), (vin) => (0, struct_1.inject)(vin.val, vin.store));
    });
    (0, node_test_1.test)('transform-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.transform);
    });
    (0, node_test_1.test)('transform-basic', () => {
        const test = (0, struct_1.clone)(TESTSPEC.transform.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.transform)(test.in.data, test.in.spec, test.in.store), test.out);
    });
    (0, node_test_1.test)('transform-paths', () => {
        test_set((0, struct_1.clone)(TESTSPEC.transform.paths), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-cmds', () => {
        test_set((0, struct_1.clone)(TESTSPEC.transform.cmds), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-each', () => {
        test_set((0, struct_1.clone)(TESTSPEC.transform.each), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-pack', () => {
        test_set((0, struct_1.clone)(TESTSPEC.transform.pack), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-modify', () => {
        test_set((0, struct_1.clone)(TESTSPEC.transform.modify), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store, (key, val, parent) => {
            if (null != key && null != parent && 'string' === typeof val) {
                val = parent[key] = '@' + val;
            }
        }));
    });
    (0, node_test_1.test)('transform-extra', () => {
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
});
//# sourceMappingURL=struct.test.js.map