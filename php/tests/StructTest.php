<?php

require_once __DIR__ . '/../src/Struct.php';
require_once __DIR__ . '/Runner.php';

use PHPUnit\Framework\TestCase;
use Voxgig\Struct\Struct;

class StructTest extends TestCase
{

    private stdClass $testSpec;

    protected function setUp(): void
    {
        $jsonPath = __DIR__ . '/../../build/test/test.json';
        if (!file_exists($jsonPath)) {
            throw new RuntimeException("Test JSON file not found: $jsonPath");
        }
        $jsonContent = file_get_contents($jsonPath);
        if ($jsonContent === false) {
            throw new RuntimeException("Failed to read test JSON: $jsonPath");
        }
        // decode objects as stdClass, arrays as PHP arrays
        $data = json_decode($jsonContent, false);
        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new RuntimeException("Invalid JSON: " . json_last_error_msg());
        }
        if (!isset($data->struct)) {
            throw new RuntimeException("'struct' key not found in the test JSON file.");
        }
        $this->testSpec = $data->struct;
    }

    /**
     * Helper that loops over each entry in $tests->set, calls $apply, then asserts:
     *  - deep‐equals (assertEquals) if $forceEquals===true or expected is array/object,
     *  - strict‐same (assertSame) otherwise.
     *
     * @param stdClass       $tests        The spec object (has ->set array)
     * @param callable       $apply        Function to call on each entry’s input
     * @param bool           $forceEquals Whether to always use deep equality
     */
    private function testSet(stdClass $tests, callable $apply, bool $forceEquals = false): void
    {
        foreach ($tests->set as $i => $entry) {
            // 1) Determine input
            if (property_exists($entry, 'args')) {
                $inForMsg = $entry->args;
                $result = $apply(...$entry->args);
            } else {
                $in = property_exists($entry, 'in') ? $entry->in : Struct::UNDEF;
                $inForMsg = $in;
                $result = $apply($in);
            }

            // 2) If no expected 'out', skip
            if (!property_exists($entry, 'out')) {
                continue;
            }
            $expected = $entry->out;

            // 3) Choose assertion
            if ($forceEquals || is_array($expected) || is_object($expected)) {
                $this->assertEquals(
                    $expected,
                    $result,
                    "Entry #{$i} failed deep‐equal. Input: " . json_encode($inForMsg)
                );
            } else {
                $this->assertSame(
                    $expected,
                    $result,
                    "Entry #{$i} failed strict. Input: " . json_encode($inForMsg)
                );
            }
        }
    }

    // ——— Minor/simple tests ———
    public function testIsnode()
    {
        $this->testSet($this->testSpec->minor->isnode, [Struct::class, 'isnode']);
    }
    public function testIsmap()
    {
        $this->testSet($this->testSpec->minor->ismap, [Struct::class, 'ismap']);
    }
    public function testIslist()
    {
        $this->testSet($this->testSpec->minor->islist, [Struct::class, 'islist']);
    }
    public function testIskey()
    {
        $this->testSet($this->testSpec->minor->iskey, [Struct::class, 'iskey']);
    }
    public function testIsempty()
    {
        $this->testSet($this->testSpec->minor->isempty, [Struct::class, 'isempty']);
    }
    public function testIsfunc()
    {
        $this->testSet($this->testSpec->minor->isfunc, [Struct::class, 'isfunc']);
    }
    public function testTypify()
    {
        $this->testSet($this->testSpec->minor->typify, [Struct::class, 'typify']);
    }

    // ——— getprop needs to extract stdClass props ———
    public function testGetprop(): void
    {
        $this->testSet(
            $this->testSpec->minor->getprop,
            function ($input) {
                $val = property_exists($input, 'val') ? $input->val : Struct::UNDEF;
                $key = property_exists($input, 'key') ? $input->key : Struct::UNDEF;
                $alt = property_exists($input, 'alt') ? $input->alt : Struct::UNDEF;
                return Struct::getprop($val, $key, $alt);
            }
        );
    }

    // ——— Simple again ———
    public function testStrkey()
    {
        $this->testSet($this->testSpec->minor->strkey, [Struct::class, 'strkey']);
    }
    public function testKeysof()
    {
        $this->testSet($this->testSpec->minor->keysof, [Struct::class, 'keysof']);
    }

    // ——— items returns array of [key, stdClass/array], so deep-equal ———
    public function testItems(): void
    {
        $this->testSet(
            $this->testSpec->minor->items,
            fn($in) => Struct::items($in),
            /*forceEquals=*/ true
        );
    }

    public function testEscre()
    {
        $this->testSet($this->testSpec->minor->escre, [Struct::class, 'escre']);
    }
    public function testEscurl()
    {
        $this->testSet($this->testSpec->minor->escurl, [Struct::class, 'escurl']);
    }
    public function testJoinurl()
    {
        $this->testSet($this->testSpec->minor->joinurl, [Struct::class, 'joinurl']);
    }

    // ——— stringify returns strings but built from objects, so deep-equal ———
    public function testStringify(): void
    {
        $this->testSet(
            $this->testSpec->minor->stringify,
            function ($input) {
                $val = property_exists($input, 'val') ? $input->val : Struct::UNDEF;
                return property_exists($input, 'max')
                    ? Struct::stringify($val, $input->max)
                    : Struct::stringify($val);
            },
            true
        );
    }

    // ——— pathify returns strings but tests include null-marker tweaks ———
    public function testPathify(): void
    {
        $this->testSet(
            $this->testSpec->minor->pathify,
            function (stdClass $entry) {
                // 1) If the JSON had no "path" key at all, use our UNDEF marker.
                //    Otherwise take whatever value was there (could be null).
                $raw = property_exists($entry, 'path')
                    ? $entry->path
                    : Struct::UNDEF;

                // 2) TS does: path = (vin.path === NULLMARK ? undefined : vin.path)
                //    Our "undefined" is PHP null, so:
                $path = ($raw === Struct::UNDEF) ? null : $raw;

                // 3) Optional slice offset
                $from = property_exists($entry, 'from')
                    ? $entry->from
                    : null;

                // 4) Run PHP port of pathify
                $s = Struct::pathify($path, $from);

                // 5) Strip out any "__NULL__." fragments (TS’s replace)
                $s = str_replace(Struct::UNDEF . '.', '', $s);

                // 6) TS does: if vin.path === NULLMARK then add ":null>"
                //    In our convention, JSON null => raw === null (not UNDEF),
                //    so we inject only when raw === null.
                if ($raw === null) {
                    $s = str_replace('>', ':null>', $s);
                }

                return $s;
            },
            /* deep‐equal = */ true
        );
    }

    public function testClone(): void
    {
        $this->testSet(
            $this->testSpec->minor->clone,
            fn($in) => Struct::clone($in),
            true
        );
    }

    public function testSetprop(): void
    {
        $this->testSet(
            $this->testSpec->minor->setprop,
            function ($input) {
                $parent = property_exists($input, 'parent') ? $input->parent : [];
                $key = property_exists($input, 'key') ? $input->key : null;
                $val = property_exists($input, 'val') ? $input->val : Struct::UNDEF;
                return Struct::setprop($parent, $key, $val);
            },
            true
        );
    }

    public function testWalkLog(): void
    {
        // was $this->testSpec->major->walk->log
        $spec = $this->testSpec->walk->log;
        $input = Struct::clone($spec->in);

        $log = [];
        $walker = function ($key, $val, $parent, $path) use (&$log) {
            $kstr = ($key === null) ? '' : Struct::stringify($key);
            $pstr = ($parent === null) ? '' : Struct::stringify($parent);
            $log[] = "k={$kstr}, v="
                . Struct::stringify($val)
                . ", p={$pstr}, t="
                . Struct::pathify($path);
            return $val;
        };

        Struct::walk($input, $walker);

        $this->assertEquals(
            $spec->out,
            $log,
            "walk-log did not produce the expected trace"
        );
    }

    /**
     * @covers \Voxgig\Struct\Struct::walk
     */
    public function testWalkBasic(): void
    {
        // was $this->testSpec->major->walk->basic
        $this->testSet(
            $this->testSpec->walk->basic,
            function ($input) {
                return Struct::walk(
                    $input,
                    function ($_k, $v, $_p, $path) {
                        return is_string($v)
                            ? $v . '~' . implode('.', $path)
                            : $v;
                    }
                );
            },
            true
        );
    }


    public function testMergeBasic(): void
    {
        $spec = $this->testSpec->merge->basic;
        $in = Struct::clone($spec->in);
        $out = Struct::merge($in);

        $this->assertEquals(
            $spec->out,
            $out,
            "merge-basic did not produce the expected result"
        );
    }

    public function testMergeCases(): void
    {
        $this->testSet(
            $this->testSpec->merge->cases,
            // take the input array/val as-is, don’t try to read ->in again
            fn($in) => Struct::merge($in),
            /* force deep‐equal */ true
        );
    }

    public function testMergeArray(): void
    {
        $this->testSet(
            $this->testSpec->merge->array,
            fn($in) => Struct::merge($in),
            /* force deep‐equal */ true
        );
    }

    public function testMergeSpecial(): void
    {
        // Function‐value merging
        $f0 = function () {
            return null;
        };

        // single‐element list → that element
        $this->assertSame($f0, Struct::merge([$f0]));

        // null then f0 → f0 wins
        $this->assertSame($f0, Struct::merge([null, $f0]));

        // map with function property
        $obj1 = new stdClass();
        $obj1->a = $f0;
        $this->assertEquals(
            $obj1,
            Struct::merge([$obj1])
        );

        // nested map
        $obj2 = new stdClass();
        $obj2->a = new stdClass();
        $obj2->a->b = $f0;
        $this->assertEquals(
            $obj2,
            Struct::merge([$obj2])
        );

    }

    public function testGetpathBasic(): void
    {
        $this->testSet(
            $this->testSpec->getpath->basic,
            function (stdClass $in) {
                $path = property_exists($in, 'path') ? $in->path : null;
                $store = property_exists($in, 'store') ? $in->store : null;
                return Struct::getpath($path, $store);
            }
        );
    }


    public function testGetpathCurrent(): void
    {
        $this->testSet(
            $this->testSpec->getpath->current,
            function (stdClass $in) {
                return Struct::getpath($in->path, $in->store, $in->current);
            }
        );
    }

    public function testGetpathState(): void
    {
        // build your shared handler/state
        $state = (object) [
            'handler' => function ($st, $val, $cur, $ref, $store) {
                $out = $st->meta->step . ':' . $val;
                $st->meta->step++;
                return $out;
            },
            'meta' => (object) ['step' => 0],
            'mode' => 'val',
            'full' => false,
            'keyI' => 0,
            'keys' => ['$TOP'],
            'key' => '$TOP',
            'val' => '',
            'parent' => new \stdClass(),
            'path' => ['$TOP'],
            'nodes' => [new \stdClass()],
            'base' => '$TOP',
            'errs' => [],
        ];

        $this->testSet(
            $this->testSpec->getpath->state,
            function (stdClass $in) use ($state) {
                $path = property_exists($in, 'path') ? $in->path : null;
                $store = property_exists($in, 'store') ? $in->store : null;
                $current = property_exists($in, 'current') ? $in->current : null;
                return Struct::getpath($path, $store, $current, $state);
            }
        );
    }

    public function testInjectBasic(): void
    {
        // single‐case spec: injectSpec.basic
        $spec = $this->testSpec->inject->basic;
        // clone the input so we don’t modify the fixture
        $val = Struct::clone($spec->in->val);
        $store = $spec->in->store;

        $result = Struct::inject($val, $store);

        $this->assertEquals(
            $spec->out,
            $result,
            "inject-basic did not produce the expected result"
        );
    }

    public function testInjectString(): void
    {
        // a no-op modifier for string‐only tests
        $nullModifier = function ($v, $k, $p, $state, $current, $store) {
            // do nothing
            return $v;
        };

        $this->testSet(
            $this->testSpec->inject->string,
            function (stdClass $in) use ($nullModifier) {
                // some specs may include a 'current' key
                $current = property_exists($in, 'current') ? $in->current : null;
                return Struct::inject($in->val, $in->store, $nullModifier, $current);
            },
            /* force deep‐equal */ true
        );
    }

    public function testInjectDeep(): void
    {
        $this->testSet(
            $this->testSpec->inject->deep,
            function (stdClass $in) {
                // deep tests never need a modifier or current
                return Struct::inject($in->val, $in->store);
            },
            /* force deep‐equal */ true
        );
    }

    // ——— transform-basic ———
    public function testTransformBasic(): void
    {
        // single‐case test (no “set” array)
        $test = $this->testSpec->transform->basic;
        $in = $test->in;
        $out = Struct::transform($in->data, $in->spec);
        $this->assertEquals(
            $test->out,
            $out,
            'transform-basic failed'
        );
    }

    // ——— transform-paths ———
    public function testTransformPaths(): void
    {
        $this->testSet(
            $this->testSpec->transform->paths,
            fn(object $vin) => Struct::transform(
                $vin->data ?? (object) [],
                $vin->spec ?? (object) [],
                $vin->store ?? (object) []
            )
        );
    }

    // ——— transform-cmds ———
    public function testTransformCmds(): void
    {
        $this->testSet(
            $this->testSpec->transform->cmds,
            fn(object $vin) => Struct::transform(
                $vin->data ?? (object) [],
                $vin->spec ?? (object) [],
                $vin->store ?? (object) []
            )
        );
    }

    // ——— transform-each ———
    public function testTransformEach(): void
    {
        $this->testSet(
            $this->testSpec->transform->each,
            fn(object $vin) => Struct::transform(
                $vin->data ?? (object) [],
                $vin->spec ?? (object) [],
                $vin->store ?? (object) []
            )
        );
    }

    // ——— transform-pack ———
    // public function testTransformPack(): void
    // {
    //     $this->testSet(
    //         $this->testSpec->transform->pack,
    //         fn(object $vin) => Struct::transform(
    //             $vin->data ?? (object) [],
    //             $vin->spec ?? (object) [],
    //             $vin->store ?? (object) []
    //         )
    //     );
    // }

    // ——— transform-modify ———
    public function testTransformModify(): void
    {
        $this->testSet(
            $this->testSpec->transform->modify,
            function (object $vin) {
                return Struct::transform(
                    $vin->data,
                    $vin->spec,
                    $vin->store ?? (object) [],
                    // “modify” hook stays the same
                    function (&$val, $key, &$parent) {
                        if ($key !== null && $parent !== null && is_string($val)) {
                            $parent->{$key} = '@' . $val;
                            $val = '@' . $val;
                        }
                    }
                );
            }
        );
    }

    // ——— transform-extra ———
    public function testTransformExtra(): void
    {
        $extraTransforms = (object) [
            '$UPPER' => function ($state) {
                $last = end($state->path);
                return strtoupper((string) $last);
            }
        ];

        $res = Struct::transform(
            (object) ['a' => 1],
            (object) [
                'x' => '`a`',
                'b' => '`$COPY`',
                'c' => '`$UPPER`',
            ],
            (object) array_merge(
                ['b' => 2],
                (array) $extraTransforms
            )
        );

        $this->assertEquals(
            (object) [
                'x' => 1,
                'b' => 2,
                'c' => 'C',
            ],
            $res
        );
    }

    // ——— transform-funcval ———
    // public function testTransformFuncval(): void
    // {
    //     $f0 = fn() => 99;

    //     // literal value stays literal
    //     $this->assertEquals(
    //         (object) ['x' => 1],
    //         Struct::transform((object) [], (object) ['x' => 1])
    //     );

    //     // function as a spec value is preserved
    //     $out1 = Struct::transform((object) [], (object) ['x' => $f0]);
    //     $this->assertSame($f0, $out1->x);

    //     // backtick reference to a number field
    //     $this->assertEquals(
    //         (object) ['x' => 1],
    //         Struct::transform((object) ['a' => 1], (object) ['x' => '`a`'])
    //     );

    //     // backtick reference to a function field
    //     $res2 = Struct::transform(
    //         (object) ['f0' => $f0],
    //         (object) ['x' => '`f0`']
    //     );
    //     $this->assertSame($f0, $res2->x);
    // }


}
