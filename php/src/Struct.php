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
class Struct {

    /* =======================
     * String Constants
     * =======================
     */
    private const S_MKEYPRE   = 'key:pre';
    private const S_MKEYPOST  = 'key:post';
    private const S_MVAL      = 'val';
    private const S_MKEY      = 'key';

    private const S_DKEY      = '`$KEY`';
    private const S_DMETA     = '`$META`';
    private const S_DTOP      = '$TOP';
    private const S_DERRS     = '$ERRS';

    private const S_array     = 'array';
    private const S_boolean   = 'boolean';
    private const S_function  = 'function';
    private const S_number    = 'number';
    private const S_object    = 'object';
    private const S_string    = 'string';
    private const S_null      = 'null';
    private const S_MT        = '';
    private const S_BT        = '`';
    private const S_DS        = '$';
    private const S_DT        = '.';
    private const S_CN        = ':';
    private const S_KEY       = 'KEY';

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
    private static function isListHelper(array $val): bool {
        return array_keys($val) === range(0, count($val) - 1);
    }

    /* =======================
     * Type and Existence Checks
     * =======================
     */

    /**
     * Check if a value is a node (array or object) and not undefined.
     *
     * @param mixed $val
     * @return bool
     */
    public static function isnode(mixed $val): bool {
        return $val !== self::UNDEF && $val !== null && (is_array($val) || is_object($val));
    }

    /**
     * Check if a value is a map (associative array or object) rather than a list.
     *
     * @param mixed $val
     * @return bool
     */
    public static function ismap(mixed $val): bool {
        if ($val === self::UNDEF || $val === null) {
            return false;
        }
        if (is_array($val)) {
            return !self::isListHelper($val);
        }
        return is_object($val);
    }

    /**
     * Check if a value is a list (sequential array).
     *
     * @param mixed $val
     * @return bool
     */
    public static function islist(mixed $val): bool {
        return is_array($val) && self::isListHelper($val);
    }

