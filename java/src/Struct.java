import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import java.io.*;

public class Struct {
    
    // String constants are explicitly defined.
    public static class S {
        public static final String MKEYPRE = "key:pre";
        public static final String MKEYPOST = "key:post";
        public static final String MVAL = "val";
        public static final String MKEY = "key";
        public static final String DKEY = "`$KEY`";
        public static final String DTOP = "$TOP";
        public static final String DERRS = "$ERRS";
        public static final String DMETA = "`$META`";
        public static final String ARRAY = "array";
        public static final String BASE = "base";
        public static final String BOOLEAN = "boolean";
        public static final String EMPTY = "";
        public static final String FUNCTION = "function";
        public static final String NUMBER = "number";
        public static final String OBJECT = "object";
        public static final String STRING = "string";
        public static final String KEY = "key";
        public static final String PARENT = "parent";
        public static final String BT = "`";
        public static final String DS = "$";
        public static final String DT = ".";
        public static final String KEY_NAME = "KEY";
    }
    
    @FunctionalInterface
    public interface WalkApply {
        Object apply(String key, Object val, Object parent, List<String> path);
    }
    
    @FunctionalInterface
    public interface WalkApplyOptional {
        Object apply(String key, Object val);
    }

    // Utility Methods
    public static boolean isNode(Object val) {
        return val instanceof Map || val instanceof List;
    }

    public static boolean isMap(Object val) {
        return val instanceof Map;
    }

    public static boolean isList(Object val) {
        return val instanceof List;
    }

    public static boolean isKey(Object key) {
        return (key instanceof String && !((String) key).isEmpty()) || key instanceof Integer;
    }

    public static boolean isEmpty(Object val) {
        return val == null ||
               (val instanceof String && ((String) val).isEmpty()) ||
               (val instanceof List && ((List<?>) val).isEmpty()) ||
               (val instanceof Map && ((Map<?, ?>) val).isEmpty());
    }

    public static boolean isFunc(Object val) {
        return val instanceof Runnable;
    }

    @SuppressWarnings("unchecked")
    public static List<Map.Entry<Object, Object>> items(Object val) {
    /*
        switch(val) {
          case Map _val -> {
            return new ArrayList<>(((Map<Object, Object>) _val).entrySet());
          }
          default -> Collections.emptyList();
        }
        */
        
        
        if (isMap(val)) {
            return new ArrayList<>(((Map<Object, Object>) val).entrySet());
        } else if (isList(val)) {
            List<?> list = (List<?>) val;
            List<Map.Entry<Object, Object>> result = new ArrayList<>();
            for (int i = 0; i < list.size(); i++) {
                result.add(new AbstractMap.SimpleEntry<>(i, list.get(i)));
            }
            return result;
        }
        return Collections.emptyList();
    }

    public static List<Object> keysof(Object val) {
        if (!isNode(val)) return Collections.emptyList();
        if (isMap(val)) return new ArrayList<>(((Map<?, ?>) val).keySet());
        if (isList(val)) return new ArrayList<>(
                Collections.nCopies(((List<?>) val).size(), 0)
        );
        return Collections.emptyList();
    }

    public static boolean hasKey(Object val, Object key) {
        return getProp(val, key, null) != null;
    }

    public static String stringify(Object val, Integer maxlen) {
        String json;
        try {
            json = Objects.toString(val, "");
        } catch (Exception e) {
            json = "";
        }
        json = json.replaceAll("\"", "");
        if (maxlen != null && maxlen < json.length()) {
            return json.substring(0, maxlen - 3) + "...";
        }
        return json;
    }

    public static Object clone(Object val) {
        if (val == null) return null;
        if (val instanceof Map) {
            Map<Object, Object> copy = new HashMap<>();
            ((Map<?, ?>) val).forEach((k, v) -> copy.put(k, clone(v)));
            return copy;
        } else if (val instanceof List) {
            List<Object> copy = new ArrayList<>();
            ((List<?>) val).forEach(v -> copy.add(clone(v)));
            return copy;
        }
        return val;
    }

    public static String escapeRegex(String s) {
        return s == null ? "" : Pattern.quote(s);
    }

    public static String escapeUrl(String s) throws UnsupportedEncodingException {
        return s == null ? "" : java.net.URLEncoder.encode(s, "UTF-8");
    }

    public static String joinUrl(String... parts) {
        return Arrays.stream(parts)
                .filter(Objects::nonNull)
                .map(s -> s.replaceAll("/+$", "").replaceAll("^/+", ""))
                .collect(Collectors.joining("/"));
    }

