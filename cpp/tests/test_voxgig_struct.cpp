#include <iostream>
#include <fstream>

#include <nlohmann/json.hpp>

#include <voxgig_struct.hpp>
#include <runner.hpp>


#define TEST_CASE(TEST_NAME) std::cout << "Running: " << TEST_NAME << " at " << __LINE__ << std::endl;

#define TEST_SUITE(NAME) std::cout << NAME << " " << " at " << __LINE__ << std::endl;


using namespace VoxgigStruct;

inline void Utility::set_key(const std::string& key, function_pointer p) {
  table[key] = p;
}

inline function_pointer& Utility::get_key(const std::string& key) {
  return table[key];
}

inline function_pointer& Utility::operator[](const std::string& key) {
  return get_key(key);
}

inline void Utility::set_table(hash_table<std::string, function_pointer>&& new_table) {
  table = std::move(new_table);
}

struct Struct : public Utility {

  Struct() {
    set_table({
        { "isnode", isnode },
        { "ismap",  ismap  },
        { "islist", islist },
        { "iskey", iskey },
        { "isempty", isempty },
        { "isfunc", isfunc<args_container&&> },
        { "getprop", getprop },
        { "keysof", keysof },
        { "haskey", haskey },
        { "items", items },
        { "escre", escre },
        { "joinurl", joinurl },
        { "stringify", stringify },
        { "clone", clone },
        { "setprop", setprop },
    });
  }

  ~Struct() = default;

};


// NOTE: More dynamic approach compared to function overloading
Provider::Provider(const json& opts = nullptr) {
  // Do opts
}

Provider Provider::test(const json& opts) {
  return Provider(opts);
}

Provider Provider::test(void) {
  return Provider(nullptr);
}


hash_table<std::string, Utility> Provider::utility() {
  return { 
    {
      "struct", Struct()
    }
  };

}

int main() {

  Provider provider = Provider::test();

  RunnerResult runparts = runner("struct", {}, "../build/test/test.json", provider);

  json spec = std::move(runparts.spec);
  auto runset = runparts.runset;


  TEST_SUITE("TEST_STRUCT") {

    TEST_CASE("test_minor_isnode") {
      runset(spec["minor"]["isnode"], isnode, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_ismap") {
      runset(spec["minor"]["ismap"], ismap, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_islist") {
      runset(spec["minor"]["islist"], islist, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_iskey") {
      runset(spec["minor"]["iskey"], iskey, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_isempty") {
      runset(spec["minor"]["isempty"], isempty, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_isfunc") {
      // resolve by (function_pointer)
      runset(spec["minor"]["isfunc"],
          static_cast<function_pointer>(isfunc<args_container&&>),
          { { "fixjson", false } }
      );
    }

    TEST_CASE("test_minor_getprop") {
      JsonFunction getprop_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        // std::cout << "json vin: " << vin << std::endl;
        // NOTE: operator[] is not good (isn't the best lookup) for auxiliary space since it creates an empty entry if the value is not found
        if(!vin.contains("alt")) {
          return getprop({
              vin.value("val", json(nullptr)),
              vin.value("key", json(nullptr))
          });
        } else {
          return getprop({
              vin.value("val", json(nullptr)), 
              vin.value("key", json(nullptr)),
              vin.value("alt", json(nullptr))
          });
        }
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["getprop"], getprop_wrapper, nullptr);
    }

    TEST_CASE("test_minor_keysof") {
      runset(spec["minor"]["keysof"], keysof, nullptr);
    }

    TEST_CASE("test_minor_haskey") {
      runset(spec["minor"]["haskey"], haskey, nullptr);
    }

    TEST_CASE("test_minor_items") {
      runset(spec["minor"]["items"], items, nullptr);
    }

    TEST_CASE("test_minor_escre") {
      runset(spec["minor"]["escre"], escre, nullptr);
    }

    TEST_CASE("test_minor_escurl") {
      runset(spec["minor"]["escurl"], escurl, nullptr);
    }

    TEST_CASE("test_minor_joinurl") {
      runset(spec["minor"]["joinurl"], joinurl, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_stringify") {
      JsonFunction stringify_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        // std::cout << "json vin: " << vin << std::endl;
        // NOTE: operator[] is not good (isn't the best lookup) for auxiliary space since it creates an empty entry if the value is not found
        if(!vin.contains("max")) {
          return stringify({
              vin.value("val", json(nullptr))
          });
        } else {
          return stringify({
              vin.value("val", json(nullptr)),
              vin.value("max", json(nullptr))
          });
        }
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["stringify"], stringify_wrapper, nullptr);
    }

    TEST_CASE("test_minor_clone") {
      runset(spec["minor"]["clone"], static_cast<function_pointer>(clone), nullptr);
    }

    TEST_CASE("test_minor_setprop") {
      JsonFunction setprop_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        return setprop({
            vin.value("parent", json(nullptr)),
            vin.value("key", json(nullptr)),
            vin.value("val", json(nullptr))
        });
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["setprop"], setprop_wrapper, nullptr);
    }


  }

  return 0;
}
