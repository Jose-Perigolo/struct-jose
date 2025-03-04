#include <iostream>
#include <fstream>

#include <nlohmann/json.hpp>

#include <voxgig_struct.hpp>
#include <runner.hpp>


#define TEST_CASE(TEST_NAME) std::cout << "Running: " << TEST_NAME << " at " << __LINE__ << std::endl;

#define TEST_STRUCT std::cout << "TEST STRUCT " << " at " << __LINE__ << std::endl;


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
        { "islist", islist },
        { "isnode", isnode },
        { "ismap",  ismap  }
    });
  }

  function_pointer& operator[](const std::string& key) {
    return get_key(key);
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


  TEST_STRUCT {

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
      runset(spec["minor"]["isfunc"], (function_pointer)isfunc<args_container&&>, { { "fixjson", false } });
    }

    TEST_CASE("test_minor_getprop") {
      JsonFunction getprop_wrapper = [](args_container&& args) -> json {
        json& vin = args[0];
        // std::cout << "json vin: " << vin << std::endl;
        if(!vin.contains("alt")) {
          return getprop({ vin["val"], vin["key"]});
        } else {
          return getprop({ vin["val"], vin["key"], vin["alt"]});
        }
      };

      // TODO: Use nullptr for now since we can't have std::function with optional arguments. Instead, we need to rewrite the entire class to implement our own closure and "operator()"
      runset(spec["minor"]["getprop"], getprop_wrapper, nullptr);
    }

  }

  return 0;
}
