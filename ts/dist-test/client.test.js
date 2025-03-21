"use strict";
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=check
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const runner_1 = require("./runner");
(0, node_test_1.describe)('client', async () => {
    const { spec, runset, subject } = await (0, runner_1.runner)('check', {}, '../../build/test/test.json');
    (0, node_test_1.test)('check-basic', async () => {
        await runset(spec.basic, subject);
    });
});
//# sourceMappingURL=client.test.js.map