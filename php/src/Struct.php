<?php
declare(strict_types=1);

namespace Voxgig\Struct;

/**
 * Class Struct
 *
 * Utility class for manipulating in-memory JSON-like data structures.
 * These utilities implement functions similar to the TypeScript version,
 * with emphasis on handling nodes, maps, lists, and special "undefined" values.
 */
class Struct
{

    /* =======================
     * String Constants
     * =======================
     */
    private const S_MKEYPRE = 'key:pre';
    private const S_MKEYPOST = 'key:post';
    private const S_MVAL = 'val';
    private const S_MKEY = 'key';

    private const S_DKEY = '`$KEY`';
    private const S_DMETA = '`$META`';
    private const S_DTOP = '$TOP';
    private const S_DERRS = '$ERRS';
    private const S_ERRS = '$ERRS';

    private const S_array = 'array';
    private const S_boolean = 'boolean';
    private const S_function = 'function';
    private const S_number = 'number';
    private const S_object = 'object';
    private const S_string = 'string';
    private const S_null = 'null';
    private const S_MT = '';
    private const S_BT = '`';
    private const S_DS = '$';
    private const S_DT = '.';
    private const S_CN = ':';
    private const S_KEY = 'KEY';
    public const S_BASE = 'base';

    /**
     * Standard undefined value represented by a unique string marker.
     *
     * NOTE: This marker should be chosen to minimize collision with real data.
     */
    public const UNDEF = '__UNDEFINED__';

    /* =======================
     * Private Helpers
     * =======================
     */

    /**
     * Determines whether an array has sequential integer keys, i.e. a list.
     *
     * @param array $val
     * @return bool True if the array is a list (i.e. sequential keys starting at 0).
     */
    private static function isListHelper(array $val): bool
    {
        return array_keys($val) === range(0, count($val) - 1);
    }

    /* =======================
     * Type and Existence Checks
     * =======================
     */

    public static function isnode(mixed $val): bool
    {
        // We don’t consider null or the undef‐marker to be a node.
        if ($val === self::UNDEF || $val === null) {
            return false;
        }
        // Any PHP object *or* any PHP array is a node (map or list).
        return is_object($val) || is_array($val);
    }



    /**
     * Check if a value is a map (associative array or object) rather than a list.
     *
     * @param mixed $val
     * @return bool
     */
    public static function ismap(mixed $val): bool
    {
        // Any PHP object (stdClass, etc.) is a map
        if (is_object($val)) {
            return true;
        }
        // Any PHP array that isn’t a list is a map,
        // but treat *empty* arrays as lists (not maps).
        if (is_array($val)) {
            if (count($val) === 0) {
                return false;
            }
            return !self::islist($val);
        }
        return false;
    }



    /**
     * Check if a value is a list (sequential array).
     *
     * @param mixed $val
     * @return bool
     */
    public static function islist(mixed $val): bool
    {
        if (!is_array($val)) {
            return false;
        }
        $i = 0;
        foreach ($val as $k => $_) {
            if ($k !== $i++) {
                return false;
            }
        }
        return true;
    }

    /**
     * Check if a key is valid (non-empty string or integer/float).
     *
     * @param mixed $key
     * @return bool
     */
    public static function iskey(mixed $key): bool
    {
        if ($key === self::UNDEF) { // Explicit check for UNDEF
            return false;
        }
        if (is_string($key)) {
            return strlen($key) > 0;
        }
        return is_int($key) || is_float($key);
    }
    /**
     * Check if a value is empty.
     * Considers undefined, null, empty string, empty array, or empty object.
     *
     * @param mixed $val
     * @return bool
     */
    public static function isempty(mixed $val): bool
    {
        if ($val === self::UNDEF || $val === null || $val === self::S_MT) {
            return true;
        }
        if (is_array($val) && count($val) === 0) {
            return true;
        }
        if (is_object($val) && count(get_object_vars($val)) === 0) {
            return true;
        }
        return false;
    }

    /**
     * Check if a value is callable.
     *
     * @param mixed $val
     * @return bool
     */
    public static function isfunc(mixed $val): bool
    {
        return is_callable($val);
    }

    /**
     * Normalize and return a type string for a given value.
     * Possible return values include 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'.
     *
     * @param mixed $value
     * @return string
     */
    public static function typify(mixed $value): string
    {
        if ($value === null || $value === self::UNDEF) {
            return self::S_null;
        }
        if (is_array($value)) {
            // If the array keys are sequential, it's a list.
            if (self::isListHelper($value)) {
                return self::S_array;
            } else {
                return self::S_object;
            }
        }
        if (is_object($value)) {
            return self::S_object;
        }
        if (is_int($value) || is_float($value)) {
            return self::S_number;
        }
        if (is_string($value)) {
            return self::S_string;
        }
        if (is_bool($value)) {
            return self::S_boolean;
        }
        if (is_callable($value)) {
            return self::S_function;
        }
        return gettype($value);
    }

