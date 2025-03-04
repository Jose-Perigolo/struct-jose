#include "utility_decls.hpp"

// Struct Utility Functions

json islist(arg_container&& args) {
  json obj = args.size() == 0 ? nullptr : std::move(args[0]);

  // NOTE: static case not needed but let's stay explicit in case we change the library
  return static_cast<bool>(obj.is_array());
}

json isnode(arg_container&& args) {
  json obj = args.size() == 0 ? nullptr : std::move(args[0]);

  return static_cast<bool>(obj.is_array() || obj.is_object());
}

json ismap(arg_container&& args) {
  json obj = args.size() == 0 ? nullptr : std::move(args[0]);

  return static_cast<bool>(obj.is_object());
}

