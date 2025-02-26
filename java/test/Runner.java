import java.nio.file.Files;
import java.nio.file.Paths;
import java.io.IOException;
import java.util.Map;
import java.util.HashMap;
import java.util.function.Function;

import org.json.*;

public class Main {

    // Utility Class and its methods
    public static class Utility {
        public Struct struct;

        public Utility() {
            this.struct = new Struct();
        }

        public class Struct {
            public Clone clone = new Clone();
            public Escr escr = new Escr();
            public Escurl escurl = new Escurl();
            public Getpath getpath = new Getpath();
            public Getprop getprop = new Getprop();
            public Inject inject = new Inject();
            public IsEmpty isempty = new IsEmpty();
            public IsKey iskey = new IsKey();
            public IsList islist = new IsList();
            public IsMap ismap = new IsMap();
            public IsNode isnode = new IsNode();
            public Items items = new Items();
            public HasKey haskey = new HasKey();
            public Keysof keysof = new Keysof();
            public Merge merge = new Merge();
            public Setprop setprop = new Setprop();
            public Stringify stringify = new Stringify();
            public Transform transform = new Transform();
            public Walk walk = new Walk();
            public Validate validate = new Validate();
            public Joinurl joinurl = new Joinurl();
        }

        // Sample Methods for Utility struct classes
        public class Clone {
            public JSONObject clone(JSONObject obj) {
                return new JSONObject(obj.toString());
            }
        }

        public class Escr {
            public String escre(String input) {
                return input != null ? input : "";
            }
        }

        public class Escurl {
            public String escurl(String url) {
                return url != null ? url : "";
            }
        }

        public class Getpath {
            public Object getpath(String path, Map<String, Object> base) {
                return base.get(path);
            }
        }

        public class Getprop {
            public Object getprop(String prop, Map<String, Object> base) {
                return base.get(prop);
            }
        }

        public class Inject {
            public void inject(Map<String, Object> options, JSONObject store) {
                // Implement injection logic here
            }
        }

        public class IsEmpty {
            public boolean isempty(Object obj) {
                return obj == null || obj.toString().trim().isEmpty();
            }
        }

        public class IsKey {
            public boolean iskey(Object key, Map<String, Object> map) {
                return map.containsKey(key);
            }
        }

        public class IsList {
            public boolean islist(Object obj) {
                return obj instanceof JSONArray;
            }
        }

        public class IsMap {

            public boolean ismap(Object obj) {
                return obj instanceof Map;
            }
        }

        public class IsNode {
            public boolean isnode(Object obj) {
                return obj instanceof Map;
            }
        }

        public class Items {
            public Iterable<Map.Entry<String, Object>> items(JSONObject json) {
                return json.toMap().entrySet();
            }
        }

        public class HasKey {
            public boolean haskey(Object key, Map<String, Object> map) {
                return map.containsKey(key);
            }
        }

        public class Keysof {
            public JSONArray keysof(Map<String, Object> map) {
                return new JSONArray(map.keySet());
            }
        }

        public class Merge {
            public Map<String, Object> merge(Map<String, Object> first, Map<String, Object> second) {
                Map<String, Object> merged = new HashMap<>(first);
                merged.putAll(second);
                return merged;
            }
        }

        public class Setprop {
            public void setprop(Map<String, Object> map, String key, Object value) {
                map.put(key, value);
            }
        }

        public class Stringify {
            public String stringify(Object obj) {
                return obj != null ? obj.toString() : null;
            }
        }

        public class Transform {
            public Object transform(Object input) {
                return input;
            }
        }

        public class Walk {
            public void walk(Object check, WalkFunction func) {
                // Walk and apply the function to each element
            }
        }

        public class Validate {
            public boolean validate(Object obj) {
                return obj != null;
            }
        }

        public class Joinurl {
            public String joinurl(String base, String relative) {
                return base + "/" + relative;
            }
        }

        public interface WalkFunction {
            void apply(String key, Object value, Object parent, String path);
        }
    }

    // Test Class that mimics the provider.test() behavior
    public static class Test {
        public Utility utility() {
            return new Utility();
        }
    }

