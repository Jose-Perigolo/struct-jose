<?php

namespace Voxgig\Struct;

class Struct {

    private const S = [
        'MKEYPRE'  => 'key:pre',
        'MKEYPOST' => 'key:post',
        'MVAL'     => 'val',
        'DTOP'     => '$TOP',
        'object'   => 'object',
        'number'   => 'number',
        'string'   => 'string',
        'function' => 'function',
        'empty'    => '',
        'base'     => 'base',
        'BT'       => '`',
        'DS'       => '$',
        'DT'       => '.',
        // Keys used in transforms:
        'TKEY'     => '`$KEY`',
        'TMETA'    => '`$META`',
        'KEY'      => 'KEY',
    ];
    

    public static function isNode($val): bool {
        return is_array($val) || is_object($val);
    }

    public static function isMap($val): bool {
        return is_array($val) && array_values($val) !== $val;
    }

    public static function isList($val): bool {
        return is_array($val) && array_values($val) === $val;
    }

    public static function isKey($key): bool {
        return is_string($key) && $key !== "" || is_int($key);
    }

    public static function clone($val) {
        return json_decode(json_encode($val), true);
    }

    public static function items($val): array {
        if (self::isMap($val)) {
            return array_map(null, array_keys($val), array_values($val));
        }
        if (self::isList($val)) {
            return array_map(fn($v, $k) => [$k, $v], $val, array_keys($val));
        }
        return [];
    }

    public static function getProp($val, $key, $alt = null) {
        if ($key === null) {
            return $alt;
        }
        if (is_array($key)) { 
            return $alt;
        }
        if (!is_string($key) && !is_int($key)) {
            throw new \TypeError("Invalid key type: " . gettype($key));
        }
        return isset($val[$key]) ? $val[$key] : $alt;
    }
    

    public static function setProp(&$parent, $key, $val) {
        if (!self::isKey($key)) return;
        if (!is_array($parent)) throw new \TypeError("Parent must be an array.");
        if ($val === null) {
            unset($parent[$key]);
        } else {
            if (isset($parent[$key]) && $parent[$key] === $val) return;
            $parent[$key] = $val;
        }
    }

    public static function merge($objs) {
        if ($objs === null) {
            return null;
        }
        if (!self::isList($objs)) {
            return $objs;
        }
        $count = count($objs);
        if ($count === 0) {
            return null;
        }
        if ($count === 1) {
            return self::clone($objs[0]);
        }
    
        $out = self::clone($objs[0]);
    
        for ($oI = 1; $oI < $count; $oI++) {
            $obj = $objs[$oI];
    
            if (!self::isNode($obj)) {
                $out = $obj;
                continue;
            }
    
            $isObjMap = self::isMap($obj);
            $isOutMap = self::isMap($out);
    
            // Treat empty arrays as the same type as $out
            if (is_array($obj) && empty($obj)) {
                $isObjMap = $isOutMap;
            }
    
            if (!self::isNode($out) || ($isObjMap !== $isOutMap)) {
                $out = self::clone($obj);
                continue;
            }
    
            foreach (self::items($obj) as $item) {
                $key = $item[0];
                $val = $item[1];
                $currentVal = self::getProp($out, $key);
    
                if (self::isNode($val)) {
                    $isValMap = self::isMap($val);
                    $isCurrentMap = self::isMap($currentVal);
                    if (!self::isNode($currentVal) || ($isValMap !== $isCurrentMap)) {
                        self::setProp($out, $key, self::clone($val));
                    } else {
                        self::setProp($out, $key, self::merge([$currentVal, $val]));
                    }
                } else {
                    self::setProp($out, $key, $val);
                }
            }
        }
    
        return $out;
    }

    public static function isEmpty($val): bool {
        return $val === null || $val === "" || $val === false || $val === 0 || (is_array($val) && count($val) === 0);
    }

    public static function stringify($val, $maxlen = null): string {
        if ($val === false) return "false";
        $json = is_array($val) || is_object($val) ? json_encode($val) : (string)$val;
        if ($json === false) return "";
        $json = str_replace('"', '', $json);
        return $maxlen !== null && strlen($json) > $maxlen ? substr($json, 0, $maxlen - 3) . "..." : $json;
    }

    public static function escre(string $s): string {
        return preg_quote($s, '/');
    }

    public static function escurl(string $s): string {
        return rawurlencode($s);
    }