    public static function getprop(mixed $val, mixed $key, mixed $alt = self::UNDEF): mixed
    {
        // 1) undefined‐marker or invalid key → alt
        if ($val === self::UNDEF || $key === self::UNDEF) {
            return $alt;
        }
        if (!self::iskey($key)) {
            return $alt;
        }
        if ($val === null) {
            return $alt;
        }

        // 2) array branch stays the same
        if (is_array($val) && array_key_exists($key, $val)) {
            $out = $val[$key];
        }
        // 3) object branch: cast $key to string
        elseif (is_object($val)) {
            $prop = (string) $key;
            if (property_exists($val, $prop)) {
                $out = $val->$prop;
            } else {
                $out = $alt;
            }
        }
        // 4) fallback
        else {
            $out = $alt;
        }

        // 5) JSON‐null‐marker check
        return ($out === self::UNDEF ? $alt : $out);
    }


    public static function strkey(mixed $key = self::UNDEF): string
    {
        if ($key === self::UNDEF) {
            return self::S_MT;
        }
        if (is_string($key)) {
            return $key;
        }
        if (is_bool($key)) {
            return self::S_MT;
        }
        if (is_int($key)) {
            return (string) $key;
        }
        if (is_float($key)) {
            return (string) floor($key);
        }
        return self::S_MT;
    }

    /**
     * Get a sorted list of keys from a node (map or list).
     *
     * @param mixed $val
     * @return array
     */
    public static function keysof(mixed $val): array
    {
        if (!self::isnode($val)) {
            return [];
        }
        if (self::ismap($val)) {
            $keys = is_array($val) ? array_keys($val) : array_keys(get_object_vars($val));
            sort($keys, SORT_STRING);
            return $keys;
        } elseif (self::islist($val)) {
            $keys = array_keys($val);
            return array_map('strval', $keys);
        }
        return [];
    }

    /**
     * Determine if a node has a defined property with the given key.
     *
     * @param mixed $val
     * @param mixed $key
     * @return bool
     */
    public static function haskey(mixed $val = self::UNDEF, mixed $key = self::UNDEF): bool
    {
        // 1. Validate $val is a node
        if (!self::isnode($val)) {
            return false;
        }

        // 2. Validate $key is a valid key
        if (!self::iskey($key)) {
            return false;
        }

        // 3. Check property existence
        $marker = new \stdClass();
        return self::getprop($val, $key, $marker) !== $marker;
    }

    public static function items(mixed $val): array
    {
        $result = [];
        if (self::islist($val)) {
            foreach ($val as $k => $v) {
                $result[] = [$k, $v];
            }
        } else {
            foreach (self::keysof($val) as $k) {
                $result[] = [$k, self::getprop($val, $k)];
            }
        }
        return $result;
    }

    public static function escre(?string $s): string
    {
        $s = $s ?? self::S_MT;
        return preg_quote($s, '/');
    }

    public static function escurl(?string $s): string
    {
        $s = $s ?? self::S_MT;
        return rawurlencode($s);
    }

    public static function joinurl(array $sarr): string
    {
        $parts = [];
        foreach ($sarr as $i => $s) {
            if ($s === null || $s === self::S_MT) {
                continue;
            }
            if ($i === 0) {
                $s = preg_replace("/\/+$/", "", $s);
            } else {
                $s = preg_replace("/([^\/])\/+/", "$1/", $s);
                $s = preg_replace("/^\/+/", "", $s);
                $s = preg_replace("/\/+$/", "", $s);
            }
            if ($s !== self::S_MT) {
                $parts[] = $s;
            }
        }
        return implode('/', $parts);
    }

    /* =======================
     * Stringification and Cloning
     * =======================
     */

    /**
     * Recursively sorts a node (array or object) to ensure consistent stringification.
     *
     * @param mixed $val
     * @return mixed
     */
    private static function sort_obj(mixed $val): mixed
    {
        if (is_array($val)) {
            if (self::islist($val)) {
                return array_map([self::class, 'sort_obj'], $val);
            } else {
                ksort($val);
                foreach ($val as $k => $v) {
                    $val[$k] = self::sort_obj($v);
                }
                return $val;
            }
        } elseif (is_object($val)) {
            $arr = get_object_vars($val);
            ksort($arr);
            foreach ($arr as $k => $v) {
                $arr[$k] = self::sort_obj($v);
            }
            return $arr;
        }
        return $val;
    }

    public static function stringify(mixed $val, ?int $maxlen = null): string
    {
        if ($val === self::UNDEF) {
            return self::S_MT;
        }

        $original = $val;            // save for later
        try {
            $sorted = self::sort_obj($val);
            $str = json_encode($sorted);
        } catch (\Exception $e) {
            $str = self::S_MT . (string) $val;
        }

        if (!is_string($str)) {
            $str = self::S_MT . $str;
        }
        // strip quotes
        $str = str_replace('"', '', $str);

        // **NEW**: if it was actually an object but came out as [], flip to {}
        if (is_object($original) && $str === '[]') {
            $str = '{}';
        }

        if (null !== $maxlen && strlen($str) > $maxlen) {
            $str = substr($str, 0, $maxlen - 3) . '...';
        }
        return $str;
    }

