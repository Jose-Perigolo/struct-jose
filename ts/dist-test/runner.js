"use strict";
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var _Client_opts, _Client_utility;
Object.defineProperty(exports, "__esModule", { value: true });
exports.Client = exports.NULLMARK = void 0;
exports.nullModifier = nullModifier;
exports.runner = runner;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_assert_1 = require("node:assert");
// Runner does make used of these struct utilities, and this usage is
// circular. This is a trade-off tp make the runner code simpler.
const struct_1 = require("../dist/struct");
class Client {
    constructor(opts) {
        _Client_opts.set(this, void 0);
        _Client_utility.set(this, void 0);
        __classPrivateFieldSet(this, _Client_opts, opts, "f");
        __classPrivateFieldSet(this, _Client_utility, {
            struct: {
                clone: struct_1.clone,
                getpath: struct_1.getpath,
                inject: struct_1.inject,
                items: struct_1.items,
                stringify: struct_1.stringify,
                walk: struct_1.walk,
            },
            check: (ctx) => {
                return {
                    zed: 'ZED' +
                        (null == __classPrivateFieldGet(this, _Client_opts, "f") ? '' : null == __classPrivateFieldGet(this, _Client_opts, "f").foo ? '' : __classPrivateFieldGet(this, _Client_opts, "f").foo) +
                        '_' +
                        (null == ctx.bar ? '0' : ctx.bar)
                };
            }
        }, "f");
    }
    static async test(opts) {
        return new Client(opts || {});
    }
    utility() { return __classPrivateFieldGet(this, _Client_utility, "f"); }
}
exports.Client = Client;
_Client_opts = new WeakMap(), _Client_utility = new WeakMap();
const NULLMARK = '__NULL__';
exports.NULLMARK = NULLMARK;
async function runner(name, store, testfile) {
    const client = await Client.test();
    const utility = client.utility();
    const structUtils = utility.struct;
    let spec = resolveSpec(name, testfile);
    let clients = await resolveClients(spec, store, structUtils);
    let subject = resolveSubject(name, utility);
    let runsetflags = async (testspec, flags, testsubject) => {
        subject = testsubject || subject;
        flags = resolveFlags(flags);
        const testspecmap = fixJSON(testspec, flags);
        const testset = testspecmap.set;
        for (let entry of testset) {
            try {
                entry = resolveEntry(entry, flags);
                let testpack = resolveTestPack(name, entry, subject, client, clients);
                let args = resolveArgs(entry, testpack);
                let res = await testpack.subject(...args);
                res = fixJSON(res, flags);
                entry.res = res;
                checkResult(entry, res, structUtils);
            }
            catch (err) {
                handleError(entry, err, structUtils);
            }
        }
    };
    let runset = async (testspec, testsubject) => runsetflags(testspec, {}, testsubject);
    let runpack = {
        spec,
        runset,
        runsetflags,
        subject,
    };
    return runpack;
}
function resolveSpec(name, testfile) {
    const alltests = JSON.parse((0, node_fs_1.readFileSync)((0, node_path_1.join)(__dirname, testfile), 'utf8'));
    let spec = alltests.primary?.[name] || alltests[name] || alltests;
    return spec;
}
async function resolveClients(spec, store, structUtils) {
    const clients = {};
    if (spec.DEF && spec.DEF.client) {
        for (let cn in spec.DEF.client) {
            const cdef = spec.DEF.client[cn];
            const copts = cdef.test.options || {};
            if ('object' === typeof store && structUtils?.inject) {
                structUtils.inject(copts, store);
            }
            clients[cn] = await Client.test(copts);
        }
    }
    return clients;
}
function resolveSubject(name, container) {
    return container?.[name];
}
function resolveFlags(flags) {
    if (null == flags) {
        flags = {};
    }
    flags.null = null == flags.null ? true : !!flags.null;
    return flags;
}
function resolveEntry(entry, flags) {
    entry.out = null == entry.out && flags.null ? NULLMARK : entry.out;
    return entry;
}
function checkResult(entry, res, structUtils) {
    if (undefined === entry.match || undefined !== entry.out) {
        // NOTE: don't use clone as we want to strip functions
        (0, node_assert_1.deepEqual)(null != res ? JSON.parse(JSON.stringify(res)) : res, entry.out);
    }
    if (entry.match) {
        match(entry.match, { in: entry.in, out: entry.res, ctx: entry.ctx }, structUtils);
    }
}
// Handle errors from test execution
function handleError(entry, err, structUtils) {
    entry.thrown = err;
    const entry_err = entry.err;
    if (null != entry_err) {
        if (true === entry_err || matchval(entry_err, err.message, structUtils)) {
            if (entry.match) {
                match(entry.match, { in: entry.in, out: entry.res, ctx: entry.ctx, err }, structUtils);
            }
            return;
        }
        (0, node_assert_1.fail)('ERROR MATCH: [' + structUtils.stringify(entry_err) +
            '] <=> [' + err.message + ']');
    }
    // Unexpected error (test didn't specify an error expectation)
    else if (err instanceof node_assert_1.AssertionError) {
        (0, node_assert_1.fail)(err.message + '\n\nENTRY: ' + JSON.stringify(entry, null, 2));
    }
    else {
        (0, node_assert_1.fail)(err.stack + '\\nnENTRY: ' + JSON.stringify(entry, null, 2));
    }
}
function resolveArgs(entry, testpack) {
    // let args = [structUtils.clone(entry.in)]
    let args = [(0, struct_1.clone)(entry.in)];
    if (entry.ctx) {
        args = [entry.ctx];
    }
    else if (entry.args) {
        args = entry.args;
    }
    if (entry.ctx || entry.args) {
        let first = args[0];
        if ('object' === typeof first && null != first) {
            entry.ctx = first = args[0] = (0, struct_1.clone)(args[0]);
            first.client = testpack.client;
            first.utility = testpack.utility;
        }
    }
    return args;
}
function resolveTestPack(name, entry, subject, client, clients) {
    const testpack = {
        client,
        subject,
        utility: client.utility(),
    };
    // console.log('CLIENTS', clients)
    if (entry.client) {
        testpack.client = clients[entry.client];
        testpack.utility = testpack.client.utility();
        testpack.subject = resolveSubject(name, testpack.utility);
    }
    return testpack;
}
function match(check, base, structUtils) {
    structUtils.walk(check, (_key, val, _parent, path) => {
        let scalar = 'object' != typeof val;
        if (scalar) {
            let baseval = structUtils.getpath(path, base);
            if (!matchval(val, baseval, structUtils)) {
                (0, node_assert_1.fail)('MATCH: ' + path.join('.') +
                    ': [' + structUtils.stringify(val) + '] <=> [' + structUtils.stringify(baseval) + ']');
            }
        }
    });
}
function matchval(check, base, structUtils) {
    check = '__UNDEF__' === check ? undefined : check;
    let pass = check === base;
    if (!pass) {
        if ('string' === typeof check) {
            let basestr = structUtils.stringify(base);
            let rem = check.match(/^\/(.+)\/$/);
            if (rem) {
                pass = new RegExp(rem[1]).test(basestr);
            }
            else {
                pass = basestr.toLowerCase().includes(structUtils.stringify(check).toLowerCase());
            }
        }
        else if ('function' === typeof check) {
            pass = true;
        }
    }
    return pass;
}
function fixJSON(val, flags) {
    if (null == val) {
        return flags.null ? NULLMARK : val;
    }
    const replacer = (_k, v) => null == v && flags.null ? NULLMARK : v;
    return JSON.parse(JSON.stringify(val, replacer));
}
function nullModifier(val, key, parent) {
    if ("__NULL__" === val) {
        parent[key] = null;
    }
    else if ('string' === typeof val) {
        parent[key] = val.replaceAll('__NULL__', 'null');
    }
}
//# sourceMappingURL=runner.js.map