    public static function getPath($path, $store, $current = null, $state = null) {
        $parts = is_array($path)
            ? $path
            : (is_string($path) ? explode(self::S['DT'], $path) : null);
        if ($parts === null) return null;
        error_log("getPath called with path: " . json_encode($path));
    
        $root = $store;
        $val  = $store;
        $base = $state ? (is_array($state) ? ($state['base'] ?? null) : ($state->base ?? null)) : null;
        
        if ($path === null || $store === null || (count($parts) === 1 && $parts[0] === '')) {
            $val = self::getProp($store, $base, $store);
        } else if (count($parts) > 0) {
            $pI = 0;
            if ($parts[0] === '') {
                $pI = 1;
                $root = $current;
            }
            $part = $parts[$pI] ?? null;
            $first = self::getProp($root, $part);
            $val = ($first === null && $pI === 0)
                ? self::getProp(self::getProp($root, $base), $part)
                : $first;
                
                for ($pI++; $val !== null && $pI < count($parts); $pI++) {
                    $val = self::getProp($val, $parts[$pI] ?? null);
            }
        }
    
        if ($state !== null) {
            $handler = is_array($state)
                ? ($state['handler'] ?? null)
                : ($state->handler ?? null);
                if ($handler && is_callable($handler)) {
                $val = call_user_func($handler, $state, $val, $current, $store);
            }
        }
        error_log("getPath resolved value: " . json_encode($val));
        return $val;
    }
    

    public static function injectHandler($state, $val, $current, $store) {
        if (is_callable($val)) return call_user_func($val, $state, $val, $current, $store);
        if ($state['mode'] === self::S['MVAL'] && $state['full']) self::setProp($state['parent'], $state['key'], $val);
        return $val;
    }

    public static function injectStr($val, $store, $current = null, $state = null) {
        if (!is_string($val)) return $val;
        if (preg_match('/^`([^`]+)`$/', $val, $matches)) {
            $ref = str_replace(['$BT', '$DS'], [self::S['BT'], self::S['DS']], $matches[1]);
            $result = self::getPath($ref, $store, $current, $state);
            return $result === null ? null : $result;
        }
        return preg_replace_callback('/`([^`]+)`/', function ($m) use ($store, $current, $state) {
            $ref = str_replace(['$BT', '$DS'], [self::S['BT'], self::S['DS']], $m[1]);
            $found = self::getPath($ref, $store, $current, $state);
            if ($found === null) {
                error_log("injectStr could not find path: " . $ref);
            }            
            if ($found === null && array_key_exists($ref, $store)) return 'null';
            if ($found === null) return '';
            if (is_bool($found)) return $found ? 'true' : 'false';
            if (is_array($found)) return json_encode($found);
            return (string)$found;
        }, $val);
    }

    public static function inject(&$val, $store, $modify = null, $current = null, $state = null) {
        if ($state === null) {
            $parent = [self::S['DTOP'] => &$val];
            $state = [
                'mode' => self::S['MVAL'],
                'full' => false,
                'keyI' => 0,
                'keys' => [self::S['DTOP']],
                'key' => self::S['DTOP'],
                'val' => &$val,
                'parent' => &$parent,
                'path' => [self::S['DTOP']],
                'nodes' => [&$parent],
                'handler' => [self::class, 'injectHandler'],
                'base' => self::S['DTOP'],
                'modify' => $modify
            ];
            $result = self::inject($val, $store, $modify, $current, $state);
            return self::getProp($parent, self::S['DTOP']);
        }

        if ($state !== null && isset($store['$TOP'])) {
            $pathParts = $state['path'];
            if (count($pathParts) > 0 && $pathParts[0] === self::S['DTOP']) {
                array_shift($pathParts);
            }
            $current = empty($pathParts)
                ? $store['$TOP']
                : self::getPath(implode(self::S['DT'], $pathParts), $store['$TOP']);
        }

        if ($current === null) {
            $current = [self::S['DTOP'] => $store];
        } else {
            $parentKey = $state['path'][count($state['path']) - 2] ?? null;
            $current = $parentKey === null ? $current : self::getProp($current, $parentKey);
        }

        if (self::isNode($val)) {
            $keys = self::isMap($val) 
                ? array_merge(
                    array_filter(array_keys($val), fn($k) => strpos($k, self::S['DS']) === false),
                    array_filter(array_keys($val), fn($k) => strpos($k, self::S['DS']) !== false)
                  )
                : range(0, count($val) - 1);
        
            foreach ($keys as $i => $origKey) {
                $childState = $state;
                $childState['mode'] = self::S['MKEYPRE'];
                $childState['key'] = $origKey;
                $childState['keyI'] = $i;
                $childState['parent'] = &$val;
                $preKey = self::injectStr((string)$origKey, $store, $current, $childState);
                if ($preKey !== null) {
                    $child = self::getProp($val, $preKey);
                    // Calculate new current data context
                    $newCurrent = self::getProp($current, $preKey);
                    // Update the state path and node chain:
                    $childState['path'] = array_merge($state['path'], [$preKey]);
                    $childState['nodes'] = array_merge($state['nodes'], [$child]);
                    $childState['mode'] = self::S['MVAL'];
                    // Pass $newCurrent as the current context for the child
                    $child = self::inject($child, $store, $modify, $newCurrent, $childState);
                    self::setProp($val, $preKey, $child);
                    $childState['mode'] = self::S['MKEYPOST'];
                    self::injectStr((string)$origKey, $store, $current, $childState);
                }
            }
        }
         elseif (is_string($val)) {
            $state['mode'] = self::S['MVAL'];
            $injectedVal = self::injectStr($val, $store, $current, $state);
            self::setProp($state['parent'], $state['key'], $injectedVal);
            $val = $injectedVal;
        }
        // In the inject method, adjust the call to the modifier
        if ($modify) {
            $parentParam = &$state['parent'];
            $modify($state['key'], $val, $parentParam, $state, $current, $store);
            // Re-read the value from parent after modification:
            $val = self::getProp($state['parent'], $state['key']);
        }
        return $val;

    }