    public static function pathify(mixed $val, ?int $startin = null, ?int $endin = null): string
    {
        $UNDEF = self::UNDEF;
        $S_MT = self::S_MT;
        $S_CN = self::S_CN;
        $S_DT = self::S_DT;

        if (is_array($val) && (self::islist($val) || count($val) === 0)) {
            $path = $val;
        } elseif (is_string($val) || is_int($val) || is_float($val)) {
            $path = [$val];
        } else {
            $path = $UNDEF;
        }

        $start = ($startin === null || $startin < 0) ? 0 : $startin;
        $end = ($endin === null || $endin < 0) ? 0 : $endin;

        $pathstr = $UNDEF;

        if ($path !== $UNDEF && $start >= 0) {
            $len = count($path);
            $length = max(0, $len - $end - $start);
            $slice = array_slice($path, $start, $length);

            if (count($slice) === 0) {
                $pathstr = '<root>';
            } else {
                $parts = [];
                foreach ($slice as $p) {
                    if (!self::iskey($p)) {
                        continue;
                    }
                    if (is_int($p) || is_float($p)) {
                        $parts[] = $S_MT . (string) floor($p);
                    } else {
                        $parts[] = str_replace('.', $S_MT, (string) $p);
                    }
                }
                $pathstr = implode($S_DT, $parts);
            }
        }

        if ($pathstr === $UNDEF) {
            if ($val === $UNDEF || $val === null) {
                $pathstr = '<unknown-path>';
            } elseif (is_object($val) && count(get_object_vars($val)) === 0) {
                // empty object
                $pathstr = '<unknown-path:{}>';
            } else {
                // booleans, numbers, non-empty objects, etc.
                $pathstr = '<unknown-path' . $S_CN . self::stringify($val, 47) . '>';
            }
        }

        return $pathstr;
    }


    public static function clone(mixed $val): mixed
    {
        if ($val === self::UNDEF) {
            return self::UNDEF;
        }
        $refs = [];
        $replacer = function (mixed $v) use (&$refs, &$replacer): mixed {
            if (is_callable($v)) {
                $refs[] = $v;
                return '`$FUNCTION:' . (count($refs) - 1) . '`';
            } elseif (is_array($v)) {
                $result = [];
                foreach ($v as $k => $item) {
                    $result[$k] = $replacer($item);
                }
                return $result;
            } elseif (is_object($v)) {
                $objVars = get_object_vars($v);
                $result = new \stdClass();
                foreach ($objVars as $k => $item) {
                    $result->$k = $replacer($item);
                }
                return $result;
            } else {
                return $v;
            }
        };
        $temp = $replacer($val);
        $reviver = function (mixed $v) use (&$refs, &$reviver): mixed {
            if (is_string($v)) {
                if (preg_match('/^`\$FUNCTION:([0-9]+)`$/', $v, $matches)) {
                    return $refs[(int) $matches[1]];
                }
                return $v;
            } elseif (is_array($v)) {
                $result = [];
                foreach ($v as $k => $item) {
                    $result[$k] = $reviver($item);
                }
                return $result;
            } elseif (is_object($v)) {
                $objVars = get_object_vars($v);
                $result = new \stdClass();
                foreach ($objVars as $k => $item) {
                    $result->$k = $reviver($item);
                }
                return $result;
            } else {
                return $v;
            }
        };
        return $reviver($temp);
    }

    /**
     * @internal
     * Set a property or list‐index on a “node” (stdClass or PHP array).
     * Respects undef‐marker removals, numeric vs string keys, and
     * list‐vs‐map semantics.
     */
    public static function setprop(mixed &$parent, mixed $key, mixed $val): mixed
    {
        // only valid keys make sense
        if (!self::iskey($key)) {
            return $parent;
        }

        // ─── OBJECT (map) ───────────────────────────────────────────
        if (is_object($parent)) {
            $keyStr = self::strkey($key);
            if ($val === self::UNDEF) {
                unset($parent->$keyStr);
            } else {
                $parent->$keyStr = $val;
            }
            return $parent;
        }

        // ─── ARRAY ──────────────────────────────────────────────────
        if (is_array($parent)) {
            if (!self::islist($parent)) {
                // map‐array
                $keyStr = self::strkey($key);
                if ($val === self::UNDEF) {
                    unset($parent[$keyStr]);
                } elseif (ctype_digit((string) $key)) {
                    // numeric string key: unshift (TS always merges maps by overwriting)
                    $parent = [$keyStr => $val] + $parent;
                } else {
                    $parent[$keyStr] = $val;
                }
            } else {
                // list‐array
                if (!is_numeric($key)) {
                    return $parent;
                }
                $keyI = (int) floor((float) $key);
                if ($val === self::UNDEF) {
                    if ($keyI >= 0 && $keyI < count($parent)) {
                        array_splice($parent, $keyI, 1);
                    }
                } elseif ($keyI >= 0) {
                    if (count($parent) < $keyI) {
                        $parent[] = $val;
                    } else {
                        $parent[$keyI] = $val;
                    }
                } else {
                    array_unshift($parent, $val);
                }
            }
        }

        return $parent;
    }


