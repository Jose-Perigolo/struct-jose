package org.example;

import java.lang.reflect.Array;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.io.IOException;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.function.Function;

import org.json.*;

import com.google.gson.Gson;
import com.google.gson.Gson.*;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import org.example.Struct;

public class Main {

    public static class RunnerResult {
        public JSONObject spec;
        public Function<RunSetArguments, Void> runset;
        public Object subject;
    }

    public static class RunSetArguments{
        public JSONObject testspec;
        public Object testsubject;

        public RunSetArguments(JSONObject testspec, Object testsubject) {
            this.testspec = testspec;
            this.testsubject = testsubject;
        }
    }

    public static RunnerResult runner(String name, Map<String, Object> store, String testfile, Provider provider) throws IOException {
        Client client = provider.test();
        Utility utility = client.utility();

        String fileContent = new String(Files.readAllBytes(Paths.get(testfile)));


        JSONObject alltests = new JSONObject(fileContent);

        System.out.println(alltests);

        JSONObject spec = alltests.has("primary") && ((JSONObject)alltests.get("primary")).has(name)
                ? (JSONObject) ((JSONObject)alltests.get("primary")).get(name)
                : alltests.has(name) ? (JSONObject) alltests.get(name) : alltests;

        Map<String, Client> clients = new HashMap<>();

        /*
        // TODO
        if (spec.has("DEF")) {
            for (Iterator<Map.Entry<String, JSONObject>> it = ((JSONObject)spec.get("DEF")).get("client"); it.hasNext(); ) {

                Map.Entry<String, JSONObject> cdef = it.next();

                JSONObject copts = cdef.getValue().has("test") && cdef.getValue().get("test").has("options")
                        ? cdef.getValue().get("test").get("options")
                        : new JSONObject();
                // TODO
                // if (store instanceof Map) {
                //    inject(copts, store);
                // }


                clients.put(cdef.getKey(), provider.test(copts));
            }
        }
        */

        Object subject = utility.get(name);

        Function<RunSetArguments, Void> runset = (func_args) -> {
            // System.out.println(func_args.testspec.getJSONArray("set"));

            JSONArray testspec_set = func_args.testspec.getJSONArray("set");
            Object testsubject = func_args.testsubject;

            // Iterator<String> keys = testspec_set.keys();
            for(int i = 0; i < testspec_set.length(); i++) {
                JSONObject entry = (JSONObject) testspec_set.get(i);

                Object entry_in = entry.get("in");

                // System.out.println(Struct.isNode(entry_in));
                switch(entry_in) {
                    case String s -> {
                        System.out.println(Struct.isNode(s));
                    }
                    case JSONArray arr -> {
                        System.out.println(Struct.isNode(arr.toList()));
                    }
                    case JSONObject obj -> {
                        System.out.println(Struct.isNode(obj.toMap()));
                    }
                    case Integer integer -> {
                        System.out.println(Struct.isNode(integer));
                    }
                    case Boolean bool -> {
                        System.out.println(Struct.isNode(bool));
                    }
                    default -> {
                        throw new AssertionError("Unknown entry in " + entry_in.getClass());
                    }
                }



                /*

                switch(entry_in) {
                    case String s -> System.out.println("String: '" + s + "'");
                    case JSONArray arr -> System.out.println("JSONArray: '" + arr.toList() + "'");
                    case JSONObject obj -> System.out.println("JSONObject: '" + obj.toMap() + "'");
                    default -> {
                        System.out.println("Unknown entry: " + entry_in.getClass());
                    }
                }
                 */

                /*
                System.out.println("entry: " + entry);
                System.out.println("entry_in: " + entry_in);

                 */



            }

            /*
            for (Iterator<String> it = keys; it.hasNext(); ) {
                String key = it.next();

                JSONObject entry = (JSONObject) testspec_set.get(key);

                try {
                    Client testclient = client;


                    if (entry.has("client")) {
                        testclient = clients.get(entry.get("client").toString());
                        testsubject = testclient.utility().get(name);
                    }

                    JSONObject args = (JSONObject) (entry.has("args") ? entry.get("args") : entry.get("in"));

                    if (entry.has("ctx")) {
                        args = (JSONObject) entry.get("ctx");
                    }

                    Object res = invokeTestSubject(testsubject, args);
                    entry.put("res", (JSONObject)res);

                    if (!entry.has("match") || entry.has("out")) {
                        // TODO
                        // assertEquals(objectMapper.valueToTree(entry.get("out")), objectMapper.valueToTree(res));
                    }
                } catch (Exception e) {
                    throw new AssertionError("Test failed: " + e.getMessage());
                }
            }
             */
            return null;
        };

        RunnerResult result = new RunnerResult();
        result.spec = spec;
        result.runset = runset;
        result.subject = subject;

        return result;
    }

    private static Object invokeTestSubject(Object testsubject, JSONObject args) {
        // Implement function invocation logic
        return null;
    }

    private static void inject(JSONObject target, Map<String, Object> store) {
        // Implement injection logic
    }

    public static class Provider {
        public Client test() {

            return new Client();
        }
        public Client test(JSONObject options) {
            return null;
        }
    }

    public static class Client {
        Utility utility() {
            return new Utility();
        }
    }

    public static class Utility {
        Object get(String name) {
            return null;
        }
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws IOException {

        {

            System.out.println("Running test");
        }

        {
            Map<String, Object> store = new HashMap<>();

            try {
                RunnerResult runner_result = runner("struct", store, "/home/alex/Project/struct/build/test/test.json", new Provider());

                JSONObject spec = runner_result.spec;
                JSONObject minor = (JSONObject) spec.get("minor");
                JSONObject isnode = (JSONObject) minor.get("isnode");

                Object testsubject = null;

                runner_result.runset.apply(new RunSetArguments(isnode, testsubject));

                {
                    String jsonString = "{ \"name\": \"Alice\", \"age\": 25 }";

//                    jsonString = "[]";
//                    jsonString = "1";
//                    jsonString = "a";


                    Gson gson = new Gson();

                    // Parse JSON string
                    JsonElement jsonElement = JsonParser.parseString(jsonString);
                    Object obj = gson.fromJson(jsonElement, Object.class);

                    System.out.println(Struct.isNode(obj));

                    switch(obj) {
                        case Map map -> {
                            System.out.println("Java Map: " + map.toString());
                            break;
                        }
                        case List list -> {
                            System.out.println("Java List: " + list.toString());
                            break;
                        }
                        case Double _double -> {
                            System.out.println("Java Double: " + _double.toString());
                            break;
                        }
                        case String string -> {
                            System.out.println("Java String: " + string);
                            break;
                        }
                        default -> {
                            System.out.println("Unmatched: " + obj.getClass());
                        }
                    }

                    /*
                    switch(jsonElement) {
                        case JsonObject obj-> {
                            System.out.println(obj.toString());
                            break;
                        }
                        default -> {
                            break;
                        }
                    }
                     */
                }

            } catch (IOException e) {
                throw new RuntimeException(e);
            }

        }

    }
}

