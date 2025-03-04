#include "utility_decls.hpp"

// Struct Utility Functions


namespace S {
    const std::string empty = "";
};

inline json isnode(args_container&& args) {
  json val = args.size() == 0 ? nullptr : std::move(args[0]);

  return static_cast<bool>(val.is_array() || val.is_object());
}

inline json ismap(args_container&& args) {
  json val = args.size() == 0 ? nullptr : std::move(args[0]);

  // NOTE: explicit static_case not needed but let's stay explicit in case we change the library
  return static_cast<bool>(val.is_object());
}

inline json islist(args_container&& args) {
  json val = args.size() == 0 ? nullptr : std::move(args[0]);

  return static_cast<bool>(val.is_array());
}


json iskey(args_container&& args) {
  json val = args.size() == 0 ? nullptr : std::move(args[0]);

  // TODO: Refactor the if statements
  if(val.is_string()) {
    return (val.get<std::string>()).length() > 0;
  }

  if(val.is_boolean()) {
    return false;
  }

  if(val.is_number_integer()) {
    return true;
  }


  return false;
}

json isempty(args_container&& args) {
  json val = args.size() == 0 ? nullptr : std::move(args[0]);

  // val.is_null()
  if(val == nullptr) {
    return true;
  }

  if(val == S::empty) {
    return true;
  }

  if(islist({ val }) && val.size() == 0) {
    return true;
  }

  if(ismap({ val }) && val.size() == 0) {
    return true;
  }



  return false;
}

// NOTE: Use template specialization
// TODO: For Python and JS, this is determined at runtime (via callable or similar) so that doesn't mirror the exact implementation as it is supposed to
// Proposal: Create a wrapper:
// class {
//   type t;
//   union {
//      json json_obj;
//      std::function<json(args_container&&)> func;
//   }
// };
// Alternatively, our own Data Structure
// class VxgDataStruct { };

template<class T>
json isfunc(T&& args) {
  return false;
}

template<class T>
json isfunc(T& args) {
  return false;
}

template<>
json isfunc<args_container>(args_container&& args) {
  return false;
}

template<>
json isfunc<std::function<json(args_container&&)>>(std::function<json(args_container&&)>& func) {
  return true;
}

template<>
json isfunc<std::function<json(args_container&&)>>(std::function<json(args_container&&)>&& func) {
  return true;
}


json getprop(args_container&& args) {
  std::cout << args << std::endl;
  std::cout << "size(): " << args.size() << std::endl;

  json val = args.size() == 0 ? nullptr : std::move(args[0]);
  json key = args.size() < 2 ? nullptr : std::move(args[1]);
  json alt = args.size() < 3 ? nullptr : std::move(args[2]);

  if(val.is_null()) {
    return alt;
  }

  if(key.is_null()) {
    return alt;
  }


  return false;
}