    /**
     * Check if a key is valid (non-empty string or integer/float).
     *
     * @param mixed $key
     * @return bool
     */
    public static function iskey(mixed $key): bool {
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
    public static function isempty(mixed $val): bool {
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
    public static function isfunc(mixed $val): bool {
        return is_callable($val);
    }

    /**
     * Normalize and return a type string for a given value.
     * Possible return values include 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'.
     *
     * @param mixed $value
     * @return string
     */
    public static function typify(mixed $value): string {
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

    /* =======================
     * Property Access and Manipulation
     * =======================
     */

    /**
     * Safely retrieves a property from an array or object.
     * If the key is not found, returns the alternative value.
     *
     * @param mixed $val Source array or object.
     * @param mixed $key Property key.
     * @param mixed $alt Alternative value to return if key is not found.
     * @return mixed
     */
    public static function getprop(mixed $val, mixed $key, mixed $alt = self::UNDEF): mixed {
        if ($val === self::UNDEF || $key === self::UNDEF) {
            return $alt;
        }
        if (!self::iskey($key)) {
            return $alt;
        }
        if ($val === null) {
            return $alt;
        }
        if (is_array($val) && array_key_exists($key, $val)) {
            $out = $val[$key];
        } elseif (is_object($val) && property_exists($val, $key)) {
            $out = $val->$key;
        } else {
            $out = $alt;
        }
        return $out === self::UNDEF ? $alt : $out;
    }

    /**
     * Convert different types of keys to their string representation.
     *
     * @param mixed $key
     * @return string
     */
    public static function strkey(mixed $key = self::UNDEF): string {
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
            return (string)$key;
        }
        if (is_float($key)) {
            return (string)floor($key);
        }
        return self::S_MT;
    }

    /**
     * Get a sorted list of keys from a node (map or list).
     *
     * @param mixed $val
     * @return array
     */
    public static function keysof(mixed $val): array {
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
    public static function haskey(mixed $val = self::UNDEF, mixed $key = self::UNDEF): bool {
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

    /**
     * Return an array of key-value pair items from a node.
     *
     * @param mixed $val
     * @return array An array of [key, value] pairs.
     */
    public static function items(mixed $val): array {
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

    /* =======================
     * String and URL Utilities
     * =======================
     */

    /**
     * Escape a string for safe use in a regular expression.
     *
     * @param string|null $s
     * @return string
     */
    public static function escre(?string $s): string {
        $s = $s ?? self::S_MT;
        return preg_quote($s, '/');
    }

    /**
     * Escape a string for safe use in a URL.
     *
     * @param string|null $s
     * @return string
     */
    public static function escurl(?string $s): string {
        $s = $s ?? self::S_MT;
        return rawurlencode($s);
    }

    /**
     * Join URL components together, merging duplicate slashes appropriately.
     *
     * @param array $sarr Array of URL parts.
     * @return string
     */
    public static function joinurl(array $sarr): string {
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
    private static function sort_obj(mixed $val): mixed {
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

    /**
     * Generate a human-friendly string representation of a node.
     * Note that this function is for display purposes and not for data serialization.
     *
     * @param mixed $val
     * @param int|null $maxlen Optional maximum string length.
     * @return string
     */
    public static function stringify(mixed $val, ?int $maxlen = null): string {
        if ($val === self::UNDEF) {
            return self::S_MT;
        }
        try {
            $sorted = self::sort_obj($val);
            $str = json_encode($sorted);
        } catch (\Exception $e) {
            $str = self::S_MT . (string)$val;
        }
        if (!is_string($str)) {
            $str = self::S_MT . $str;
        }
        $str = str_replace('"', '', $str);
        if ($maxlen !== null && strlen($str) > $maxlen) {
            $str = substr($str, 0, $maxlen - 3) . '...';
        }
        return $str;
    }

    /**
     * Build a human-friendly "path" string from a node.
     * If the node is not a list, returns a marker including its stringified value.
     *
     * @param mixed $val A node, or value to be converted into a path.
     * @param int|null $from Starting index for path slicing.
     * @param bool $pathDefined Indicates that the value was provided via a "path" key.
     * @return string
     */
    public static function pathify(mixed $val, ?int $from = null, bool $pathDefined = false): string {
        error_log('Pathify input: ' . json_encode($val));
        
        if ($val === self::UNDEF) {
            return '<unknown-path>';
        }
        
        // Handle objects first.
        if (is_object($val)) {
            return '<unknown-path' . self::S_CN . self::stringify($val, 47) . '>';
        }
        
        // Process arrays.
        if (is_array($val)) {
            echo 'Processing array: ' . json_encode($val) . PHP_EOL;
            // Immediate handling for empty arrays:
                if (empty($val)) {
                    error_log('Processing array 111: ' . json_encode($val));
                    error_log('Pathify input: ' . $pathDefined);
                    return $pathDefined ? '<root>' : '<unknown-path>';
                }
                
            // For nonempty arrays, distinguish between a list and an associative array.
            if (self::islist($val)) {
                $path = $val;
            } else {
                return '<unknown-path' . self::S_CN . self::stringify($val, 47) . '>';
            }
        } elseif (is_string($val) || is_numeric($val)) {
            // Wrap scalars into a one-element list.
            $path = [$val];
        } else {
            // Handle booleans and null.
            if ($val === null) {
                return '<unknown-path:null>';
            }
            if (is_bool($val)) {
                return '<unknown-path:' . ($val ? 'true' : 'false') . '>';
            }
            return '<unknown-path' . self::S_CN . self::stringify($val, 47) . '>';
        }
        
        // At this point, $path is a nonempty list.
        $start = ($from === null || $from < 0) ? 0 : $from;
        $sliced = array_slice($path, $start);
        
        if (count($sliced) === 0) {
            return '<root>';
        }
        
        $filtered = [];
        foreach ($sliced as $p) {
            if (!self::iskey($p)) {
                continue;
            }
            if (is_int($p)) {
                $filtered[] = (string)$p;
            } elseif (is_float($p)) {
                $filtered[] = (string)floor($p);
            } elseif (is_string($p)) {
                if (is_numeric($p) && strpos($p, '.') !== false) {
                    $filtered[] = str_replace('.', '', $p);
                } else {
                    $filtered[] = $p;
                }
            }
        }
        error_log('Filtered path: ' . json_encode($filtered));
        return implode(self::S_DT, $filtered);
    }
              

    /* =======================
     * Cloning
     * =======================
     */

    /**
     * Create a deep clone of a node.
     * Functions (callables) are cloned by reference via a marker mechanism.
     *
     * @param mixed $val
     * @return mixed
     */
    public static function clone_val(mixed $val): mixed {
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
                    return $refs[(int)$matches[1]];
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

    /* =======================
     * Property Setting
     * =======================
     */

    /**
     * Safely set a property in an array or object.
     * If $val is UNDEF, the property is removed. For lists (sequential arrays),
     * performs insertion, replacement, or removal based on the key.
     *
     * @param mixed $parent Reference to the parent array or object.
     * @param mixed $key The key to set.
     * @param mixed $val The value to set.
     * @return mixed The modified parent.
     */
    public static function setprop(mixed &$parent, mixed $key, mixed $val): mixed {
        if (!self::iskey($key)) {
            return $parent;
        }
        if (is_array($parent)) {
            if (!self::islist($parent)) {
                $keyStr = self::strkey($key);
                if ($val === self::UNDEF) {
                    unset($parent[$keyStr]);
                } else {
                    if (array_key_exists($keyStr, $parent)) {
                        $parent[$keyStr] = $val;
                    } else {
                        // Prepend the new key-value pair
                        $parent = [$keyStr => $val] + $parent;
                    }
                }
            } else {
                if (!is_numeric($key)) {
                    return $parent;
                }
                $keyI = (int) floor($key);
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
}
?>
