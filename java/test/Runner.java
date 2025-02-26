package org.example;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.io.IOException;
import java.util.Iterator;
import java.util.Map;
import java.util.HashMap;
import java.util.function.Function;

import org.json.*;

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
            JSONObject testspec_set = (JSONObject) func_args.testspec.get("set");
            Object testsubject = func_args.testsubject;

            Iterator<String> keys = testspec_set.keys();

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

            } catch (IOException e) {
                throw new RuntimeException(e);
            }

        }

    }
}

