USING: arrays generic assocs kernel math namespaces
sequences tools.test words definitions parser quotations
vocabs continuations tuples ;
IN: temporary

[ 4 ] [
    [
        "poo" "temporary" create [ 2 2 + ] define-compound
    ] with-compilation-unit
    "poo" "temporary" lookup execute
] unit-test

[ t ] [ t vocabs [ words [ word? and ] each ] each ] unit-test

DEFER: plist-test

[ t ] [
    \ plist-test t "sample-property" set-word-prop
    \ plist-test "sample-property" word-prop
] unit-test

[ f ] [
    \ plist-test f "sample-property" set-word-prop
    \ plist-test "sample-property" word-prop
] unit-test

[ f ] [ 5 compound? ] unit-test

"create-test" "scratchpad" create { 1 2 } "testing" set-word-prop
[ { 1 2 } ] [
    "create-test" "scratchpad" lookup "testing" word-prop
] unit-test

[
    [ t ] [ \ array? "array?" "arrays" lookup = ] unit-test

    [ ] [ "test-scope" "scratchpad" create drop ] unit-test
] with-scope

[ "test-scope" ] [
    "test-scope" "scratchpad" lookup word-name
] unit-test

[ t ] [ vocabs array? ] unit-test
[ t ] [ vocabs [ words [ word? ] all? ] all? ] unit-test

[ f ] [ gensym gensym = ] unit-test

[ f ] [ 123 compound? ] unit-test

: colon-def ;
[ t ] [ \ colon-def compound? ] unit-test

SYMBOL: a-symbol
[ t ] [ \ a-symbol compound? ] unit-test
[ t ] [ \ a-symbol symbol? ] unit-test

! See if redefining a generic as a colon def clears some
! word props.
GENERIC: testing
"IN: temporary : testing ;" eval

[ f ] [ \ testing generic? ] unit-test

[ f ] [ gensym interned? ] unit-test

: forgotten ;
: another-forgotten ;

[ f ] [ \ forgotten interned? ] unit-test

FORGET: forgotten

[ f ] [ \ another-forgotten interned? ] unit-test

FORGET: another-forgotten
: another-forgotten ;

[ t ] [ \ + interned? ] unit-test

! I forgot remove-crossref calls!
: fee ;
: foe fee ;
: fie foe ;

[ t ] [ \ fee usage [ word? ] subset empty? ] unit-test
[ t ] [ \ foe usage empty? ] unit-test
[ f ] [ \ foe crossref get key? ] unit-test

FORGET: foe

! xref should not retain references to gensyms
[ ] [
    [ gensym [ * ] define-compound ] with-compilation-unit
] unit-test

[ t ] [
    \ * usage [ word? ] subset [ interned? not ] subset empty?
] unit-test

DEFER: calls-a-gensym
[ ] [
    [
        \ calls-a-gensym
        gensym dup "x" set 1quotation
        define-compound
    ] with-compilation-unit
] unit-test

[ f ] [ "x" get crossref get at ] unit-test

! more xref buggery
[ f ] [
    GENERIC: xyzzle ( x -- x )
    : a ; \ a
    M: integer xyzzle a ;
    FORGET: a
    M: object xyzzle ;
    crossref get at
] unit-test

! regression
GENERIC: freakish ( x -- y )
: bar freakish ;
M: array freakish ;
[ t ] [ \ bar \ freakish usage member? ] unit-test

DEFER: x
[ t ] [ [ x ] catch undefined? ] unit-test

[ ] [ "no-loc" "temporary" create drop ] unit-test
[ f ] [ "no-loc" "temporary" lookup where ] unit-test

[ ] [ "IN: temporary : no-loc-2 ;" eval ] unit-test
[ f ] [ "no-loc-2" "temporary" lookup where ] unit-test

[ ] [ "IN: temporary : test-last ( -- ) ;" eval ] unit-test
[ "test-last" ] [ word word-name ] unit-test

! regression
SYMBOL: quot-uses-a
SYMBOL: quot-uses-b

[ ] [
    [
        quot-uses-a [ 2 3 + ] define-compound
    ] with-compilation-unit
] unit-test

[ { + } ] [ \ quot-uses-a uses ] unit-test

[ ] [
    [
        quot-uses-b 2 [ 3 + ] curry define-compound
    ] with-compilation-unit
] unit-test

[ { + } ] [ \ quot-uses-b uses ] unit-test

[ t ] [
    [ "IN: temporary : undef-test ; << undef-test >>" eval ] catch
    [ undefined? ] is?
] unit-test

[ ] [
    "IN: temporary GENERIC: symbol-generic" eval
] unit-test

[ ] [
    "IN: temporary SYMBOL: symbol-generic" eval
] unit-test

[ t ] [ "symbol-generic" "temporary" lookup symbol? ] unit-test
[ f ] [ "symbol-generic" "temporary" lookup generic? ] unit-test

[ ] [
    "IN: temporary GENERIC: symbol-generic" eval
] unit-test

[ ] [
    "IN: temporary TUPLE: symbol-generic ;" eval
] unit-test

[ t ] [ "symbol-generic" "temporary" lookup symbol? ] unit-test
[ f ] [ "symbol-generic" "temporary" lookup generic? ] unit-test
