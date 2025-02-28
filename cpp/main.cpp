#include <iostream>
#include <fstream>

#include <nlohmann/json.hpp>



using json = nlohmann::json;

using arg_container = std::vector<json>;

// TODO: Consider: Function Pointers

// NOTE: polymorphic
class Obj {
  public:
    Obj() = default;

    virtual json apply(arg_container&& args) = 0;
};

#define _exception(message) message


class isList : public Obj {

  public:
    virtual json apply(arg_container&& args) {

      if(args.size() == 0) {
        throw _exception("1 arguments expected");
      }

      json obj = std::move(args[0]);

      return static_cast<bool>(obj.is_array());
    }
};

class isNode : public Obj {
  public:
    virtual json apply(arg_container&& args) {

      if(args.size() == 0) {
        throw _exception("1 arguments expected");
      }
      
      json obj = std::move(args[0]);

      return static_cast<bool>(obj.is_array() || obj.is_object());
    } 

};

struct Struct {
  Obj* islist;
  Obj* isnode;
  Obj* isbool;

  ~Struct() {
    if(islist != nullptr) {
      delete islist;
    }

    if(isnode != nullptr) {
      delete isnode;
    }

    if(isbool != nullptr) {
      delete isbool;
    }

  }

};

// NOTE: struct for now
struct Utility {
  Struct _struct;
};

class Provider {

  public:
    Provider() = default;

    Utility utility() {

      return Utility{
        Struct{
          new isList(),
          new isNode()
        }
      };

    }
};

class RunnerResult {
  public:
    RunnerResult() = default;
};

RunnerResult runner(const std::string& name, const json& store, const char* testfile, Provider&& provider) {
  return RunnerResult();
}

int main() {

  {

    std::ifstream f("../build/test/test.json");
    json alltests = json::parse(f);

    std::cout << "spec: " << alltests["minor"]["isnode"] << std::endl;

  }


  {
    Struct _struct {new isList()};

    std::cout << _struct.islist->apply({ 1 }) << std::endl;
    std::cout << _struct.islist->apply({ json::array() }) << std::endl;
    std::cout << _struct.islist->apply({ json::object() }) << std::endl;

  }



  json ex1 = json::parse(R"(
{
  "happy": true,
  "pi": 2
}
  )");

  json j2 = {
    {"pi", 3.141},
    {"happy", true},
    {"name", "Niels"},
    {"nothing", nullptr},
    {"answer", {
                 {"everything", 42}
               }},
    {"list", {1, 0, 2}},
    {"object", {
                 {"currency", "USD"},
                 {"value", 42.99}
               }}
  };

// Using initializer lists
json ex3 = {
  {"happy", true},
  {"pi", 3.141},
};

json happy = ex1.at("happy");


json list1 = json::parse("[ 1, \"a\"]");
const json& list2 = list1;

std::vector<json> vec1;

if(list1.is_array()) {
  for(json::iterator it = list1.begin(); it != list1.end(); ++it) {
    vec1.push_back(it.value());
  }
}


std::cout << ex1.dump(2) << std::endl;
std::cout << happy << std::endl;
std::cout << ex1.is_object() << std::endl;

for(size_t i = 0; i < vec1.size(); i++) {
  std::cout << "vec[i]: " << vec1[i] << std::endl;
}

// Deep Copy
{
  json obj1 = json::parse("{\"a\": {\"1\": \"2\" }}");
  json obj2 = obj1;

  obj1["a"]["1"] = 3;


  std::cout << obj1.dump(2) << std::endl;
  std::cout << obj2.dump(2) << std::endl;
}

return 0;
}
