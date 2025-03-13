package = "@voxgig/struct"
version = "0.0-1"
source = {
  url = "https://github.com/voxgig/struct/archive/refs/tags/0.0-1.tar.gz",
  tag = "0.0-1"
}
description = {
  summary = "Data structure manipulations",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  "busted >= 2.2"
}
build = {
  type = "builtin",
  modules = {
    ["struct"] = "src/struct.lua"
  }
}
