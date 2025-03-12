
#ifndef RUNNER_H

#define RUNNER_H

#define FOR(entry, OBJ) for(json::iterator entry = OBJ.begin(); entry != OBJ.end(); ++entry)

json fixJSON(const json&);
json unfixJSON(const json&); // UNUSED

struct RunnerResult {
  using Function = std::function<void(const json&, JsonFunction, json&&)>;

  json spec;
  Function runset;
  // TODO: TBD: function_pointer subject

  RunnerResult() = default;

  RunnerResult(json&& spec, Function&& runset) : runset{std::move(runset)} {
    // NOTE: NEVER DO spec{...} in the constructor - it will treat it as an json::array. e.g. evaluates to [spec]
    this->spec = std::move(spec);
  }
};


class assertion_error : public std::exception {
  public:
    assertion_error() = default;
    assertion_error(const std::string& message) : message{message} {}

    const char* what() const noexcept override {
      return message.c_str();
    }
  private:
    std::string message;

};

RunnerResult runner(const std::string& name, const json& store, const std::string& testfile, const Provider& provider) {

  using hash_utility = hash_table<std::string, Utility>;

  Provider client = provider.test();

  hash_utility utility = client.utility();

  Utility _struct = utility["struct"];

  function_pointer items = _struct["items"];
  function_pointer stringify = _struct["stringify"];


  // Read and parse the test JSON file
  std::ifstream f(testfile);

  json alltests = json::parse(f);

  json spec;

  // TODO: Copy by reference the first two conditons
  // Attempt to find the requested spec in the JSON
  if(alltests.contains("primary") && alltests["primary"].contains(name)) {
    spec = alltests["primary"][name];
  }
  else if(alltests.contains(name)) {
    spec = alltests[name];
  } else {
    spec = std::move(alltests);
  }

  // std::cout << "spec DEF: " << (spec["DEF"]) << std::endl;
  /*
  // TODO
  hash_table<std::string, Provider> clients;

# Build up any additional clients from a DEF section, if present
clients = {}
if 'DEF' in spec and 'client' in spec['DEF']:
for c_name, c_val in items(spec['DEF']['client']):
copts = c_val.get('test', {}).get('options', {})
if isinstance(store, dict):
inject(copts, store)
clients[c_name] = provider.test(copts)

   */

  // TODO
  // auto subject = utility[name];

  // NOTE: Use std::function (instead of function_pointer) in case lambdas are being passed
  auto runset = [=](const json& testspec, JsonFunction testsubject = nullptr, json&& flags = nullptr){

    if(flags == nullptr) {
      flags = json::object();
    }

    // JS: flags["fixjson"] = flags["fixjson"] || true
    flags["fixjson"] = flags.value("fixjson", true);

    /*
    // TODO
    if(testsubject == nullptr) {
    testsubject = subject;
    }
     */


    json set = testspec.value("set", json::array());

    FOR(entry, set) {
      try {
        if(!entry->contains("out")) {
          (*entry)["out"] = nullptr; // OR: entry->at("out") = nullptr;
        }

        if(flags["fixjson"] == true) {
          *entry = fixJSON(*entry);
        }

        Provider testclient = client;
        // TODO
        /*
# If a particular entry wants to use a different client:
if 'client' in entry:
testclient = clients[entry['client']]
testsubject = testclient.utility()[name]
         */

        json args = json::array();

        // TODO: Refactor double lookup
        // Build up the call arguments
        if(entry->contains("ctx")) {
          args = json::array({ (*entry)["ctx"] });
        } else if(entry->contains("args") && entry->at("args").is_array()) {
          args = (*entry)["args"];
        } else {
          if(entry->contains("in")) {
            // TODO: Ensure clone since it is cloning by default this way
            // args = [clone(entry['in'])] if 'in' in entry else []
            args = json::array({ (*entry)["in"] });
          } else {
            args = json::array();
          }
        }

        if(entry->contains("ctx") || entry->contains("args")) {
          json first_arg;

         if(args.is_null() || args.size() == 0) {
           first_arg = nullptr;
         } 

         if(first_arg.is_object()) {

           // TODO: first_arg = clone(first_arg)
         
           args[0] = first_arg;
           (*entry)["ctx"] = first_arg;

           if(first_arg.is_object()) {
             // first_arg["client"] = testclient;
           }
         
         }

        }

        /*
        // TODO
# If we have a context or arguments, we might need to patch them:
if 'ctx' in entry or 'args' in entry:
first_arg = None if args is None or 0 == len(args) else args[0]
if isinstance(first_arg, dict):
# Deep clone first_arg
first_arg = clone(first_arg)
args[0] = first_arg
entry['ctx'] = first_arg

if isinstance(first_arg, dict):
first_arg["client"] = testclient
first_arg["utility"] = testclient.utility()
         */

        // std::cout << "json::args: " << args << std::endl;

        json res;

        if(args.is_array()) {
          res = testsubject(
            std::move(args.get<std::vector<json>>())
          );
        } else {
          res = testsubject({ std::move(args) });
        }

        res = fixJSON(res);


        // NOTE: COPY ENFORCED
        (*entry)["res"] = res;

        if(!entry->contains("match") || entry->contains("out")) {
          /*
          // TODO:
# Remove functions/etc. by JSON round trip
cleaned_res = json.loads(json.dumps(res, default=str))
           */
          json cleaned_res = res;
          json expected_out = entry->at("out");

          // cleaned_res = false;
          // cleaned_res[0];
          // std::cout << "CHECK: " << (cleaned_res == expected_out) << std::endl;
          // std::cout << cleaned_res << std::endl;
          // std::cout << expected_out << std::endl;

          if(cleaned_res != expected_out) {
            throw assertion_error(
                "Expected " + expected_out.dump() + " got " + cleaned_res.dump() + "\n" +
                "Entry: " + entry->dump(2));
          }

        }

        // TODO
        /*
# If we also need to do "match" checks
if 'match' in entry:
match(entry['match'], {
'in': entry.get('in'),
'out': entry.get('res'),
'ctx': entry.get('ctx')
})
         */



} /* catch(const assertion_error& err) {
     std::cout << err.what() << std::endl; } */
catch(const std::exception& err) {

  (*entry)["thrown"] = err.what();
  json entry_err = entry->value("err", json(nullptr));

  if(entry_err != nullptr) {
    // TODO: if entry_err is True or matchval(entry_err, str(err))
    if(entry_err == true) {
      // TODO
      /*
         if 'match' in entry:
         match(entry['match'], {
         'in': entry.get('in'),
         'out': entry.get('res'),
         'ctx': entry.get('ctx'),
         'err': str(err)
         })
       */

      continue;
    } else {
      // TODO
      /*
         raise AssertionError_(
         f"ERROR MATCH: [{stringify(entry_err)}] <=> [{str(err)}]\n"
         f"Entry: {json.dumps(entry, indent=2)}"
         )
       */
    }


  } else {
    throw assertion_error(
        std::string(err.what()) + "\n\nENTRY: " + entry->dump(2));
  }

}

}

};




RunnerResult out = RunnerResult(
    std::move(spec), 
    std::move(runset));

return out;

}

json fixJSON(const json& obj) {
  if(obj.is_null()) {
    return "__NULL__";
  } else if(obj.is_array()) {
    json arr = json::array();
    for(json::const_iterator item = obj.begin(); item != obj.end(); item++) {
      arr.push_back(
          fixJSON(item.value()));
    }
    return arr;
  } else if(obj.is_object()) {
    json _obj = json::object();
    for(json::const_iterator item = obj.begin(); item != obj.end(); item++) {
      _obj[item.key()] = fixJSON(item.value());
    }
    return _obj;
  } else {
    return obj;
  }

}



/*
   json unfixJSON(const json& obj) {
   return obj;
   }
 */
// TODO
/*
   def unfixJSON(obj):
   if "__NULL__" == obj:
   return None
   elif isinstance(obj, list):
   return [unfixJSON(item) for item in obj]
   elif isinstance(obj, dict):
   return {k: unfixJSON(v) for k, v in obj.items()}
else:
return obj
 */


#endif
