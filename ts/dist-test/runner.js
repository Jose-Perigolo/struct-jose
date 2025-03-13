"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NULLMARK = void 0;
exports.nullModifier = nullModifier;
exports.runner = runner;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const node_assert_1 = require("node:assert");
const NULLMARK = '__NULL__';
exports.NULLMARK = NULLMARK;
async function runner(name, store, testfile, provider) {
    const client = await provider.test();
    const utility = client.utility();
    const structUtils = utility.struct;
    let spec = resolveSpec(name, testfile);
    let clients = await resolveClients(spec, store, provider, structUtils);
    // let subject = (utility as any)[name]
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
async function resolveClients(spec, store, provider, structUtils) {
    const clients = {};
    if (spec.DEF) {
        for (let cdef of structUtils.items(spec.DEF.client)) {
            const copts = cdef[1].test.options || {};
            if ('object' === typeof store) {
                structUtils.inject(copts, store);
            }
            clients[cdef[0]] = await provider.test(copts);
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
    const structUtils = testpack.utility.struct;
    let args = [structUtils.clone(entry.in)];
    if (entry.ctx) {
        args = [entry.ctx];
    }
    else if (entry.args) {
        args = entry.args;
    }
    if (entry.ctx || entry.args) {
        let first = args[0];
        if ('object' === typeof first && null != first) {
            entry.ctx = first = args[0] = structUtils.clone(args[0]);
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