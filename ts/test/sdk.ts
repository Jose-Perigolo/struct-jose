
import * as structUtils from '../dist/struct'

class SDK {

  #opts: any = {}
  #utility: any = {}

  constructor(opts?: any) {
    this.#opts = opts || {}
    this.#utility = {
      struct: structUtils,
      check: (ctx: any) => {
        return {
          zed: 'ZED' +
            (null == this.#opts ? '' : null == this.#opts.foo ? '' : this.#opts.foo) +
            '_' +
            (null == ctx.bar ? '0' : ctx.bar)
        }
      }
    }
  }

  static async test(opts?: any) {
    return new SDK(opts)
  }

  async test(opts?: any) {
    return new SDK(opts)
  }

  utility() {
    return this.#utility
  }
}

export {
  SDK
}
