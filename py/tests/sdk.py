# import os


import voxgig_struct

class StructUtils:
    def __init__(self):
        # Copy all attributes from the voxgig_struct module to this class
        for attr_name in dir(voxgig_struct):
            # Skip private attributes and modules
            if not attr_name.startswith('_'):
                setattr(self, attr_name, getattr(voxgig_struct, attr_name))

class Utility:
    def __init__(self, opts=None):
        self._opts = opts
        self.struct = StructUtils()

    def check(self, ctx):
        zed = "ZED"
    
        if self._opts is None:
            zed += ""
        else:
            foo = self._opts.get("foo")
            zed += "0" if foo is None else str(foo)

        zed += "_"
        zed += str(ctx.get("bar"))

        return {"zed": zed}


class SDK:
    def __init__(self, opts=None):
        self._opts = opts or {}
        self._utility = Utility(opts)
        
    @staticmethod
    def test(opts=None):
        return SDK(opts)
        
    def tester(self, opts=None):
        return SDK(self.opts if None == opts else opts)
        
    def utility(self):
        return self._utility
