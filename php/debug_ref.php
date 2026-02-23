<?php
define('STRUCT_DEBUG_REF', true);
require_once __DIR__ . '/src/Struct.php';
use Voxgig\Struct\Struct;
$data = (object)[];
$ref = '`' . '$REF' . '`';
$spec = (object)['x0' => 0, 'r0' => [$ref, 'x0']];
$out = Struct::transform($data, $spec);
echo 'Result: ' . json_encode($out) . "\n";