    public static function walk(
        mixed $val,
        callable $apply,
        mixed $key = null,
        mixed $parent = null,
        array $path = []
    ): mixed {
        // If this is an interior node, recurse into its children first.
        if (self::isnode($val)) {
            foreach (self::items($val) as [$childKey, $childVal]) {
                // build the path including this child's prefixed key
                $childPath = array_merge($path, [self::strkey($childKey)]);
                // recurse
                $newChild = self::walk($childVal, $apply, $childKey, $val, $childPath);
                // replace the child in the parent node
                self::setprop($val, $childKey, $newChild);
            }
        }

        // now apply the callback to this node (or leaf)
        return $apply($key, $val, $parent, $path);
    }

    public static function merge(mixed $val): mixed
    {
        $UNDEF = self::UNDEF;

        // 1) If not a PHP list, just return it.
        if (!self::islist($val)) {
            return $val;
        }

        $list = $val;
        $len = count($list);

        // 2) Special lengths: empty → UNDEF; single → itself
        if ($len === 0) {
            return $UNDEF;
        } elseif ($len === 1) {
            return $list[0];
        }

        // 3) Start with the first element (or {} if somehow missing)
        $out = self::getprop($list, 0, new \stdClass());

        // 4) Merge each subsequent element
        for ($i = 1; $i < $len; $i++) {
            $obj = $list[$i];

            // a) Non-nodes always win outright
            if (!self::isnode($obj)) {
                $out = $obj;
            } else {
                // b) Nodes of differing kinds (map vs list) also win outright
                if (
                    !self::isnode($out)
                    || (self::ismap($obj) && self::islist($out))
                    || (self::islist($obj) && self::ismap($out))
                ) {
                    $out = $obj;
                }
                // c) Otherwise we have two same-kind nodes → deep-merge
                else {
                    // **Here’s the only change**: hold $out by reference.
                    $cur = [&$out];

                    $merger = function ($key, $value, $parent, $path) use (&$cur, &$out) {
                        // Skip the root (no key)
                        if ($key === null) {
                            return $value;
                        }

                        // depth is path length minus one
                        $depth = count($path) - 1;

                        // If we haven’t yet set $cur[$depth], grab it via getpath()
                        if (!array_key_exists($depth, $cur) || $cur[$depth] === self::UNDEF) {
                            $cur[$depth] = self::getpath(
                                array_slice($path, 0, $depth),
                                $out
                            );
                        }

                        // Ensure it’s a node
                        if (!self::isnode($cur[$depth])) {
                            $cur[$depth] = self::islist($parent) ? [] : new \stdClass();
                        }

                        // If the override value is a non-empty node, preserve children
                        if (self::isnode($value) && !self::isempty($value)) {
                            self::setprop($cur[$depth], $key, $cur[$depth + 1]);
                            $cur[$depth + 1] = self::UNDEF;
                        }
                        // Otherwise scalar or empty node → direct override
                        else {
                            self::setprop($cur[$depth], $key, $value);
                        }

                        return $value;
                    };

                    // Walk the overriding node so we can inject its leaves into $out
                    self::walk($obj, $merger);
                }
            }
        }

        return $out;
    }

    public static function getpath(
        mixed $path,
        mixed $store,
        mixed $current = null,
        mixed $state = null
    ): mixed {
        $UNDEF = self::UNDEF;
        $S_DT = self::S_DT;
        $S_MT = self::S_MT;
        $BASE = self::S_BASE;

        // 1) normalize to array of parts
        if (self::islist($path)) {
            $parts = $path;
        } elseif (is_string($path)) {
            $parts = explode($S_DT, $path);
        } else {
            return $UNDEF;
        }

        $root = $store;
        $val = $store;
        $base = self::getprop($state, $BASE);

        // 2) empty‐path shortcut
        if (
            $path === null
            || $store === null
            || (count($parts) === 1 && $parts[0] === $S_MT)
        ) {
            $val = self::getprop($store, $base, $store);
        }
        // 3) otherwise walk down the segments
        elseif (count($parts) > 0) {
            $pi = 0;
            // leading “.” means start from $current
            if ($parts[0] === $S_MT) {
                $pi = 1;
                $root = $current;
            }

            // first segment
            $seg = $parts[$pi] ?? $UNDEF;
            if (is_array($root) && ctype_digit((string) $seg)) {
                // numeric array index
                $idx = (int) $seg;
                $first = $root[$idx] ?? $UNDEF;
            } else {
                // map/object lookup
                $first = self::getprop($root, $seg);
            }

            // base‐fallback at top‐level
            $val = ($first === $UNDEF && $pi === 0)
                ? self::getprop(self::getprop($root, $base), $seg)
                : $first;

            // descend remaining parts
            for ($pi = $pi + 1; $val !== $UNDEF && $pi < count($parts); $pi++) {
                $seg = $parts[$pi];
                if (is_array($val) && ctype_digit((string) $seg)) {
                    $idx = (int) $seg;
                    $val = $val[$idx] ?? $UNDEF;
                } else {
                    $val = self::getprop($val, $seg);
                }
            }
        }

        // 4) final transform hook
        if (
            $state !== null
            && is_object($state)
            && isset($state->handler)
            && is_callable($state->handler)
        ) {
            $ref = is_array($parts) ? implode('.', $parts) : (string) $path;
            $val = call_user_func(
                $state->handler,
                $state,
                $val,
                $current,
                $ref,
                $store
            );
        }

        return $val;
    }


