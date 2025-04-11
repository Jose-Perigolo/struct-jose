<?php

require_once __DIR__ . '/../src/Struct.php';

use PHPUnit\Framework\TestCase;
use Voxgig\Struct\Struct;

class StructTest extends TestCase {

    private array $testSpec;

    protected function setUp(): void {
        // Adjust this path as needed.
        $jsonPath = __DIR__ . '/../../build/test/test.json';
        if (!file_exists($jsonPath)) {
            throw new RuntimeException("Test JSON file not found: $jsonPath");
        }
        $jsonContent = file_get_contents($jsonPath);
        if ($jsonContent === false) {
            throw new RuntimeException("Failed to read test JSON: $jsonPath");
        }
        $data = json_decode($jsonContent, true);
        if (!isset($data['struct'])) {
            throw new RuntimeException("'struct' key not found in the test JSON file.");
        }
        $this->testSpec = $data['struct'];
        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new RuntimeException("Invalid JSON: " . json_last_error_msg());
        }
    }

    /**
     * A helper that loops over test entries (in a "set")
     * and applies the given function to the "in" value.
     * If an expected "out" is specified, it asserts equality.
     * If an error is expected, the error message is checked.
     */
    private function testSet(array $tests, callable $apply): void {
        foreach ($tests['set'] as $index => $entry) {
            try {
                if (array_key_exists('args', $entry)) {
                    $args = $entry['args'];
                    $result = $apply(...$args);
                    $inputForMessage = $args; // Use args for error reporting
                } else {
                    $input = array_key_exists('in', $entry) ? $entry['in'] : Struct::UNDEF;
                    $result = $apply($input);
                    $inputForMessage = $input;
                }
    
                if (isset($entry['out'])) {
                    $this->assertSame(
                        $entry['out'],
                        $result,
                        "Input " . json_encode($inputForMessage) . " did not produce expected output."
                    );
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

    public function testIsnode() {
        $this->testSet($this->testSpec['minor']['isnode'], [Struct::class, 'isnode']);
    }

    public function testIsmap() {
        $this->testSet($this->testSpec['minor']['ismap'], [Struct::class, 'ismap']);
    }

    public function testIslist() {
        $this->testSet($this->testSpec['minor']['islist'], [Struct::class, 'islist']);
    }

    public function testIskey() {
        $this->testSet($this->testSpec['minor']['iskey'], [Struct::class, 'iskey']);
    }

    public function testIsempty() {
        $this->testSet($this->testSpec['minor']['isempty'], [Struct::class, 'isempty']);
    }

    public function testIsfunc() {
        $this->testSet($this->testSpec['minor']['isfunc'], [Struct::class, 'isfunc']);
    }

    public function testTypify() {
        $this->testSet($this->testSpec['minor']['typify'], [Struct::class, 'typify']);
    }

    public function testGetprop() {
        $this->testSet($this->testSpec['minor']['getprop'], function($input) {
            if (!array_key_exists('val', $input) || !array_key_exists('key', $input)) {
                error_log("Missing 'val' or 'key' in input: " . print_r($input, true));
                // You may choose to return a default value:
                return null;
            }
            return isset($input['alt'])
                ? Struct::getprop($input['val'], $input['key'], $input['alt'])
                : Struct::getprop($input['val'], $input['key']);
        });
    }    

    public function testStrkey() {
        $this->testSet($this->testSpec['minor']['strkey'], [Struct::class, 'strkey']);
    }

    public function testKeysof() {
        $this->testSet($this->testSpec['minor']['keysof'], [Struct::class, 'keysof']);
    }

    public function testHaskey() {
        $spec = $this->testSpec['minor']['haskey'];
        $this->testSet($spec, function (...$args) {
            // Directly pass args to haskey without modification
            return Struct::haskey(...$args);
        });
    }
           
    
    public function testItems() {
        $this->testSet($this->testSpec['minor']['items'], [Struct::class, 'items']);
    }

    public function testEscre() {
        $this->testSet($this->testSpec['minor']['escre'], [Struct::class, 'escre']);
    }

    public function testEscurl() {
        $this->testSet($this->testSpec['minor']['escurl'], [Struct::class, 'escurl']);
    }

    public function testJoinurl() {
        $this->testSet($this->testSpec['minor']['joinurl'], [Struct::class, 'joinurl']);
    }

    public function testStringify() {
        $this->testSet($this->testSpec['minor']['stringify'], function ($input) {
            // If "val" is not given, use the special undefined marker.
            $val = array_key_exists('val', $input) ? $input['val'] : '__UNDEFINED__';
            return isset($input['max'])
                ? Struct::stringify($val, $input['max'])
                : Struct::stringify($val);
        });
    }
    
    // public function testPathify() {
    //     $this->testSet($this->testSpec['minor']['pathify'], function ($input) {
    //         $pathDefined = array_key_exists('path', $input);
    //         $path = $pathDefined ? $input['path'] : $input;
    //         $from = $input['from'] ?? null;
    //         return Struct::pathify($path, $from, $pathDefined);
    //     });
    // }
    

    public function testClone() {
        $this->testSet($this->testSpec['minor']['clone'], [Struct::class, 'clone_val']);
    }

    // public function testSetprop() {
    //     $this->testSet($this->testSpec['minor']['setprop'], function ($input) {
    //         $parent = array_key_exists('parent', $input) ? $input['parent'] : [];
    //         $val = array_key_exists('val', $input) ? $input['val'] : '__UNDEFINED__';
    //         return Struct::setprop($parent, $input['key'] ?? null, $val);
    //     });
    // }    
    
}
