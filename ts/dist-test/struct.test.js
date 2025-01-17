"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_test_1 = require("node:test");
const node_assert_1 = require("node:assert");
const struct_1 = require("../dist/struct");
const TESTSPEC = JSON.parse((0, node_fs_1.readFileSync)((0, node_path_1.join)(__dirname, '..', '..', 'build/test/test.json'), 'utf8'));
function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}
function test_set(tests, apply) {
    for (let entry of tests.set) {
        (0, node_assert_1.deepEqual)(apply(entry.in), entry.out);
    }
}
(0, node_test_1.describe)('struct', () => {
    (0, node_test_1.test)('merge-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('merge-basic', () => {
        const test = clone(TESTSPEC.merge.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-children', () => {
        const test = clone(TESTSPEC.merge.children);
        (0, node_assert_1.deepEqual)((0, struct_1.merge)(test.in), test.out);
    });
    (0, node_test_1.test)('merge-array', () => {
        test_set(clone(TESTSPEC.merge.array), struct_1.merge);
    });
    (0, node_test_1.test)('walk-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.merge);
    });
    (0, node_test_1.test)('walk-basic', () => {
        test_set(clone(TESTSPEC.walk.basic), (vin) => (0, struct_1.walk)(vin, walkpath));
    });
    (0, node_test_1.test)('getpath-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.getpath);
    });
    (0, node_test_1.test)('getpath-basic', () => {
        test_set(clone(TESTSPEC.getpath.basic), (vin) => (0, struct_1.getpath)(vin.path, vin.store));
    });
    (0, node_test_1.test)('inject-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.inject);
    });
    (0, node_test_1.test)('inject-basic', () => {
        const test = clone(TESTSPEC.inject.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.inject)(test.in.val, test.in.store), test.out);
    });
    (0, node_test_1.test)('inject-deep', () => {
        test_set(clone(TESTSPEC.inject.deep), (vin) => (0, struct_1.inject)(vin.val, vin.store));
    });
    (0, node_test_1.test)('transform-exists', () => {
        (0, node_assert_1.equal)('function', typeof struct_1.transform);
    });
    (0, node_test_1.test)('transform-basic', () => {
        const test = clone(TESTSPEC.transform.basic);
        (0, node_assert_1.deepEqual)((0, struct_1.transform)(test.in.data, test.in.spec, test.in.store), test.out);
    });
    (0, node_test_1.test)('transform-paths', () => {
        test_set(clone(TESTSPEC.transform.paths), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-cmds', () => {
        test_set(clone(TESTSPEC.transform.cmds), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-each', () => {
        test_set(clone(TESTSPEC.transform.each), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-pack', () => {
        test_set(clone(TESTSPEC.transform.pack), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store));
    });
    (0, node_test_1.test)('transform-modify', () => {
        test_set(clone(TESTSPEC.transform.modify), (vin) => (0, struct_1.transform)(vin.data, vin.spec, vin.store, (key, _val, newval, parent) => {
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