    public static function inject(
        mixed $val,
        mixed $store,
        ?callable $modify = null,
        mixed $current = self::UNDEF,
        mixed $state = self::UNDEF
    ): mixed {

        error_log(
            '➤ inject() called — '
            . 'VAL=' . var_export($val, true)
            . '  STORE=' . var_export($store, true)
            . '  STATE=' . ($state === self::UNDEF ? 'undef' : 'defined')
        );

        $UNDEF = self::UNDEF;
        $S_MT = self::S_MT;
        $S_DS = self::S_DS;
        $S_DTOP = self::S_DTOP;
        $S_BASE = self::S_BASE;
        $S_DERRS = self::S_DERRS;
        $S_MKEYPRE = self::S_MKEYPRE;
        $S_MVAL = self::S_MVAL;
        $S_MKEYPOST = self::S_MKEYPOST;

        // 1) At the very root: wrap incoming $val in a virtual parent & init state
        if ($state === $UNDEF) {
            $parent = new \stdClass();
            $parent->{$S_DTOP} = $val;

            $st = new \stdClass();
            $st->mode = $S_MVAL;
            $st->full = false;
            $st->keyI = 0;
            $st->keys = [$S_DTOP];
            $st->key = $S_DTOP;
            $st->val = $val;
            $st->parent = $parent;
            $st->path = [$S_DTOP];
            $st->nodes = [$parent];
            $st->handler = [self::class, '_injecthandler'];
            $st->base = $S_DTOP;
            $st->modify = $modify;
            $st->errs = self::getprop($store, $S_DERRS, []);
            $st->meta = new \stdClass();

            $state = $st;
        }

        // 2) Resolve “current” for dot-prefixed local paths
        if ($current === $UNDEF) {
            $current = (object) [$S_DTOP => $store];
        } else {
            $keys = $state->path;
            $pk = $keys[count($keys) - 2] ?? null;
            if ($pk !== null) {
                $current = self::getprop($current, $pk);
            }
        }

        // 3a) STRING leaf: inject backticks right now
        if (is_string($val)) {
            error_log("    ** STRING-LEAF ** val={$val}  parentKey={$state->key}");
            $state->mode = $S_MVAL;
            $newVal = self::_injectstr($val, $store, $current, $state);
            self::setprop($state->parent, $state->key, $newVal);
        }

        // 3b) Otherwise if it's a NODE (array or object), walk its children
        elseif (self::isnode($val)) {
            error_log('  — isnode, isMap=' . (self::ismap($val) ? 'yes' : 'no'));

            // in inject(), before you start sorting/looping the node’s keys:
            if (
                !self::ismap($val)
                && count($val) >= 1
                && $val[0] === '`$EACH`'
                && $state->mode === self::S_MVAL
            ) {
                $eachHandler = self::getprop($store, '$EACH');
                // pass along the macro name
                $ref = $val[0];
                return call_user_func(
                    $eachHandler,
                    $state,
                    $val,
                    $current,
                    $ref,
                    $store
                );
            }    

            // sort map-keys so “$…” transforms run last
            if (self::ismap($val)) {
                $all = array_keys((array) $val);
                $plain = array_filter($all, fn($k) => strpos($k, $S_DS) === false);
                sort($plain);
                $trans = array_filter($all, fn($k) => strpos($k, $S_DS) !== false);
                sort($trans);
                $nodekeys = array_merge($plain, $trans);
            } else {
                // list
                $nodekeys = array_keys($val);
            }

            $count = count($nodekeys);
            for ($nkI = 0; $nkI < $count; $nkI++) {
                $rawKey = $nodekeys[$nkI];
                $nodekey = self::ismap($val) ? (self::S_MT . $rawKey) : $rawKey;
                $childVal = self::getprop($val, $nodekey);

                error_log(sprintf(
                    "    → child[%s] → nodekey=%s (type=%s), childVal=%s",
                    $rawKey,
                    var_export($nodekey, true),
                    self::ismap($val) ? 'map' : 'list',
                    var_export($childVal, true)
                ));
                // fork state for this kid
                $childState = clone $state;
                $childState->mode = $S_MKEYPRE;
                $childState->keyI = $nkI;
                $childState->keys = $nodekeys;
                $childState->key = $nodekey;
                $childState->val = $childVal;
                $childState->parent =& $val;
                $childState->path = array_merge($state->path, [$nodekey]);
                $childState->nodes = array_merge($state->nodes, [$val]);

                // 3b.1) key:pre
                if (self::ismap($val)) {
                    $prekey = self::_injectstr($nodekey, $store, $current, $childState);
                } else {
                    $prekey = $nodekey;
                }
                $nkI = $childState->keyI;
                $nodekeys = $childState->keys;
                $count = count($nodekeys);

                if ($prekey !== $UNDEF) {
                    // 3b.2) recurse under (possibly) new key
                    $childState->mode = $S_MVAL;
                    $childState->val = self::getprop($val, $prekey);

                    self::inject(
                        $childState->val,
                        $store,
                        $modify,
                        $current,
                        $childState
                    );
                    $nkI = $childState->keyI;
                    $nodekeys = $childState->keys;
                    $count = count($nodekeys);

                    // 3b.3) key:post
                    $childState->mode = $S_MKEYPOST;
                    self::_injectstr($nodekey, $store, $current, $childState);
                    $nkI = $childState->keyI;
                    $nodekeys = $childState->keys;
                    $count = count($nodekeys);
                }
            }

            // once every child’s been injected, write the node back up once
            if ($state->mode === $S_MVAL) {
                self::setprop($state->parent, $state->key, $val);
            }
        }

        // 4) “modify” hook, if any
        if ($modify) {
            $mkey = $state->key;
            $mparent = $state->parent;
            $mval = self::getprop($mparent, $mkey);
            $modify($mval, $mkey, $mparent, $state, $current, $store);
        }

        // 5) return the fully-injected root out of our virtual parent
        return self::getprop($state->parent, $S_DTOP);
    }


