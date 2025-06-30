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
    private const S_DANNO = '`$ANNO`';
    
    // Match TypeScript constants exactly
    private const S_BKEY = '`$KEY`';
    private const S_BANNO = '`$ANNO`';
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
        // We don't consider null or the undef‐marker to be a node.
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
        // Any PHP array that isn't a list is a map,
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
     * Set a property or list‐index on a "node" (stdClass or PHP array).
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
                    // **Here's the only change**: hold $out by reference.
                    $cur = [&$out];

                    $merger = function ($key, $value, $parent, $path) use (&$cur, &$out) {
                        // Skip the root (no key)
                        if ($key === null) {
                            return $value;
                        }

                        // depth is path length minus one
                        $depth = count($path) - 1;

                        // If we haven't yet set $cur[$depth], grab it via getpath()
                        if (!array_key_exists($depth, $cur) || $cur[$depth] === self::UNDEF) {
                            $cur[$depth] = self::getpath(
                                array_slice($path, 0, $depth),
                                $out
                            );
                        }

                        // Ensure it's a node
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
        // Convert path to array of parts
        $parts = is_array($path) ? $path :
            (is_string($path) ? explode('.', $path) :
                (is_numeric($path) ? [self::strkey($path)] : self::UNDEF));

        if ($parts === self::UNDEF) {
            return self::UNDEF;
        }

        $val = $store;
        $base = self::getprop($state, 'base', self::S_DTOP);
        $src = self::getprop($store, $base, $store);
        $numparts = count($parts);
        $dparent = self::getprop($state, 'dparent');
        
        // If no dparent from state but current is provided, use current as dparent for relative paths
        if ($dparent === self::UNDEF && $current !== null && $current !== self::UNDEF) {
            $dparent = $current;
        }

        // An empty path (incl empty string) just finds the src (base data)
        if ($path === null || $store === null || ($numparts === 1 && $parts[0] === '')) {
            $val = $src;
        } else if ($numparts > 0) {
            // Check for $ACTIONs (transforms/functions in store)
            if ($numparts === 1) {
                $storeVal = self::getprop($store, $parts[0]);
                if ($storeVal !== self::UNDEF) {
                    // Found in store - return directly, don't traverse as path
                    $val = $storeVal;
                } else {
                    // Not in store - treat as regular path in data
                    // Use current context if provided, otherwise use src
                    $val = ($current !== null && $current !== self::UNDEF) ? $current : $src;
                }
            } else {
                // Multi-part paths - use current context if provided, otherwise use src
                $val = ($current !== null && $current !== self::UNDEF) ? $current : $src;
            }

            // Only traverse if we didn't get a direct store value or if it's a function that needs to be called
            if (!self::isfunc($val) && ($numparts > 1 || self::getprop($store, $parts[0]) === self::UNDEF)) {

                // Check for meta path in first part
                if (preg_match('/^([^$]+)\$([=~])(.+)$/', $parts[0], $m) && $state && isset($state->meta)) {
                    $val = self::getprop($state->meta, $m[1]);
                    $parts[0] = $m[3];
                }

                $dpath = self::getprop($state, 'dpath');

                for ($pI = 0; $val !== self::UNDEF && $pI < count($parts); $pI++) {
                    $part = $parts[$pI];

                    if ($state && $part === '$KEY') {
                        $part = self::getprop($state, 'key');
                    } else if ($state && str_starts_with($part, '$GET:')) {
                        // $GET:path$ -> get store value, use as path part (string)
                        $getpath = substr($part, 5, -1);
                        $getval = self::getpath($getpath, $src, null, null);
                        $part = self::stringify($getval);
                    } else if ($state && str_starts_with($part, '$REF:')) {
                        // $REF:refpath$ -> get spec value, use as path part (string)
                        $refpath = substr($part, 5, -1);
                        $spec = self::getprop($store, '$SPEC');
                        if ($spec !== self::UNDEF) {
                            $specval = self::getprop($spec, $refpath);
                            if ($specval !== self::UNDEF) {
                                $part = self::stringify($specval);
                            } else {
                                $part = self::UNDEF;
                            }
                        } else {
                            $part = self::UNDEF;
                        }
                    } else if ($state && str_starts_with($part, '$META:')) {
                        // $META:metapath$ -> get meta value, use as path part (string)
                        $part = self::stringify(self::getpath(substr($part, 6, -1), self::getprop($state, 'meta'), null, null));
                    }

                    // $$ escapes $
                    $part = str_replace('$$', '$', $part);

                    if ($part === '') {
                        $ascends = 0;
                        while ($pI + 1 < count($parts) && $parts[$pI + 1] === '') {
                            $ascends++;
                            $pI++;
                        }

                        if ($state && $ascends > 0) {
                            if ($pI === count($parts) - 1) {
                                $ascends--;
                            }

                            if ($ascends === 0) {
                                $val = $dparent;
                            } else {
                                // Navigate up the data path by removing 'ascends' levels
                                $dpath_slice = [];
                                if (is_array($dpath) && $ascends <= count($dpath)) {
                                    $dpath_slice = array_slice($dpath, 0, count($dpath) - $ascends);
                                }
                                
                                $parts_slice = array_slice($parts, $pI + 1);
                                $fullpath = array_merge($dpath_slice, $parts_slice);

                                if (is_array($dpath) && $ascends <= count($dpath)) {
                                    $val = self::getpath($fullpath, $store, null, null);
                                } else {
                                    $val = self::UNDEF;
                                }
                                break;
                            }
                        } else {
                            // Special case for single dot: use dparent if available
                            if ($dparent !== null && $dparent !== self::UNDEF) {
                                $val = $dparent;
                            } else {
                                $val = $src;
                            }
                        }
                    } else {
                        $val = self::getprop($val, $part);
                    }
                }
            }
        }

        // Inj may provide a custom handler to modify found value
        $handler = self::getprop($state, 'handler');
        if ($state !== null && self::isfunc($handler)) {
            $ref = self::pathify($path);
            $val = $handler($state, $val, $ref, $store);
        }

        return $val;
    }


    public static function inject(
        mixed $val,
        mixed $store,
        ?callable $modify = null,
        mixed $current = null,
        ?object $injdef = null
    ): mixed {
        // Check if we're using an existing injection state
        if ($injdef !== null && property_exists($injdef, 'mode')) {
            // Use the existing injection state directly
            $state = $injdef;
        } else {
            // Create a state object to track the injection process
            $state = (object) [
                'mode' => self::S_MVAL,
                'key' => self::S_DTOP,
                'parent' => null,
                'path' => [self::S_DTOP],
                'nodes' => [],
                'keys' => [self::S_DTOP],
                'keyI' => 0,
                'base' => self::S_DTOP,
                'modify' => $modify,
                'full' => false,
                'handler' => [self::class, '_injecthandler'],
                'dparent' => null,
                'dpath' => [self::S_DTOP],
                'errs' => [],
                'meta' => (object) [],
            ];

            // Set up data context
            if ($current === null) {
                $current = self::getprop($store, self::S_DTOP);
                if ($current === self::UNDEF) {
                    $current = $store;
                }
            }
            $state->dparent = $current;

            // Create a virtual parent holder like TypeScript does  
            $holder = (object) [self::S_DTOP => $val];
            $state->parent = $holder;
            $state->nodes = [$holder];
        }

        // Process the value through _injectval
        $modifiedVal = self::_injectval($state, $val, $state->dparent ?? $current, $store);
        
        // For existing injection states, just update and return the modified value
        if ($injdef !== null && property_exists($injdef, 'mode')) {
            $state->val = $modifiedVal;
            return $modifiedVal;
        }
        
        // For new injection states, update the holder and return from it
        self::setprop($state->parent, self::S_DTOP, $modifiedVal);
        return self::getprop($state->parent, self::S_DTOP);
    }


    private static function _injectstr(
        string $val,
        mixed $store,
        ?object $inj = null
    ): mixed {
        // Can't inject into non-strings
        if ($val === self::S_MT) {
            return self::S_MT;
        }

        // Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`", "``"
        $m = preg_match('/^`(\$[A-Z]+|[^`]*)[0-9]*`$/', $val, $matches);

        // Full string of the val is an injection.
        if ($m) {
            if ($inj !== null) {
                $inj->full = true;
            }
            $pathref = $matches[1];

            // Debug specific to PACK
            if ($pathref === '$PACK') {
                echo "DEBUG _injectstr: Processing PACK injection\n";
                echo "DEBUG _injectstr: injection state mode: " . ($inj->mode ?? 'null') . "\n";
            }

            // Special escapes inside injection.
            // Only apply escape handling to strings longer than 3 characters
            // to avoid affecting transform command names like $BT (length 3) and $DS (length 2)
            if (strlen($pathref) > 3) {
                // Handle escaped dots FIRST: \. -> .
                $pathref = str_replace('\\.', '.', $pathref);
                // Then handle $BT and $DS
                $pathref = str_replace('$BT', self::S_BT, $pathref);
                $pathref = str_replace('$DS', self::S_DS, $pathref);
            }

            // Get the extracted path reference.
            // Use dparent from injection state as current context for relative path resolution
            $current = ($inj !== null && property_exists($inj, 'dparent')) ? $inj->dparent : null;
            $out = self::getpath($pathref, $store, $current, $inj);
            
            if ($pathref === '$PACK') {
                echo "DEBUG _injectstr: getpath returned for PACK: " . json_encode($out) . "\n";
            }
            
            return $out;
        }

        // Check for injections within the string.
        $out = preg_replace_callback('/`([^`]+)`/', function($matches) use ($store, $inj) {
            $ref = $matches[1];

            // Special escapes inside injection.
            // Only apply escape handling to strings longer than 3 characters
            // to avoid affecting transform command names like $BT (length 3) and $DS (length 2)
            if (strlen($ref) > 3) {
                // Handle escaped dots FIRST: \. -> .
                $ref = str_replace('\\.', '.', $ref);
                // Then handle $BT and $DS
                $ref = str_replace('$BT', self::S_BT, $ref);
                $ref = str_replace('$DS', self::S_DS, $ref);
            }
            if ($inj !== null) {
                $inj->full = false;
            }
            // Use dparent from injection state as current context for relative path resolution
            $current = ($inj !== null && property_exists($inj, 'dparent')) ? $inj->dparent : null;
            $found = self::getpath($ref, $store, $current, $inj);

            // Ensure inject value is a string.
            if ($found === self::UNDEF) {
                return self::S_MT;
            }
            if (is_string($found)) {
                return $found;
            }
            return json_encode($found);
        }, $val);

        // Also call the inj handler on the entire string, providing the
        // option for custom injection.
        if ($inj !== null && is_callable($inj->handler)) {
            $inj->full = true;
            // Use the extracted pathref if this was a full injection, otherwise original val
            $ref = isset($pathref) ? $pathref : $val;
            $out = call_user_func($inj->handler, $inj, $out, $ref, $store);
        }

        return $out;
    }


    private static function _injectexpr(
        string $expr,
        mixed $store,
        mixed $current,
        object $state
    ): mixed {
        // Check if it's a transform command
        if (str_starts_with($expr, self::S_DS)) {
            $transform = self::getprop($store, $expr);
            if (is_callable($transform)) {
                return call_user_func($transform, $state, $expr, $current, $expr, $store);
            }
        }

        // Otherwise treat it as a path
        $result = self::getpath($expr, $store, $current, $state);
        return $result;
    }

    private static function _injecthandler(
        object $inj,
        mixed $val,
        string $ref,
        mixed $store
    ): mixed {
        $out = $val;
        
        // Check if val is a function (command transforms)
        $iscmd = self::isfunc($val) && (self::UNDEF === $ref || str_starts_with($ref, self::S_DS));

        // Only call val function if it is a special command ($NAME format).
        if ($iscmd) {
            $out = call_user_func($val, $inj, $val, $ref, $store);
        }
        // Update parent with value. Ensures references remain in node tree.
        elseif (self::S_MVAL === $inj->mode && $inj->full) {
            self::setprop($inj->parent, $inj->key, $out);
        }
        return $out;
    }

    private static function _injecthandler_getpath(
        object $state,
        mixed $val,
        string $ref,
        mixed $store
    ): mixed {
        return self::_injecthandler($state, $val, $ref, $store);
    }

    /**
     * @internal
     * Delete a key from a map or list.
     */
    public static function transform_DELETE(
        object $state,
        mixed $val,
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
    public static function transform_COPY(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;

        $out = $key;
        if (!str_starts_with($mode, self::S_MKEY)) {
            // For root-level copies where key is "$TOP", return dparent directly
            if ($key === self::S_DTOP) {
                $out = $state->dparent;
            } else {
                $out = self::getprop($state->dparent, $key);
            }
            self::_setparentprop($state, $out);
        }

        return $out;
    }

    /**
     * @internal
     * As a value, inject the key of the parent node.
     * As a key, defines the name of the key property in the source object.
     */
    public static function transform_KEY(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // only in "val" mode do anything
        if ($state->mode !== self::S_MVAL) {
            return self::UNDEF;
        }

        // if parent has a "$KEY" override, use that
        $keyspec = self::getprop($state->parent, self::S_DKEY);
        if ($keyspec !== self::UNDEF) {
            // remove the marker
            self::setprop($state->parent, self::S_DKEY, self::UNDEF);
            return self::getprop($state->dparent, $keyspec);
        }

        // otherwise pull from $ANNO.KEY or fallback to the path index
        $meta = self::getprop($state->parent, self::S_BANNO);
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
    public static function transform_META(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // remove the $META marker
        self::setprop($state->parent, self::S_DMETA, self::UNDEF);
        return self::UNDEF;
    }

    /**
     * @internal
     * Store annotation data about a node. Does nothing itself, just used by other transforms.
     */
    public static function transform_ANNO(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        // remove the $ANNO marker
        self::setprop($state->parent, self::S_BANNO, self::UNDEF);
        return self::UNDEF;
    }

    /**
     * @internal
     * Merge a list of objects into the current object.
     */
        public static function transform_MERGE(
        object $state,
        mixed $val,
        mixed $ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;
        $parent = $state->parent;

        // in key:pre, do all the merge work and remove the key
        if ($mode === self::S_MKEYPRE) {
            // gather the args under parent[key]
            $args = self::getprop($parent, $key);

            // empty-string means "merge top-level store"
            if ($args === self::S_MT) {
                $args = [self::getprop($state->dparent, self::S_DTOP)];
            }
            // coerce single value into array
            elseif (!is_array($args)) {
                $args = [$args];
            }

            // Resolve each argument to get data values
            $resolvedArgs = [];
            foreach ($args as $arg) {
                if (is_string($arg)) {
                    // Check if it's an injection string like '`a`'
                    if (preg_match('/^`(\$[A-Z]+|[^`]*)[0-9]*`$/', $arg, $matches)) {
                        $pathref = $matches[1];
                        // Handle escapes
                        if (strlen($pathref) > 3) {
                            $pathref = str_replace('\\.', '.', $pathref);
                            $pathref = str_replace('$BT', '`', $pathref);
                            $pathref = str_replace('$DS', '$', $pathref);
                        }
                        $resolved = self::getpath($pathref, $store);
                    } else {
                        $resolved = $arg;
                    }
                    $resolvedArgs[] = $resolved;
                } else {
                    $resolvedArgs[] = $arg;
                }
            }

            // remove the $MERGE entry from parent
            self::setprop($parent, $key, self::UNDEF);

            // build list: [ parent, ...resolvedArgs, clone(parent) ]
            $mergelist = array_merge(
                [$parent],
                $resolvedArgs,
                [clone $parent]
            );

            // perform merge - this modifies the parent in place
            self::merge($mergelist);

            // return UNDEF to prevent further processing of this key
            return self::UNDEF;
        }

        // in key:post, the merge is already done, just return the key
        if ($mode === self::S_MKEYPOST) {
            return $key;
        }

        // otherwise drop it
        return self::UNDEF;
    }

    public static function transform_EACH(
        object $state,
        mixed $_val,
        string $_ref,
        mixed $store
    ): mixed {
        // Remove arguments to avoid spurious processing
        if (isset($state->keys)) {
            $state->keys = array_slice($state->keys, 0, 1);
        }

        if (self::S_MVAL !== $state->mode) {
            return self::UNDEF;
        }

        // Get arguments: ['`$EACH`', 'source-path', child-template]
        $srcpath = self::getprop($state->parent, 1);
        $child = self::clone(self::getprop($state->parent, 2));
        
        // Source data
        $srcstore = self::getprop($store, $state->base, $store);
        $src = self::getpath($srcpath, $srcstore, $state);

        // Create parallel data structures: source entries :: child templates  
        $tcur = [];
        $tval = [];

        $tkey = self::getelem($state->path, -2);
        $target = self::getelem($state->nodes, -2) ?? self::getelem($state->nodes, -1);

        // Create clones of the child template for each value of the current source
        if (self::islist($src)) {
            $tval = array_map(function($_) use ($child) {
                return self::clone($child);
            }, $src);
        } elseif (self::ismap($src)) {
            $tval = [];
            foreach ($src as $k => $v) {
                $template = self::clone($child);
                // Make a note of the key for $KEY transforms
                self::setprop($template, self::S_BANNO, (object) [self::S_KEY => $k]);
                $tval[] = $template;
            }
        }
        
        $rval = [];

        if (count($tval) > 0) {
            $tcur = (null == $src) ? self::UNDEF : array_values((array) $src);

            $ckey = self::getelem($state->path, -2);
            $tpath = array_slice($state->path, 0, -1);
            
            // Build dpath like TypeScript: [S_DTOP, ...srcpath.split('.'), '$:' + ckey]
            $dpath = [self::S_DTOP];
            $dpath = array_merge($dpath, explode('.', $srcpath), ['$:' . $ckey]);

            // Build parent structure like TypeScript version
            $tcur = [$ckey => $tcur];

            if (count($tpath) > 1) {
                $pkey = self::getelem($state->path, -3) ?? self::S_DTOP;
                $tcur = [$pkey => $tcur];
                $dpath[] = '$:' . $pkey;
            }

            // Create child injection state matching TypeScript version
            $tinj = (object) [
                'mode' => self::S_MVAL,
                'full' => false,
                'keyI' => 0,
                'keys' => [$ckey],
                'key' => $ckey,
                'val' => $tval,
                'parent' => self::getelem($state->nodes, -1),
                'path' => $tpath,
                'nodes' => array_slice($state->nodes, 0, -1),
                'handler' => [self::class, '_injecthandler'],
                'base' => $state->base,
                'modify' => $state->modify,
                'errs' => $state->errs ?? [],
                'meta' => $state->meta ?? (object) [],
                'dparent' => $tcur,  // Use the full nested structure like TypeScript
                'dpath' => $dpath,
            ];

            // Set tval in parent like TypeScript version
            self::setprop($tinj->parent, $ckey, $tval);

            // Inject using the proper injection state
            $result = self::inject($tval, $store, $state->modify, $tinj->dparent, $tinj);
            
            $rval = $tinj->val;
        }

        // Update ancestors using the simple approach like TypeScript
        self::_updateAncestors($state, $target, $tkey, $rval);

        // Prevent callee from damaging first list entry (since we are in `val` mode).
        return count($rval) > 0 ? $rval[0] : self::UNDEF;
    }



    /** @internal */
    public static function transform_PACK(
        object $state,
        mixed $_val,
        string $_ref,
        mixed $store
    ): mixed {
        $mode = $state->mode;
        $key = $state->key;
        $path = $state->path;
        $parent = $state->parent;
        $nodes = $state->nodes;

        echo "DEBUG PACK: Called with mode=$mode, key=$key\n";

        // Defensive context checks - only run in key:pre mode
        if (self::S_MKEYPRE !== $mode || !is_string($key) || null == $path || null == $nodes) {
            echo "DEBUG PACK: Defensive check failed, returning UNDEF\n";
            return self::UNDEF;
        }

        // Get arguments
        $args = self::getprop($parent, $key);
        if (!is_array($args) || count($args) < 2) {
            return self::UNDEF;
        }

        $srcpath = $args[0]; // Path to source data
        $child = self::clone($args[1]); // Child template

        // Find key and target node
        $keyprop = self::getprop($child, self::S_BKEY);
        $tkey = self::getelem($path, -2);
        $target = $nodes[count($path) - 2] ?? $nodes[count($path) - 1];

        // Source data
        $srcstore = self::getprop($store, $state->base, $store);
        $src = self::getpath($srcpath, $srcstore, null, $state);

        // Prepare source as a list - matching TypeScript logic exactly
        if (self::islist($src)) {
            $src = $src;
        } elseif (self::ismap($src)) {
            // Transform map to list with KEY annotations like TypeScript
            $newSrc = [];
            foreach ($src as $k => $node) {
                $node = (array) $node; // Ensure it's an array for setprop
                $node[self::S_BANNO] = (object) [self::S_KEY => $k];
                $newSrc[] = (object) $node;
            }
            $src = $newSrc;
        } else {
            return self::UNDEF;
        }

        if (null == $src) {
            return self::UNDEF;
        }

        // Get key if specified - matching TypeScript logic
        $childkey = self::getprop($child, self::S_BKEY);
        $keyname = $childkey !== self::UNDEF ? $childkey : $keyprop;
        self::delprop($child, self::S_BKEY);

        // Build parallel target object using reduce pattern from TypeScript
        $tval = new \stdClass();
        foreach ($src as $node) {
            $kn = self::getprop($node, $keyname);
            if ($kn !== self::UNDEF) {
                self::setprop($tval, $kn, self::clone($child));
                $nchild = self::getprop($tval, $kn);
                
                // Transfer annotation data if present
                $mval = self::getprop($node, self::S_BANNO);
                if ($mval === self::UNDEF) {
                    self::delprop($nchild, self::S_BANNO);
                } else {
                    self::setprop($nchild, self::S_BANNO, $mval);
                }
            }
        }

        $rval = new \stdClass();

        if (count((array) $tval) > 0) {
            // Build parallel source object
            $tcur = new \stdClass();
            foreach ($src as $node) {
                $kn = self::getprop($node, $keyname);
                if ($kn !== self::UNDEF) {
                    self::setprop($tcur, $kn, $node);
                }
            }

            $tpath = array_slice($path, 0, -1);

            $ckey = self::getelem($path, -2);
            $dpath = [self::S_DTOP];
            if (!empty($srcpath)) {
                $dpath = array_merge($dpath, explode('.', $srcpath));
            }
            $dpath[] = '$:' . $ckey;

            // Build nested structure like TypeScript using objects, not arrays
            $tcur = (object) [$ckey => $tcur];

            if (count($tpath) > 1) {
                $pkey = self::getelem($path, -3) ?? self::S_DTOP;
                $tcur = (object) [$pkey => $tcur];
                $dpath[] = '$:' . $pkey;
            }

            // Create child injection state matching TypeScript  
            $slicedNodes = array_slice($nodes, 0, -1);
            $childState = (object) [
                'mode' => self::S_MVAL,
                'full' => false,
                'keyI' => 0,
                'keys' => [$ckey],
                'key' => $ckey,
                'val' => $tval,
                'parent' => self::getelem($slicedNodes, -1),
                'path' => $tpath,
                'nodes' => $slicedNodes,
                'handler' => [self::class, '_injecthandler'],
                'base' => $state->base,
                'modify' => $state->modify,
                'errs' => $state->errs ?? [],
                'meta' => $state->meta ?? (object) [],
                'dparent' => $tcur,
                'dpath' => $dpath,
            ];

            // Set the value in parent like TypeScript version does
            self::setprop($childState->parent, $ckey, $tval);

            // Instead of injecting the entire template at once, 
            // inject each individual template with its own data context
            foreach ((array) $tval as $templateKey => $template) {
                // Get the corresponding source node for this template
                // $tcur structure may be nested like: {$TOP: {ckey: {K0: sourceNode0, K1: sourceNode1, ...}}}
                // Navigate through the structure to find the actual source data
                $sourceData = $tcur;
                
                // If tcur has $TOP level, navigate through it
                if (self::getprop($sourceData, self::S_DTOP) !== self::UNDEF) {
                    $sourceData = self::getprop($sourceData, self::S_DTOP);
                }
                
                // Then navigate to the ckey level
                $sourceData = self::getprop($sourceData, $ckey);
                
                // Finally get the specific source node
                $sourceNode = self::getprop($sourceData, $templateKey);
                
                if ($sourceNode !== self::UNDEF) {
                    // Create individual injection state for this template
                    $individualState = clone $childState;
                    $individualState->dparent = $sourceNode; // Set to individual source node
                    $individualState->key = $templateKey;
                    
                    // Inject this individual template
                    $injectedTemplate = self::inject($template, $store, $state->modify, $sourceNode, $individualState);
                    self::setprop($tval, $templateKey, $injectedTemplate);
                }
            }
            
            $rval = $tval;
        }

        // Use _setparentprop to properly set the parent value to the packed data
        self::_setparentprop($state, $rval);
        
        echo "DEBUG PACK: Returning UNDEF to delete key\n";
        // Return UNDEF to signal that this key should be deleted
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
                '$ANNO' => [self::class, 'transform_ANNO'],
                '$MERGE' => [self::class, 'transform_MERGE'],
                '$EACH' => [self::class, 'transform_EACH'],
                '$PACK' => [self::class, 'transform_PACK'],
            ],
            $extraTransforms
        );

        // 4) run inject to do the transform
        $result = self::inject($specClone, $store, $modify, $dataClone);
        
        // Debug: check what the spec clone looks like after injection
        error_log("TRANSFORM: SpecClone after inject: " . json_encode($specClone));
        
        // Debug: check the final result
        error_log("TRANSFORM: Final result: " . json_encode($result));
        
        return $result;
    }

    /** @internal */
    private static function _setparentprop(object $state, mixed $val): void {
        if ($val === self::UNDEF) {
            self::delprop($state->parent, $state->key);
        } else {
            self::setprop($state->parent, $state->key, $val);
        }
    }

    /** @internal */
    private static function _updateAncestors(object $_state, mixed &$target, mixed $tkey, mixed $tval): void
    {
        // In TS this simply re-writes the transformed value into its ancestor
        self::setprop($target, $tkey, $tval);
    }

    /** @internal */
    private static function _invalidTypeMsg(array $path, string $type, string $vt, mixed $v): string
    {
        // Build the same "Expected X at foo.bar, found Y: Z" message
        $vs = self::stringify($v);
        $location = self::pathify($path, 1);
        $found = ($v !== null ? $vt . ': ' : '');
        return "Expected {$type} at {$location}, found {$found}{$vs}";
    }

    /**
     * Select children from a top-level object that match a MongoDB-style query.
     * Supports $and, $or, and equality comparisons.
     * For arrays, children are elements; for objects, children are values.
     *
     * @param mixed $query The query specification
     * @param mixed $children The object or array to search in
     * @return array Array of matching children
     */
    public static function select(mixed $query, mixed $children): array
    {
        if (!self::isnode($children)) {
            return [];
        }

        if (self::ismap($children)) {
            $children = array_map(function($n) {
                $n[1][self::S_DKEY] = $n[0];
                return $n[1];
            }, self::items($children));
        } else {
            $children = array_map(function($n, $i) {
                if (self::ismap($n)) {
                    $n[self::S_DKEY] = $i;
                }
                return $n;
            }, $children, array_keys($children));
        }

        $results = [];
        $injdef = (object) [
            'errs' => [],
            'meta' => (object) ['`$EXACT`' => true],
            'extra' => [
                '$AND' => [self::class, 'select_AND'],
                '$OR' => [self::class, 'select_OR'],
                '$GT' => [self::class, 'select_CMP'],
                '$LT' => [self::class, 'select_CMP'],
                '$GTE' => [self::class, 'select_CMP'],
                '$LTE' => [self::class, 'select_CMP'],
            ]
        ];

        $q = self::clone($query);

        self::walk($q, function($k, $v) {
            if (self::ismap($v)) {
                self::setprop($v, '`$OPEN`', self::getprop($v, '`$OPEN`', true));
            }
            return $v;
        });

        foreach ($children as $child) {
            $injdef->errs = [];
            self::validate($child, self::clone($q), $injdef);

            if (count($injdef->errs) === 0) {
                $results[] = $child;
            }
        }

        return $results;
    }

    /**
     * Helper method for $AND operator in select queries
     */
    private static function select_AND(object $state, mixed $val, mixed $current, string $ref, mixed $store): mixed
    {
        if (self::S_MKEYPRE === $state->mode) {
            $terms = self::getprop($state->parent, $state->key);
            $src = self::getprop($store, $state->base, $store);

            foreach ($terms as $term) {
                $terrs = [];
                self::validate($src, $term, (object) [
                    'extra' => $store,
                    'errs' => $terrs,
                    'meta' => $state->meta,
                ]);

                if (count($terrs) !== 0) {
                    $state->errs[] = 'AND:' . self::stringify($val) . ' fail:' . self::stringify($term);
                }
            }
        }
        return null;
    }

    /**
     * Helper method for $OR operator in select queries
     */
    private static function select_OR(object $state, mixed $val, mixed $current, string $ref, mixed $store): mixed
    {
        if (self::S_MKEYPRE === $state->mode) {
            $terms = self::getprop($state->parent, $state->key);
            $src = self::getprop($store, $state->base, $store);

            foreach ($terms as $term) {
                $terrs = [];
                self::validate($src, $term, (object) [
                    'extra' => $store,
                    'errs' => $terrs,
                    'meta' => $state->meta,
                ]);

                if (count($terrs) === 0) {
                    return null;
                }
            }

            $state->errs[] = 'OR:' . self::stringify($val) . ' fail:' . self::stringify($terms);
        }
        return null;
    }

    /**
     * Helper method for comparison operators in select queries
     */
    private static function select_CMP(object $state, mixed $_val, string $ref, mixed $store): mixed
    {
        if (self::S_MKEYPRE === $state->mode) {
            $term = self::getprop($state->parent, $state->key);
            $src = self::getprop($store, $state->base, $store);
            $gkey = self::getelem($state->path, -2);

            $tval = self::getprop($src, $gkey);
            $pass = false;

            if ('$GT' === $ref && $tval > $term) {
                $pass = true;
            }
            else if ('$LT' === $ref && $tval < $term) {
                $pass = true;
            }
            else if ('$GTE' === $ref && $tval >= $term) {
                $pass = true;
            }
            else if ('$LTE' === $ref && $tval <= $term) {
                $pass = true;
            }

            if ($pass) {
                // Update spec to match found value so that _validate does not complain
                $gp = self::getelem($state->nodes, -2);
                self::setprop($gp, $gkey, $tval);
            }
            else {
                $state->errs[] = 'CMP: fail:' . $ref . ' ' . self::stringify($term);
            }
        }
        return null;
    }

    /**
     * Get element from array by index, supporting negative indices
     * The key should be an integer, or a string that can parse to an integer only.
     * Negative integers count from the end of the list.
     */
    public static function getelem(mixed $val, mixed $key): mixed
    {
        if (!self::islist($val)) {
            return null;
        }

        // Convert string keys to integers if possible
        if (is_string($key)) {
            $nkey = (int)$key;
            if (!is_numeric($key) || (string)$nkey !== $key) {
                return null;
            }
            $key = $nkey;
        }

        if (!is_int($key)) {
            return null;
        }

        if ($key < 0) {
            $key = count($val) + $key;
        }

        return $val[$key] ?? null;
    }

    /**
     * Safely delete a property from an object or array element.
     * Undefined arguments and invalid keys are ignored.
     * Returns the (possibly modified) parent.
     * For objects, the property is deleted using unset.
     * For arrays, the element at the index is removed and remaining elements are shifted down.
     */
    public static function delprop(mixed $parent, mixed $key): mixed
    {
        if (!self::iskey($key)) {
            return $parent;
        }

        if (self::ismap($parent)) {
            $key = self::strkey($key);
            unset($parent->$key);
        }
        else if (self::islist($parent)) {
            // Ensure key is an integer
            $keyI = (int)$key;
            if (!is_numeric($key) || (string)$keyI !== (string)$key) {
                return $parent;
            }

            // Delete list element at position keyI, shifting later elements down
            if ($keyI >= 0 && $keyI < count($parent)) {
                for ($pI = $keyI; $pI < count($parent) - 1; $pI++) {
                    $parent[$pI] = $parent[$pI + 1];
                }
                array_pop($parent);
            }
        }

        return $parent;
    }

    private static function _injectval(
        object $state,
        mixed $val,
        mixed $current,
        mixed $store
    ): mixed {
        $valtype = gettype($val);

        // Descend into node (arrays and objects)
        if (self::isnode($val)) {
            // Check if this object has been replaced by a PACK transform
            if (self::ismap($val) && self::getprop($val, '__PACK_REPLACED__') === true) {
                // The parent structure has been replaced, skip processing this object
                // But first, clean up the marker so it doesn't appear in the final output
                self::delprop($val, '__PACK_REPLACED__');
                error_log("INJECTVAL: Skipping processing due to PACK replacement and cleaned marker");
                return $val;
            }
            
            // Keys are sorted alphanumerically to ensure determinism.
            // Injection transforms ($FOO) are processed *after* other keys.
            if (self::ismap($val)) {
                $allKeys = array_keys((array) $val);
                $normalKeys = [];
                $transformKeys = [];
                
                foreach ($allKeys as $k) {
                    if (str_contains((string) $k, self::S_DS)) {
                        $transformKeys[] = $k;
                    } else {
                        $normalKeys[] = $k;
                    }
                }
                
                sort($normalKeys);
                sort($transformKeys);
                $nodekeys = array_merge($normalKeys, $transformKeys);
            } else {
                // For lists, keys are just the indices - important: use indices as integers like TypeScript
                $nodekeys = array_keys($val);
            }

            // Each child key-value pair is processed in three injection phases:
            // 1. mode='key:pre' - Key string is injected, returning a possibly altered key.
            // 2. mode='val' - The child value is injected.
            // 3. mode='key:post' - Key string is injected again, allowing child mutation.
            for ($nkI = 0; $nkI < count($nodekeys); $nkI++) {
                $nodekey = $nodekeys[$nkI];

                // Create child injection state
                $childpath = array_merge($state->path, [self::strkey($nodekey)]);
                $childnodes = array_merge($state->nodes, [$val]);
                $childval = self::getprop($val, $nodekey);

                // Calculate the child data context (dparent)
                // Only descend into data properties when the spec value is a nested object
                // This allows relative paths to work while keeping simple injections at the right level
                $child_dparent = $state->dparent;
                if ($child_dparent !== self::UNDEF && $child_dparent !== null && self::isnode($childval)) {
                    $child_dparent = self::getprop($child_dparent, self::strkey($nodekey));
                }

                $childinj = (object) [
                    'mode' => self::S_MKEYPRE,
                    'full' => false,
                    'keyI' => $nkI,
                    'keys' => $nodekeys,
                    'key' => self::strkey($nodekey),
                    'val' => $childval,
                    'parent' => $val,
                    'path' => $childpath,
                    'nodes' => $childnodes,
                    'handler' => $state->handler,
                    'base' => $state->base,
                    'modify' => $state->modify,
                    'errs' => $state->errs ?? [],
                    'meta' => $state->meta ?? (object) [],
                    'dparent' => $child_dparent,
                    'dpath' => isset($state->dpath) ? array_merge($state->dpath, [self::strkey($nodekey)]) : [self::strkey($nodekey)],
                ];

                // Perform the key:pre mode injection on the child key.
                $prekey = self::_injectstr(self::strkey($nodekey), $store, $childinj);

                // The injection may modify child processing.
                $nkI = $childinj->keyI;
                $nodekeys = $childinj->keys;

                // If prekey is UNDEF, delete the key and skip further processing
                if ($prekey === self::UNDEF) {
                    // Delete the key from the parent
                    self::delprop($val, $nodekey);
                    
                    // Remove this key from the nodekeys array to prevent issues with iteration
                    array_splice($nodekeys, $nkI, 1);
                    $nkI--; // Adjust index since we removed an element
                    continue;
                }

                // Continue with normal processing
                $childinj->val = self::getprop($val, $prekey);
                $childinj->mode = self::S_MVAL;

                // Perform the val mode injection on the child value.
                // Pass the child injection state to maintain context
                $injected_result = self::inject($childinj->val, $store, $state->modify, $childinj->dparent, $childinj);
                self::setprop($val, $nodekey, $injected_result);

                // The injection may modify child processing.
                $nkI = $childinj->keyI;
                $nodekeys = $childinj->keys;

                // Perform the key:post mode injection on the child key.
                $childinj->mode = self::S_MKEYPOST;
                self::_injectstr(self::strkey($nodekey), $store, $childinj);

                // The injection may modify child processing.
                $nkI = $childinj->keyI;
                $nodekeys = $childinj->keys;
            }
        }
        // Inject paths into string scalars.
        else if ($valtype === 'string') {
            $state->mode = self::S_MVAL;
            $val = self::_injectstr($val, $store, $state);
            if ($val !== '__SKIP__') { // PHP equivalent of SKIP check
                self::setprop($state->parent, $state->key, $val);
            }
        }

        // Custom modification
        if ($state->modify) {
            $mkey = $state->key;
            $mparent = $state->parent;
            $mval = self::getprop($mparent, $mkey);
            call_user_func($state->modify, $mval, $mkey, $mparent, $state, $current, $store);
        }

        $state->val = $val;

        return $val;
    }

}
?>