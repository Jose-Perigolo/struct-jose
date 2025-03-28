
const structUtils = require('../src/struct')

class SDK {

  #opts = {}
  #utility = {}
  
  constructor(opts) {
    this.#opts = opts || {}
    this.#utility = {
      struct: structUtils,
      check: (ctx) => {
        return {
          zed: 'ZED' +
            (null == this.#opts ? '' : null == this.#opts.foo ? '' : this.#opts.foo) +
            '_' +
            (null == ctx.bar ? '0' : ctx.bar)
        }
      }
    }
  }

  static async test(opts) {
    return new SDK(opts)
  }

  async test(opts) {
    return new SDK(opts)
  }

  utility() { 
    return this.#utility 
  }
}

module.exports = {
  SDK
}