    /** @internal */
    private static function _injectstr(
        mixed $val,
        mixed $store,
        mixed $current,
        object $state = null
    ): mixed {
        // only non-empty strings get scanned
        if (!is_string($val) || $val === self::S_MT) {
            return self::S_MT;
        }

        // full backtick match:  `foo`  or  `$CMD123`
        if (preg_match('/^`(\$[A-Z]+|[^`]+)[0-9]*`$/', $val, $m)) {
            if ($state) {
                $state->full = true;
            }
            $pathref = $m[1];

            // un-escape any “\$BT”→“`” or “\$DS”→“$”
            if (strlen($pathref) > 3) {
                $pathref = str_replace(['$BT', '$DS'], [self::S_BT, self::S_DS], $pathref);
            }

            // <<< FIX: if it’s purely digits, pull straight out of the store array >>>
            if (ctype_digit($pathref)) {
                $idx = (int) $pathref;
                // prefer current context if set
                $src = ($current !== self::UNDEF && is_array($current)) ? $current : $store;
                return $src[$idx] ?? self::UNDEF;
            }

            // otherwise fall back to the usual dot-path logic
            return self::getpath($pathref, $store, $current, $state);
        }

        // partial injections inside a bigger string
        $out = preg_replace_callback(
            '/`([^`]+)`/',
            function (array $m) use ($store, $current, $state) {
                $ref = $m[1];
                if (strlen($ref) > 3) {
                    $ref = str_replace(['\$BT', '\$DS'], [self::S_BT, self::S_DS], $ref);
                }
                if ($state) {
                    $state->full = false;
                }
                $found = self::getpath($ref, $store, $current, $state);
                if ($found === self::UNDEF) {
                    return self::S_MT;
                }
                return is_string($found) ? $found : json_encode($found);
            },
            $val
        );

        // a final transform pass (e.g. `$TR()` commands) if we’re in “val” mode
        if (
            $state
            && $state->mode === self::S_MVAL
            && is_callable($state->handler)
        ) {
            $state->full = true;
            $out = call_user_func(
                $state->handler,
                $state,
                $out,
                $current,
                $val,
                $store
            );
        }

        return $out;
    }


    /** @internal */
    private static function _injecthandler(
        object $state,
        mixed $val,
        mixed $current,
        string $ref,
        mixed $store
    ): mixed {
        $out = $val;

        // transforms only run on real “$CMD” functions
        $iscmd = is_callable($val)
            && ($ref === self::UNDEF || str_starts_with($ref, self::S_DS));

        if ($iscmd) {
            $out = call_user_func($val, $state, $val, $current, $ref, $store);
        }
        // otherwise, if this was a full “val” injection, write it back
        elseif ($state->mode === self::S_MVAL && !empty($state->full)) {
            self::setprop($state->parent, $state->key, $val);
        }

        return $out;
    }

    /**
     * @internal
     * Delete a key from a map or list.
     */
    private static function transform_DELETE(
        object $state,
        mixed $val,
        mixed $current,
        mixed $ref,
        mixed $store
    ): mixed {
        // _setparentprop(state, UNDEF)
        self::_setparentprop($state, self::UNDEF);
        return self::UNDEF;
    }

    /**
     * @internal
     * Copy value from source data.
     */
    private static function transform_COPY(
        object $state,
        mixed $val,
        mixed $current,
        mixed $ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;
        $out = $key;

        // if not in key-pre/post, copy from current[key]
        if (!str_starts_with($mode, self::S_MKEY)) {
            $out = self::getprop($current, $key);
            self::_setparentprop($state, $out);
        }

        return $out;
    }

