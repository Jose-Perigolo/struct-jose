"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runner = runner;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_assert_1 = require("node:assert");
async function runner(name, store, testfile, provider) {
    const client = await provider.test();
    const utility = client.utility();
    const { clone, getpath, inject, items, stringify, walk, } = utility.struct;
    const alltests = JSON.parse((0, node_fs_1.readFileSync)((0, node_path_1.join)(__dirname, testfile), 'utf8'));
    // TODO: a more coherent namespace perhaps?
    let spec = alltests.primary?.[name] || alltests[name] || alltests;
    const clients = {};
    if (spec.DEF) {
        for (let cdef of items(spec.DEF.client)) {
            const copts = cdef[1].test.options || {};
            if ('object' === typeof store) {
                inject(copts, store);
            }
            clients[cdef[0]] = await provider.test(copts);
        }
    }
    let subject = utility[name];
    let runset = async (testspec, testsubject, makesubject) => {
        testsubject = testsubject || subject;
        next_entry: for (let entry of testspec.set) {
            try {
                let testclient = client;
                if (entry.client) {
                    testclient = clients[entry.client];
                    let utility = client.utility();
                    testsubject = utility[name];
                }
                if (makesubject) {
                    testsubject = makesubject(testsubject);
                }
                let args = [clone(entry.in)];
                if (entry.ctx) {
                    args = [entry.ctx];
                }
                else if (entry.args) {
                    args = entry.args;
                }
                if (entry.ctx || entry.args) {
                    let first = args[0];
                    if ('object' === typeof first && null != first) {
                        entry.ctx = first = args[0] = clone(args[0]);
                        first.client = testclient;
                        first.utility = testclient.utility();
                    }
                }
                let res = await testsubject(...args);
                entry.res = res;
                if (undefined === entry.match || undefined !== entry.out) {
                    // NOTE: don't use clone as we want to strip functions
                    (0, node_assert_1.deepEqual)(null != res ? JSON.parse(JSON.stringify(res)) : res, entry.out);
                }
                if (entry.match) {
                    match(entry.match, { in: entry.in, out: entry.res, ctx: entry.ctx });
                }
            }
            catch (err) {
                entry.thrown = err;
                const entry_err = entry.err;
                if (null != entry_err) {
                    // if (true === entry_err || (err.message.includes(entry_err))) {
                    if (true === entry_err || matchval(entry_err, err.message)) {
                        if (entry.match) {
                            match(entry.match, { in: entry.in, out: entry.res, ctx: entry.ctx, err });
                        }
                        continue next_entry;
                    }
                    (0, node_assert_1.fail)('ERROR MATCH: [' + stringify(entry_err) + '] <=> [' + err.message + ']');
                }
                else if (err instanceof node_assert_1.AssertionError) {
                    (0, node_assert_1.fail)(err.message + '\n\nENTRY: ' + JSON.stringify(entry, null, 2));
                }
                else {
                    (0, node_assert_1.fail)(err.stack + '\\nnENTRY: ' + JSON.stringify(entry, null, 2));
                }
            }
        }
    };
    function match(check, base) {
        walk(check, (_key, val, _parent, path) => {
            if ('object' != typeof val) {
                let baseval = getpath(path, base);
                if (!matchval(val, baseval)) {
                    (0, node_assert_1.fail)('MATCH: ' + path.join('.') +
                        ': [' + stringify(val) + '] <=> [' + stringify(baseval) + ']');
                }
            }
        });
    }
    function matchval(check, base) {
        check = '__UNDEF__' === check ? undefined : check;
        let pass = check === base;
        if (!pass) {
            if ('string' === typeof check) {
                let basestr = stringify(base);
                let rem = check.match(/^\/(.+)\/$/);
                if (rem) {
                    pass = new RegExp(rem[1]).test(basestr);
                }
                else {
                    pass = basestr.toLowerCase().includes(stringify(check).toLowerCase());
                }
            }
            else if ('function' === typeof check) {
                pass = true;
            }
        }
        return pass;
    }
    return {
        spec,
        runset,
        subject,
    };
}
//# sourceMappingURL=runner.js.map