    public static function walk($val, callable $apply, $key = null, &$parent = null, array $path = []) {
        if (self::isNode($val)) {
            foreach (self::items($val) as $item) {
                list($ckey, $child) = $item;
                // Build the new path by appending the current key (as a string)
                $newPath = array_merge($path, [(string)$ckey]);
                // Recursively process the child
                $childResult = self::walk($child, $apply, $ckey, $val, $newPath);
                // Replace the child with its processed result
                self::setProp($val, $ckey, $childResult);
            }
        }
        // Apply the callback after processing children
        return $apply($key, $val, $parent, $path);
    }

    public static function transform_DELETE($state) {
        $key = $state['key'];
        $parent = $state['parent'];
        self::setProp($parent, $key, null);
        return null;
    }
    
    // Copy value from source data.
    public static function transform_COPY($state, $_val, $current) {
        $mode = $state['mode'];
        $key = $state['key'];
        $parent = $state['parent'];
        if (strpos($mode, 'key:') === 0) {
            return $key;
        } else {
            $out = is_array($current)
                ? self::getProp($current, $key)
                : $current;
            self::setProp($parent, $key, $out);
            return $out;
        }
    }
    
    
    // As a value, inject the key of the parent node.
    // As a key, define the name of the key property in the source object.
    public static function transform_KEY($state, $_val, $current) {
        if ($state['mode'] !== self::S['MVAL']) {
            return null;
        }
        $keyspec = self::getProp($state['parent'], self::S['TKEY'], null);
        if ($keyspec !== null) {
            self::setProp($state['parent'], self::S['TKEY'], null);
            return self::getProp($current, $keyspec);
        }
        $meta = self::getProp($state['parent'], self::S['TMETA'], []);
        $defaultKey = (count($state['path']) >= 2) ? $state['path'][count($state['path']) - 2] : null;
        return self::getProp($meta, self::S['KEY'], $defaultKey);
    }
    
    // Store meta data about a node.
    public static function transform_META($state) {
        self::setProp($state['parent'], self::S['TMETA'], null);
        return null;
    }
    
    // Merge a list of objects into the current object.
    public static function transform_MERGE($state, $_val, $store) {
        $mode = $state['mode'];
        $key = $state['key'];
        $parent = $state['parent'];
        if ($mode === self::S['MKEYPRE']) {
            return $key;
        }
        if ($mode === self::S['MKEYPOST']) {
            $args = self::getProp($parent, $key);
            if ($args === self::S['empty']) {
                $args = [ $store['$TOP'] ];
            } elseif (!is_array($args)) {
                $args = [$args];
            }
            self::setProp($parent, $key, null);
            // Merge: parent's literal entries override entries from args.
            $mergelist = array_merge([$parent], $args, [self::clone($parent)]);
            self::setProp($parent, $key, self::merge($mergelist));
            return $key;
        }
        return null;
    }
    
