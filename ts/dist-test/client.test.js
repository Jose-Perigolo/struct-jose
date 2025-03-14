"use strict";
// RUN: npm test
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const runner_1 = require("./runner");
(0, node_test_1.describe)('client', async () => {
    const { spec, runset, subject } = await (0, runner_1.runner)('check', {}, '../../build/test/test.json', {
        test: async (opts) => ({
            utility: () => ({
                check: (_arg) => {
                    return { zed: 'ZED' + (null == opts ? '' : null == opts.foo ? '0' : opts.foo) };
                }
            })
        })
    });
    // console.log('CHECK', spec, runset, subject)
    (0, node_test_1.test)('check', async () => {
        await runset(spec.basic, subject);
    });
});
//# sourceMappingURL=client.test.js.map