    /**
     * @internal
     * As a value, inject the key of the parent node.
     * As a key, defines the name of the key property in the source object.
     */
    private static function transform_KEY(
        object $state,
        mixed $val,
        mixed $current,
        mixed $ref,
        mixed $store
    ): mixed {
        // only in “val” mode do anything
        if ($state->mode !== self::S_MVAL) {
            return self::UNDEF;
        }

        // if parent has a `$KEY` override, use that
        $keyspec = self::getprop($state->parent, self::S_DKEY);
        if ($keyspec !== self::UNDEF) {
            // remove the marker
            self::setprop($state->parent, self::S_DKEY, self::UNDEF);
            return self::getprop($current, $keyspec);
        }

        // otherwise pull from $META.KEY or fallback to the path index
        $meta = self::getprop($state->parent, self::S_DMETA);
        $idx = count($state->path) - 2;
        return self::getprop(
            $meta,
            self::S_KEY,
            self::getprop($state->path, $idx)
        );
    }

    /**
     * @internal
     * Store meta data about a node.  Does nothing itself, just used by other transforms.
     */
    private static function transform_META(
        object $state,
        mixed $val,
        mixed $current,
        mixed $ref,
        mixed $store
    ): mixed {
        // remove the $META marker
        self::setprop($state->parent, self::S_DMETA, self::UNDEF);
        return self::UNDEF;
    }

    /**
     * @internal
     * Merge a list of objects into the current object.
     */
    private static function transform_MERGE(
        object $state,
        mixed $val,
        mixed $current,
        mixed $ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;
        $parent = $state->parent;

        // in key:pre, just pass the key through
        if ($mode === self::S_MKEYPRE) {
            return $key;
        }

        // in key:post, do the actual merge
        if ($mode === self::S_MKEYPOST) {
            // gather the args under parent[key]
            $args = self::getprop($parent, $key);

            // empty‐string means “merge top‐level store”
            if ($args === self::S_MT) {
                $args = [self::getprop($current, self::S_DTOP)];
            }
            // coerce single value into array
            elseif (!is_array($args)) {
                $args = [$args];
            }

            // remove the $MERGE entry from parent
            self::_setparentprop($state, self::UNDEF);

            // build list: [ parent, ...args, clone(parent) ]
            $mergelist = array_merge(
                [$parent],
                $args,
                [clone $parent]
            );

            // perform merge (your existing merge utility)
            self::merge($mergelist);

            return $key;
        }

        // otherwise drop it
        return self::UNDEF;
    }

    private static function transform_EACH(
        object $state,
        mixed $_val,
        mixed $current,
        string $_ref,
        mixed $store
    ): mixed {
        // 1) Only run in “val” mode
        if ($state->mode !== self::S_MVAL) {
            return self::UNDEF;
        }
    
        // 2) Reset any leftover keys so we don’t re-enter the old transform args
        if (isset($state->keys)) {
            $state->keys = array_slice($state->keys, 0, 1);
            $state->keyI  = 0;
        }
    
        // 3) Pull out the two args: [ '$EACH', srcPath, childTpl ]
        $srcPath  = self::getprop($_val, 1);
        $childTpl = self::clone(self::getprop($_val, 2));
    
        // 4) Resolve the source data
        $srcStore = self::getprop($store, $state->base, $store);
        $src      = self::getpath($srcPath, $srcStore, $current);
    
        // 5) Build a parallel list of template-clones
        $templates = [];
        if (self::islist($src)) {
            foreach ($src as $_) {
                $templates[] = self::clone($childTpl);
            }
        } elseif (self::ismap($src)) {
            foreach ($src as $k => $_v) {
                $tpl = self::clone($childTpl);
                self::setprop($tpl, self::S_DMETA, (object)[self::S_KEY => $k]);
                $templates[] = $tpl;
            }
        }
    
        // 6) Prepare the “current” context for nested injection:
        //    only actual lists or maps become values, everything else → empty list
        if (self::islist($src) || self::ismap($src)) {
            $values = array_values((array)$src);
        } else {
            $values = [];
        }
        $innerStore = (object)[ self::S_DTOP => $values ];
        // bring along all the same transforms:
        foreach (['$BT','$DS','$DELETE','$COPY','$KEY','$META','$MERGE','$EACH','$PACK'] as $cmd) {
            $innerStore->{$cmd} = $store->{$cmd};
        }
    
        // 7) Do the nested injection
        $injected = self::inject(
            $templates,
            $innerStore,
            $state->modify,
            $innerStore
        );
    
        // 8) Write the full array back into the spec’s parent
        // $idx    = count($state->path) - 2;
        // $tkey   = $state->path[$idx];
        // $target = $state->nodes[$idx] ?? $state->nodes[$idx + 1];
        // self::_updateAncestors($state, $target, $tkey, $injected);
        // 8) Write the full array back into the spec’s parent
        self::setprop($state->parent, $state->key, $injected);
    
        // 9) And return just the first element, per TS
        return $injected;
    }
    