    // Provider Class to provide an instance of Test
    public static class Provider {
        public Test test() {
            return new Test();
        }
    }

    /*
    public static boolean isMap(Object val) {
        return val instanceof Map;
    }
    */

    public static Map<String, Object> runner(String name, JSONObject store, String testfile, Provider provider) throws IOException {
        Test client = provider.test();
        Utility utility = client.utility();
        Utility.Struct utilStruct = utility.struct;

        // Read the test file
        String fileContent = new String(Files.readAllBytes(Paths.get(testfile)));
        JSONObject alltests = new JSONObject(fileContent);

        System.out.println("fileContent: ");
        System.out.println(((JSONObject)alltests.get("transform")));


        // Fetch the specific test spec
        JSONObject spec = alltests.optJSONObject("primary") != null ? alltests.getJSONObject("primary").optJSONObject(name) : alltests.optJSONObject(name);
        if (spec == null) {
            spec = alltests;
        }

        Map<String, Test> clients = new HashMap<>();
        if (spec.has("DEF")) {
            JSONArray clientDefs = spec.getJSONArray("DEF").getJSONArray(0);
            for (int i = 0; i < clientDefs.length(); i++) {
                JSONObject cdef = clientDefs.getJSONObject(i);
                Map<String, Object> copts = cdef.optJSONObject("test").optJSONObject("options").toMap();
                if (utility.struct.ismap.ismap(store)) {
                    utility.struct.inject.inject(copts, store);
                }
                clients.put(cdef.getString("client"), provider.test());
            }
        }

        // Run the tests
        runset((JSONObject) ((JSONObject) spec.get("minor")).get("ismap"), utility, clients, client, utility);

        return Map.of("spec", spec, "runset", new Object(), "subject", utility);
    }

    public static void runset(JSONObject testspec, Utility testsubject, Map<String, Test> clients, Test client, Utility utilityInstance) {
        System.out.println("testspec: ");
        System.out.println(testspec);

        for (Object entryObj : testspec.getJSONArray("set")) {
            JSONObject entry = (JSONObject) entryObj;
            try {
                Test testclient = client;

                if (entry.has("client")) {
                    testclient = clients.get(entry.getString("client"));
                    // Set appropriate testsubject if necessary
                }

                // Arguments setup
                JSONArray args = new JSONArray();
                if (entry.has("ctx")) {
                    args.put(entry.get("ctx"));
                } else if (entry.has("args")) {
                    args.put(entry.get("args"));
                }

                // Process test subject
                JSONObject res = new JSONObject(); // Placeholder for test results
                if (entry.isNull("match") || !entry.isNull("out")) {
                    // Perform deep equality check
                    System.out.println("entry: " + entry);
                    System.out.println("res: " + res);
                    // System.out.println(entry);

                    if (!entry.get("out").equals(res)) {
                        throw new AssertionError("Test failed");
                    }
                }

                // Match check logic (Implement match logic here)
                if (entry.has("match")) {
                    match((JSONObject) entry.get("match"), entry);
                }

            } catch (Exception err) {
                // Handle errors (e.g., throw an exception or log failure)
                throw new RuntimeException("Test error", err);
            }
        }
    }

    public static void match(JSONObject check, JSONObject base) {
        // Walk and match check with base
    }

    public static boolean matchval(Object check, Object base) {
        // Implement matching logic here
        return check.equals(base);
    }

    public static void main(String[] args) {

        JSONObject myobj = new JSONObject("{\"a\": 1, 1: 3}");
        Object obj = myobj;

        Object mynum = myobj.get("a");

        System.out.println("my obj: " + myobj);
        System.out.println("obj: " + (JSONObject)(myobj));

        switch (mynum) {
            case Integer i -> System.out.println("NUM obj: " + mynum);
            default -> {
                break;
            }
        }


        // Example usage
        try {
            Provider provider = new Provider();
            JSONObject store = new JSONObject(); // Pass in store data
            runner("struct", store, "/home/alex/Project/struct/build/test/test.json", provider);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}

