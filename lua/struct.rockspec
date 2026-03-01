package = "voxgig-struct"
version = "0.0-1"
source = {
   url = "git://github.com/voxgig/struct/lua/struct.lua"
}
description = {
   summary = "Utility functions for JSON-like data structures",
   detailed = [[
      Utility functions to manipulate in-memory JSON-like data structures.
      Includes functions for walking, merging, transforming, and validating data.
   ]],
   license = "MIT"
}
dependencies = {
   "lua >= 5.3",
   "busted >= 2.0.0",
   "luassert >= 1.8.0",
   "dkjson >= 2.5",
   "luafilesystem >= 1.8.0"
}
build = {
   type = "builtin",
   modules = {
      struct = "struct.lua"
   },
   copy_directories = {"test"}
}