    @SuppressWarnings("unchecked")
    public static Object getProp(Object val, Object key, Object alt) {
        if (val instanceof Map && key instanceof String) {
            return ((Map<Object, Object>) val).getOrDefault(key, alt);
        } else if (val instanceof List && key instanceof Integer) {
            List<?> list = (List<?>) val;
            int index = (Integer) key;
            return (index >= 0 && index < list.size()) ? list.get(index) : alt;
        }
        return alt;
    }

    @SuppressWarnings("unchecked")
    public static <P> P setProp(P parent, Object key, Object val) {
        if (!isKey(key)) return parent;
        if (parent instanceof Map) {
            Map<Object, Object> map = (Map<Object, Object>) parent;
            if (val == null) {
                map.remove(key);
            } else {
                map.put(key, val);
            }
        } else if (parent instanceof List) {
            List<Object> list = (List<Object>) parent;
            int index = (Integer) key;
            if (index < 0) {
                list.add(0, val);
            } else if (index < list.size()) {
                list.set(index, val);
            } else {
                list.add(val);
            }
        }
        return parent;
    }
    
    // Walk function (Java version)
    public static Object walk(Object val, WalkApply apply, String key, Object parent, List<String> path) {
        // Default empty path if not provided
        path = path == null ? new ArrayList<>() : path;
        
        // If the value is a node (Map or List), recursively walk through it
        if (isNode(val)) {
            for (Map.Entry<Object, Object> entry : items(val)) {
                Object child = entry.getValue();
                String childKey = entry.getKey().toString();
                // Recursively walk and update the value at each step
                setProp(val, entry.getKey(), walk(child, apply, childKey, val, new ArrayList<>(path) {{
                    add(S.EMPTY + childKey);
                }}));
            }
        }
        
        // Apply the function to the current node, after processing its children
        return apply.apply(key, val, parent, path);
    }
    
    // Walk function (Java version)
    public static Object walk(Object val, WalkApplyOptional apply, String key) {
        
        // If the value is a node (Map or List), recursively walk through it
        if (isNode(val)) {
            for (Map.Entry<Object, Object> entry : items(val)) {
                Object child = entry.getValue();
                String childKey = entry.getKey().toString();
                // Recursively walk and update the value at each step
                setProp(val, entry.getKey(), walk(child, apply, childKey));
            }
        }
        
        // Apply the function to the current node, after processing its children
        return apply.apply(key, val);
    }
  public static Object merge(List<Object> objs) {
        Object out = null; // Equivalent to UNDEF in JS

        // Handle edge cases
        if (!isList(objs)) {
            out = objs;
        } else if (objs.isEmpty()) {
            out = null;
        } else if (objs.size() == 1) {
            out = objs.get(0);
        } else {
            out = getProp(objs, 0, new HashMap<>()); // Initialize with an empty map

            // Merge remaining down onto first
            for (int oI = 1; oI < objs.size(); oI++) {
                Object obj = objs.get(oI);

                if (!isNode(obj)) {
                    out = obj; // Non-node values override
                } else {
                    if (!isNode(out) || (isMap(obj) && isList(out)) || (isList(obj) && isMap(out))) {
                        out = obj; // Node type mismatch handling
                    } else {
                        // Node stack - traversing and merging
                        List<Object> cur = new ArrayList<>();
                        cur.add(out);
                        int cI = 0;

                        // Walk overriding node, creating paths in output as needed
                        walk(obj, (key, val, parent, path) -> {
                            if (key == null) {
                                return val; // Skip null keys
                            }

                            int lenPath = path.size();
                            cI = lenPath - 1;

                            // Get the current value at the path in out (not efficient, should optimize)
                            if (cur.get(cI) == null) {
                                cur.set(cI, getPath(path.subList(0, lenPath - 1), out));
                            }

                            // Create node if needed
                            if (!isNode(cur.get(cI))) {
                                cur.set(cI, isList(parent) ? new ArrayList<>() : new HashMap<>());
                            }

                            // If node child is just ahead on the stack
                            if (isNode(val) && !isEmpty(val)) {
                                setProp(cur.get(cI), key, cur.get(cI + 1));
                                cur.set(cI + 1, null);
                            } else {
                                setProp(cur.get(cI), key, val);
                            }

                            return val;
                        }, null, null, null);
                    }
                }
            }
        }

        return out;
    }

    
   public static void main(String[] args) {
        // Example usage with a sample Map
        Map<String, Object> sampleMap = new HashMap<>();
        sampleMap.put("key1", "value1");
        sampleMap.put("key2", new HashMap<>());
        
        walk(sampleMap, (key, val) -> {
            System.out.println("Walking key: " + key + ", value: " + val);
            return val;
        }, null);
        
        /*
        walk(sampleMap, (key, val, parent, path) -> {
            System.out.println("Walking key: " + key + ", value: " + val);
            return val;
        }, null, null, new ArrayList<>());
        */
        
    }
}

