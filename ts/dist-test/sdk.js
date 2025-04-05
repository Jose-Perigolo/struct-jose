"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
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
var _SDK_opts, _SDK_utility;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SDK = void 0;
const structUtils = __importStar(require("../dist/struct"));
class SDK {
    constructor(opts) {
        _SDK_opts.set(this, {});
        _SDK_utility.set(this, {});
        __classPrivateFieldSet(this, _SDK_opts, opts || {}, "f");
        __classPrivateFieldSet(this, _SDK_utility, {
            struct: structUtils,
            contextify: (ctxmap) => ctxmap,
            check: (ctx) => {
                return {
                    zed: 'ZED' +
                        (null == __classPrivateFieldGet(this, _SDK_opts, "f") ? '' : null == __classPrivateFieldGet(this, _SDK_opts, "f").foo ? '' : __classPrivateFieldGet(this, _SDK_opts, "f").foo) +
                        '_' +
                        (null == ctx.bar ? '0' : ctx.bar)
                };
            }
        }, "f");
    }
    static async test(opts) {
        return new SDK(opts);
    }
    async tester(opts) {
        return new SDK(opts || __classPrivateFieldGet(this, _SDK_opts, "f"));
    }
    utility() {
        return __classPrivateFieldGet(this, _SDK_utility, "f");
    }
}
exports.SDK = SDK;
_SDK_opts = new WeakMap(), _SDK_utility = new WeakMap();
//# sourceMappingURL=sdk.js.map