    // Convert a node to a list.
    public static function transform_EACH($state, $_val, $current, $store) {
        // Remove extra keys to avoid spurious processing.
        if (isset($state['keys'])) {
            $state['keys'] = array_slice($state['keys'], 0, 1);
        }
        if ($state['mode'] !== self::S['MVAL'] || empty($state['path']) || empty($state['nodes'])) {
            return null;
        }
        // In the spec, parent[1] is the source path and parent[2] is the child template.
        $srcpath = self::getProp($state['parent'], 1);
        $child = self::clone(self::getProp($state['parent'], 2));
        $src = self::getPath($srcpath, $store, $current, $state);
        $tval = [];
        $tcurrent = [];
        $pathCount = count($state['path']);
        $tkey = ($pathCount >= 2) ? $state['path'][$pathCount - 2] : null;
        $target = isset($state['nodes'][$pathCount - 2]) ? $state['nodes'][$pathCount - 2] : end($state['nodes']);
        if (self::isNode($src)) {
            if (self::isList($src)) {
                foreach ($src as $_dummy) {
                    $tval[] = self::clone($child);
                }
                $tcurrent = array_values($src);
            } else {
                foreach ($src as $k => $v) {
                    $temp = self::clone($child);
                    self::setProp($temp, self::S['TMETA'], ['KEY' => $k]);
                    $tval[] = $temp;
                }
                $tcurrent = array_values($src);
            }
        }
        $tcurrent = ['$TOP' => $tcurrent];
        $tval = self::inject($tval, $store, $state['modify'] ?? null, $tcurrent);
        self::setProp($target, $tkey, $tval);
        return isset($tval[0]) ? $tval[0] : null;
    }
    
    // Convert a node to a map.
    public static function transform_PACK($state, $_val, $current, $store) {
        if ($state['mode'] !== self::S['MKEYPRE'] || !is_string($state['key']) || empty($state['path']) || empty($state['nodes'])) {
            return null;
        }
        $args = self::getProp($state['parent'], $state['key']);
        if (!is_array($args) || count($args) < 2) {
            return null;
        }
        $srcpath = $args[0]; // Source path
        $child = self::clone(self::getProp($args, 1)); // Child template
        $keyprop = self::getProp($child, self::S['TKEY']);
        $pathCount = count($state['path']);
        $tkey = ($pathCount >= 2) ? $state['path'][$pathCount - 2] : null;
        $target = isset($state['nodes'][$pathCount - 2]) ? $state['nodes'][$pathCount - 2] : end($state['nodes']);
        $src = self::getPath($srcpath, $store, $current, $state);
        if (self::isList($src)) {
            // Already a list.
        } elseif (self::isMap($src)) {
            $temp = [];
            foreach ($src as $k => $v) {
                $v[self::S['TMETA']] = ['KEY' => $k];
                $temp[] = $v;
            }
            $src = $temp;
        } else {
            $src = null;
        }
        if ($src === null) {
            return null;
        }
        $childkey = self::getProp($child, self::S['TKEY']);
        $keyname = ($childkey === null) ? $keyprop : $childkey;
        self::setProp($child, self::S['TKEY'], null);
        $tval = [];
        foreach ($src as $n) {
            $kn = self::getProp($n, $keyname);
            $tval[$kn] = self::clone($child);
            $nchild = $tval[$kn];
            self::setProp($nchild, self::S['TMETA'], self::getProp($n, self::S['TMETA']));
        }
        $tcurrent = ['$TOP' => []];
        foreach ($src as $n) {
            $kn = self::getProp($n, $keyname);
            $tcurrent['$TOP'][$kn] = $n;
        }
        $tval = self::inject($tval, $store, $state['modify'] ?? null, $tcurrent);
        self::setProp($target, $tkey, $tval);
        // REMOVE the original transform marker from the parent.
        self::setProp($state['parent'], $state['key'], null);
        return null;
    }
    
    
    // Main transform function.
    public static function transform($data, $spec, $extra = null, $modify = null) {
        $extraTransforms = [];
        $extraData = ($extra === null) ? [] : $extra;
        foreach (self::items($extraData) as $item) {
            $k = $item[0];
            $v = $item[1];
            if (strpos($k, self::S['DS']) === 0) {
                $extraTransforms[$k] = $v;
            }
        }
        $dataClone = self::merge([self::clone($extraData), self::clone($data)]);
        $store = array_merge($extraTransforms, [
            '$TOP'    => $dataClone,
            '$BT'     => function() { return self::S['BT']; },
            '$DS'     => function() { return self::S['DS']; },
            '$WHEN'   => function() { return date('c'); },
            '$DELETE' => [self::class, 'transform_DELETE'],
            '$COPY'   => [self::class, 'transform_COPY'],
            '$KEY'    => [self::class, 'transform_KEY'],
            '$META'   => [self::class, 'transform_META'],
            '$MERGE'  => [self::class, 'transform_MERGE'],
            '$EACH'   => [self::class, 'transform_EACH'],
            '$PACK'   => [self::class, 'transform_PACK'],
        ]);
        // Pass the merged data as the "current" context.
        $out = self::inject($spec, $store, $modify, $dataClone);
        return $out;
    }
    

}

?>