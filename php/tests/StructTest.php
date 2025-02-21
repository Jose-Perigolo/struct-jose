<?php

use PHPUnit\Framework\TestCase;
require_once __DIR__ . '/../src/Struct.php'; 
use Voxgig\Struct\Struct;

class StructTest extends TestCase {

    private array $testSpec;

    protected function setUp(): void {
        $jsonPath = __DIR__ . '/../../build/test/test.json';

        if (!file_exists($jsonPath)) {
            throw new RuntimeException("Test JSON file not found: $jsonPath");
        }

        $jsonContent = file_get_contents($jsonPath);
        if ($jsonContent === false) {
            throw new RuntimeException("Failed to read test JSON: $jsonPath");
        }

        $this->testSpec = json_decode($jsonContent, true);

        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new RuntimeException("Invalid JSON: " . json_last_error_msg());
        }
    }

    private function testSet(array $tests, callable $apply) {
        foreach ($tests['set'] as $entry) {
            try {
                $result = $apply($entry['in'] ?? null);
                if (isset($entry['out'])) {
                    $this->assertEquals($entry['out'], $result);
                }
            } catch (Throwable $err) {
                if (isset($entry['err'])) {
                    $this->assertStringContainsString($entry['err'], $err->getMessage());
                } else {
                    throw $err;
                }
            }
        }
    }

    public static function nullModifier($key, $val, &$parent) {
        if ($val === '__NULL__') {
            call_user_func_array([Struct::class, 'setProp'], [&$parent, $key, null]);
        } elseif (is_string($val)) {
            $newVal = str_replace('__NULL__', 'null', $val);
            call_user_func_array([Struct::class, 'setProp'], [&$parent, $key, $newVal]);
        }
    }    

    public function testMinorFunctionsExist() {
        $methods = ['clone', 'isNode', 'isMap', 'isList', 'isKey', 'isEmpty', 'stringify', 'escre', 'escurl', 'items', 'getProp', 'setProp', 'getPath'];
        foreach ($methods as $method) {
            $this->assertTrue(method_exists(Struct::class, $method), "Method $method does not exist.");
        }
    }

    public function testClone() {
        $this->testSet($this->testSpec['minor']['clone'], [Struct::class, 'clone']);
    }

    public function testIsNode() {
        $this->testSet($this->testSpec['minor']['isnode'], [Struct::class, 'isNode']);
    }

    public function testIsMap() {
        $this->testSet($this->testSpec['minor']['ismap'], [Struct::class, 'isMap']);
    }

    public function testIsList() {
        $this->testSet($this->testSpec['minor']['islist'], [Struct::class, 'isList']);
    }

    public function testIsKey() {
        $this->testSet($this->testSpec['minor']['iskey'], [Struct::class, 'isKey']);
    }

    public function testIsEmpty() {
        $this->testSet($this->testSpec['minor']['isempty'], [Struct::class, 'isEmpty']);
    }

    public function testEscre() {
        $this->testSet($this->testSpec['minor']['escre'], [Struct::class, 'escre']);
    }

    public function testEscurl() {
        $this->testSet($this->testSpec['minor']['escurl'], [Struct::class, 'escurl']);
    }

    public function testStringify() {
        $this->testSet($this->testSpec['minor']['stringify'], fn($input) => isset($input['max']) ? Struct::stringify($input['val'], $input['max']) : Struct::stringify($input['val']));
    }

    public function testItems() {
        $this->testSet($this->testSpec['minor']['items'], [Struct::class, 'items']);
    }

    public function testGetProp() {
        $this->testSet($this->testSpec['minor']['getprop'], fn($input) => isset($input['alt']) ? Struct::getProp($input['val'], $input['key'], $input['alt']) : Struct::getProp($input['val'], $input['key']));
    }

    public function testGetPathBasic() {
        $this->testSet(
            $this->testSpec['getpath']['basic'],
            fn($input) => Struct::getPath(
                $input['path'] ?? null, 
                $input['store'] ?? null
            )
        );
    }

    public function testGetPathCurrent() {
        $this->testSet($this->testSpec['getpath']['current'], fn($input) => Struct::getPath($input['path'], $input['store'], $input['current']));
    }

    public function testGetPathState() {
        $state = $this->createState();
        $this->testSet($this->testSpec['getpath']['state'], fn($input) => Struct::getPath($input['path'], $input['store'], $input['current'] ?? null, $state));
    }

    private function createState(): object {
        $state = new \stdClass();
        $state->handler = function ($state, $val) {
            $out = $state->step . ':' . $val;
            $state->step++;
            return $out;
        };
        $state->step = 0;
        $state->mode = 'val';
        $state->full = false;
        $state->keyI = 0;
        $state->keys = ['$TOP'];
        $state->key = '$TOP';
        $state->val = '';
        $state->parent = [];
        $state->path = ['$TOP'];
        $state->nodes = [[]];
        $state->base = '$TOP';
        return $state;
    }

    public function testWalkExists() {
        $this->assertTrue(method_exists(Struct::class, 'walk'), "Method walk does not exist.");
    }
    
    public function testWalkBasic() {
        $this->testSet($this->testSpec['walk']['basic'], function($vin) {
            return Struct::walk($vin, function($key, $val, $parent, $path) {
                return is_string($val) ? $val . '~' . implode('.', $path) : $val;
            });
        });
    }    

    public function testMergeExists() {
        $this->assertTrue(method_exists(Struct::class, 'merge'));
    }
    
    public function testMergeBasic() {
        $test = $this->testSpec['merge']['basic'];
        $this->assertEquals($test['out'], Struct::merge($test['in']));
    }
    
    public function testMergeCases() {
        $this->testSet($this->testSpec['merge']['cases'], [Struct::class, 'merge']);
    }
    
    public function testMergeArray() {
        $this->testSet($this->testSpec['merge']['array'], [Struct::class, 'merge']);
    }

    public function testInjectExists() {
        $this->assertTrue(method_exists(Struct::class, 'inject'));
    }

    public function testInjectBasic() {
        $test = $this->testSpec['inject']['basic'];
        $this->assertEquals($test['out'], Struct::inject($test['in']['val'], $test['in']['store']));
    }

    public function testInjectString() {
        $this->testSet($this->testSpec['inject']['string'], fn($input) => Struct::inject($input['val'], $input['store'], [self::class, 'nullModifier'], $input['current'] ?? null));
    }

    public function testInjectDeep() {
        $this->testSet($this->testSpec['inject']['deep'], fn($input) => Struct::inject($input['val'], $input['store']));
    }

    public function testTransformExists() {
        $this->assertTrue(method_exists(Struct::class, 'transform'), "Method transform does not exist.");
    }

    public function testTransformBasic() {
        $test = $this->testSpec['transform']['basic'];
        $result = Struct::transform($test['in']['data'], $test['in']['spec'], $test['in']['store'] ?? null);
        $this->assertEquals($test['out'], $result);
    }

    public function testTransformPaths() {
        $this->testSet($this->testSpec['transform']['paths'], function($vin) {
            return Struct::transform($vin['data'] ?? null, $vin['spec'] ?? null, $vin['store'] ?? null);
        });
    }

    public function testTransformCmds() {
        $this->testSet($this->testSpec['transform']['cmds'], function($vin) {
            return Struct::transform($vin['data'] ?? null, $vin['spec'] ?? null, $vin['store'] ?? null);
        });
    }

    public function testTransformEach() {
        $this->testSet($this->testSpec['transform']['each'], function($vin) {
            return Struct::transform($vin['data'] ?? null, $vin['spec'] ?? null, $vin['store'] ?? null);
        });
    }

    public function testTransformPack() {
        $this->testSet($this->testSpec['transform']['pack'], function($vin) {
            return Struct::transform($vin['data'] ?? null, $vin['spec'] ?? null, $vin['store'] ?? null);
        });
    }

    public function testTransformModify() {
        $this->testSet($this->testSpec['transform']['modify'], function($vin) {
            return Struct::transform(
                $vin['data'] ?? null,
                $vin['spec'] ?? null,
                $vin['store'] ?? null,
                function($key, $val, &$parent) {
                    if ($key !== null && $parent !== null && is_string($val)) {
                        $parent[$key] = '@' . $val;
                    }
                }
            );
        });
    }

    public function testTransformExtra() {
        $result = Struct::transform(
            ['a' => 1],
            ['x' => '`a`', 'b' => '`$COPY`', 'c' => '`$UPPER`'],
            [
                'b' => 2,
                '$UPPER' => function($state) {
                    // Assume $state['path'] is an array and return the last element uppercased.
                    $path = $state['path'] ?? [];
                    return strtoupper((string) end($path));
                }
            ]
        );
        $this->assertEquals(['x' => 1, 'b' => 2, 'c' => 'C'], $result);
    }
    
}

?>