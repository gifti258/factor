USING: array-programming array-programming.syntax kernel
literals tools.test ;

${ { 1 2 3 4 } { 2 2 } f array* boa }
ARRAY[ { { 1 2 } { 3 4 } } ] unit-test
{ ARRAY{ 1 2 3 4 } } ARRAY[ { 1 2 3 4 } ] unit-test
{ ARRAY{ 1 2 3 4 } } ARRAY[ { 1 2 } { 3 4 } append ] unit-test
{ ARRAY{ 1 2 3 } } ARRAY[ { 1 2 } 3 append ] unit-test
