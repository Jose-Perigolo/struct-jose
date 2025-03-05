#include "utility_decls.hpp"

// Struct Utility Functions


namespace VoxgigStruct {

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
    json isfunc<args_container&&>(args_container&& args) {
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
    json val = args.size() == 0 ? nullptr : std::move(args[0]);
    json key = args.size() < 2 ? nullptr : std::move(args[1]);
    json alt = args.size() < 3 ? nullptr : std::move(args[2]);

    if(val.is_null()) {
      return alt;
    }

    if(key.is_null()) {
      return alt;
    }

    json out = alt;

    if(ismap({val})) {
      out = val.value(key.is_string() ? key : json(key.dump()), alt);
    }
    else if(islist({val})) {
      int _key {0};

      try {
        _key = key.get<int>();
      } catch(const json::exception&) {

        try {
          std::string __key = key.get<std::string>();
          // TODO: Refactor: this is O(2n)
          Auxiliary::validate_int(__key);
          _key = std::stoi(__key);
          goto try_access;

        } catch(...) {}

        return alt;
      }

try_access:
      if(0 <= _key && _key < val.size()) {
        return val[_key];
      } else {
        return alt;
      }

    }

    if(out.is_null()) {
      out = alt;
    }



    return out;
  }


  json keysof(args_container&& args) {
    json val = args.size() == 0 ? nullptr : args[0];

    if(isnode({val}) == false) {
      return json::array();
    } else if(ismap({val})) {
      json keys = json::array();
      for(json::iterator it = val.begin(); it != val.end(); it++) {
        keys.push_back(it.key());
      }
      return keys; // TODO: sorted(val.keys()). HOWEVER, the keys appear to be sorted (in order) by default. Try "std::cout << json::parse(R"({"b": 1, "a": 2})") << std::endl;"
    } else {
      json arr = json::array();
      for(int i = 0; i < val.size(); i++) {
        arr.push_back(i);
      }
      return arr;
    }

  }

  json haskey(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);
    json key = args.size() < 2 ? nullptr : std::move(args[1]);

    return getprop({val, key}) != nullptr;
  }

  json items(args_container&& args) {
    json val = args.size() == 0 ? nullptr : std::move(args[0]);

    if(ismap({ val })) {
      json _items = json::array();
      for(json::iterator it = val.begin(); it != val.end(); it++) {
        json pair = json::array();
        pair.push_back(it.key());
        pair.push_back(it.value());

        _items.push_back(pair);
      }
      return _items;

    } else if(islist({ val })) {
      json _items = json::array();
      int i = 0;

      for(json::iterator it = val.begin(); it != val.end(); it++, i++) {
        json pair = json::array();
        pair.push_back(i);
        pair.push_back(it.value());
        _items.push_back(pair);
      }

      return _items;
    } else {
      return json::array();
    }

  }

  json escre(args_container&& args) {
    json s = args.size() == 0 ? nullptr : std::move(args[0]);

    if(s == nullptr) {
      s = S::empty;
    }

    const std::string& s_string = s.get<std::string>();

    const std::regex pattern(R"([.*+?^${}()|[\]\\])");

    return std::regex_replace(s_string, pattern, R"(\$&)");

  }

  json escurl(args_container&& args) {
    json s = args.size() == 0 ? nullptr : std::move(args[0]);

    if(s == nullptr) {
      s = S::empty;
    }

    const std::string& s_string = s.get<std::string>();

    std::ostringstream escaped;
    escaped.fill('0');
    escaped << std::hex;

    for (unsigned char c : s_string) {
      // Encode non-alphanumeric characters except '-' '_' '.' '~'
      if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
        escaped << c;
      } else {
        escaped << '%' << std::uppercase << std::setw(2) << int(c);
        escaped << std::nouppercase;
      }
    }

    return escaped.str();
  }

  json joinurl(args_container&& args) {
    json _sarr = args.size() == 0 ? nullptr : std::move(args[0]);

    std::vector<std::string> sarr;

    std::vector<std::string> parts;

    for(json::iterator it = _sarr.begin(); it != _sarr.end(); it++) {
      json v = it.value();
      if(v != nullptr && v != "") {
        sarr.push_back(v.get<std::string>());
      }
    }


    // Refactor: double loop
    for (size_t i = 0; i < sarr.size(); ++i) {
      std::string s = sarr[i];

      if(i == 0) {
            s = std::regex_replace(s, std::regex(R"(([^/])/+)"), "$1/");
            s = std::regex_replace(s, std::regex(R"(/+$)"), "");
      } else {
            s = std::regex_replace(s, std::regex(R"(([^/])/+)"), "$1/"); // Merge multiple slashes after a character
            s = std::regex_replace(s, std::regex(R"(^/+)"), ""); // Remove leading slashes
            s = std::regex_replace(s, std::regex(R"(/+$)"), "");
      }

      if (!s.empty()) {
        parts.push_back(s);
      }

    }

    std::string out = parts.empty() ? "" : std::accumulate(parts.begin() + 1, parts.end(), parts[0],
        [](const std::string& a, const std::string& b) {
          return a + "/" + b;
        });

    return out;

  }


}
