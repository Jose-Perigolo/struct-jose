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
        (0, node_assert_1.deepEqual)(apply(entry.in), entry.out);
    }
}
(0, node_test_1.describe)('struct', () => {
    (0, node_test_1.test)('minor-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.clone);
        (0, node_assert_1.equal)('function', typeof struct_1.isnode);
        (0, node_assert_1.equal)('function', typeof struct_1.ismap);
        (0, node_assert_1.equal)('function', typeof struct_1.islist);
        (0, node_assert_1.equal)('function', typeof struct_1.items);
        (0, node_assert_1.equal)('function', typeof struct_1.prop);
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
    (0, node_test_1.test)('minor-items', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.items), struct_1.items);
    });
    (0, node_test_1.test)('minor-prop', () => {
        test_set((0, struct_1.clone)(TESTSPEC.minor.prop), (vin) => null == vin.alt ? (0, struct_1.prop)(vin.val, vin.key) : (0, struct_1.prop)(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('merge-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('merge-basic', () => {
        const test = (0, struct_1.clone)(TESTSPEC.merge.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-children', () => {
        const test = (0, struct_1.clone)(TESTSPEC.merge.children);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-array', () => {
        test_set((0, struct_1.clone)(TESTSPEC.merge.array), struct_1.merge);
    });
    (0, node_test_1.test)('walk-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('walk-basic', () => {
        test_set((0, struct_1.clone)(TESTSPEC.walk.basic), (vin) => (0, struct_1.walk)(vin, walkpath));
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
            handler: (val, parts, store, current, state) => {
                state.last = state.step + ':' + parts.join('.') + ':' + val;
                state.step++;
                return state.last;
            },
            step: 0,
            last: undefined
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
        test_set((0, struct_1.clone)(TESTSPEC.transform.modify), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store, (key, _val, newval, parent) => {
            if (null != key && null != parent && 'string' === typeof newval) {
                parent[key] = '@' + newval;
            }
        }));
    });
});
function walkpath(_key, val, _parent, path) {
    return 'string' === typeof val ? val + '~' + path.join('.') : val;
}
//# sourceMappingURL=struct.test.js.map