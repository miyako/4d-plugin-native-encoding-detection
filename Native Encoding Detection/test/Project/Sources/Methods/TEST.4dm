//%attributes = {}
$params:=New object:C1471

CONVERT FROM TEXT:C1011("〠ゆうびん";"x-mac-japanese";$source)

$status:=NED Detect encoding ($source;$params)