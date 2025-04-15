<?php

namespace Voxgig\Struct;

class SDK {
    private array $opts;
    private object $utility;

    public function __construct(array $opts = []) {
        $this->opts = $opts ?: [];
        // Capture opts for use in the closure.
        $optsCopy = $this->opts;
        $this->utility = (object)[
            // An anonymous adapter that forwards method calls to the Struct class.
            'struct' => new class {
                public function __call(string $name, array $args) {
                    // Map method name (if needed) here; otherwise, call directly.
                    return call_user_func_array(['Voxgig\Struct\Struct', $name], $args);
                }
            },
            // A simple check function similar to the TS version.
            'check' => function($ctx) use ($optsCopy) {
                $foo = isset($optsCopy['foo']) ? $optsCopy['foo'] : '';
                $bar = isset($ctx->bar) ? $ctx->bar : '0';
                return (object)[
                    'zed' => 'ZED' . $foo . '_' . $bar
                ];
            }
        ];
    }

    // Static method to obtain a test SDK instance.
    public static function test(array $opts = []): SDK {
        return new SDK($opts);
    }

    // Instance method (if needed) that mimics the async test() from TS.
    public function testMethod(array $opts = []): SDK {
        return new SDK($opts);
    }

    public function utility(): object {
        return $this->utility;
    }
}