    /** @internal */
    private static function transform_PACK(
        object $state,
        mixed $_val,
        mixed $current,
        string $_ref,
        mixed $store
    ): mixed {
        // Only run in key:pre mode on a string key
        if ($state->mode !== self::S_MKEYPRE || !is_string($state->key)) {
            return self::UNDEF;
        }

        // 1) pull the “args” off the spec (should be [ path, template ])
        $raw = self::getprop($state->parent, $state->key);
        // coerce to true PHP array
        $args = is_array($raw) ? $raw : (array) $raw;

        // must have exactly two entries
        if (count($args) < 2) {
            return self::UNDEF;
        }

        [$srcPath, $childTpl] = $args;
        $childTpl = self::clone($childTpl);

        // 2) where does this belong in the output?
        $tkey = $state->path[count($state->path) - 2];
        $nodes = $state->nodes;
        $target = $nodes[count($nodes) - 2] ?? $nodes[count($nodes) - 1];

        // 3) resolve the source data
        $srcStore = self::getprop($store, $state->base, $store);
        $src = self::getpath($srcPath, $srcStore, $current);

        // 4) normalize it to a list of nodes, attaching any META
        if (self::islist($src)) {
            $list = $src;
        } elseif (self::ismap($src)) {
            $list = [];
            foreach ($src as $k => $node) {
                self::setprop($node, self::S_DMETA, (object) [self::S_KEY => $k]);
                $list[] = $node;
            }
        } else {
            return self::UNDEF;
        }

        // 5) figure out which property of each node will be its “key”
        $explicit = self::getprop($childTpl, self::S_DKEY);
        $keyName = $explicit !== self::UNDEF
            ? $explicit
            : self::getprop($childTpl, self::S_DKEY); // fallback if you have another convention
        // remove it from the template
        self::setprop($childTpl, self::S_DKEY, self::UNDEF);

        // 6) build up two parallel maps: one of output‐templates, one of contexts
        $outMap = [];
        $ctxMap = [];
        foreach ($list as $node) {
            $kn = self::getprop($node, $keyName);
            $tplClone = self::clone($childTpl);
            // carry over the META for any $KEY transforms inside
            self::setprop($tplClone, self::S_DMETA, self::getprop($node, self::S_DMETA));
            $outMap[$kn] = $tplClone;
            $ctxMap[$kn] = $node;
        }

        // 7) run a nested inject on that map, using the new “current” context
        $ctx = (object) [self::S_DTOP => $ctxMap];
        $injected = self::inject($outMap, $store, $state->modify, $ctx);

        // 8) write the finished map back into its parent
        self::setprop($target, $tkey, $injected);

        // 9) remove the original `$PACK` instruction
        return self::UNDEF;
    }


    /**
     * Transform data using a spec.
     *
     * @param mixed $data   Source data (not mutated)
     * @param mixed $spec   Transform spec (JSON-like)
     * @param array<mixed>|object|null $extra   extra transforms or data
     * @param callable|null $modify  optional per-value hook
     */
    public static function transform(
        mixed $data,
        mixed $spec,
        mixed $extra = null,
        ?callable $modify = null
    ): mixed {
        // 1) clone spec so we can mutate it
        $specClone = self::clone($spec);

        // 2) split extra into data vs transforms
        $extraTransforms = [];
        $extraData = [];

        foreach ((array) $extra as $k => $v) {
            if (str_starts_with((string) $k, self::S_DS)) {
                $extraTransforms[$k] = $v;
            } else {
                $extraData[$k] = $v;
            }
        }

        // 3) build the combined store
        $dataClone = self::merge([
            self::clone($extraData),
            self::clone($data),
        ]);

        $store = (object) array_merge(
            [
                self::S_DTOP => $dataClone,
                '$BT' => fn() => self::S_BT,
                '$DS' => fn() => self::S_DS,
                '$WHEN' => fn() => (new \DateTime)->format(\DateTime::ATOM),
                '$DELETE' => [self::class, 'transform_DELETE'],
                '$COPY' => [self::class, 'transform_COPY'],
                '$KEY' => [self::class, 'transform_KEY'],
                '$META' => [self::class, 'transform_META'],
                '$MERGE' => [self::class, 'transform_MERGE'],
                '$EACH' => [self::class, 'transform_EACH'],
                '$PACK' => [self::class, 'transform_PACK'],
            ],
            $extraTransforms
        );

        // 4) run inject to do the transform
        return self::inject($specClone, $store, $modify, $store);
    }

    /** @internal */
    private static function _setparentprop(object $state, mixed $val): void
    {
        // Mirror TypeScript’s _setparentprop: write $val back into the parent at state->key
        self::setprop($state->parent, $state->key, $val);
    }

    /** @internal */
    private static function _updateAncestors(object $_state, mixed $target, mixed $tkey, mixed $tval): void
    {
        // In TS this simply re-writes the transformed value into its ancestor
        self::setprop($target, $tkey, $tval);
    }

    /** @internal */
    private static function _invalidTypeMsg(array $path, string $type, string $vt, mixed $v): string
    {
        // Build the same “Expected X at foo.bar, found Y: Z” message
        $vs = self::stringify($v);
        $location = self::pathify($path, 1);
        $found = ($v !== null ? $vt . ': ' : '');
        return "Expected {$type} at {$location}, found {$found}{$vs}";
    }



}
?>