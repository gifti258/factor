! Copyright (C) 2022 Giftpflanze.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors arrays assocs combinators effects.parser kernel
lexer math math.order parser quotations sequences
sequences.repeating strings vectors vocabs.parser words ;
IN: array-programming.syntax

TUPLE: array* underlying shape dress-code ;

PREDICATE: dressed-array* < array* dress-code>> ;

UNION: scalar POSTPONE: f number string dressed-array* ;

: <array*> ( seq shape -- array* ) f array* boa ;

ERROR: misshaped-array ;

! n-dimensional matrix with boxes (dressed arrays)
! also possible: nested array (shape = common prefix)
: >array* ( seq -- array )
    >array {
        { [ dup [ scalar? ] all? ] [ dup length 1array ] } {
            [
                dup dup [ array*? ] all?
                [ [ shape>> ] [ = ] map-reduce ] [ drop f ] if
            ] [ [
                [ [ underlying>> ] map concat ]
                [ first shape>> ] bi
            ] keep length prefix ]
        } [ misshaped-array ]
    } cond <array*> ;

DEFER: with-array
! Reimplement some stuff, Factor forgets changed manifest after
! first substructure
: parse-until-step* ( accum end -- accum ? )
    [ ?scan-datum ] with-array {
        { [ 2dup eq? ] [ 2drop f ] }
        { [ dup not ] [ drop throw-unexpected-eof t ] }
        { [ dup delimiter? ] [ unexpected t ] }
        { [ dup parsing-word? ] [ nip execute-parsing t ] }
        [ pick push drop t ]
    } cond ;
: (parse-until*) ( accum end -- accum )
    [ parse-until-step* ] keep swap [ (parse-until*) ] [ drop ]
    if ;
: parse-until* ( end -- vec ) 100 <vector> swap (parse-until*) ;
: parse-literal* ( accum end quot -- accum )
    [ parse-until* ] dip call suffix! ; inline
: parse-quotation* ( -- quot ) \ ] parse-until* >quotation ;

SYNTAX: ARRAY{ \ } [ >array* ] parse-literal* ;

: array-words ( -- assoc )
    H{
        { "{" POSTPONE: ARRAY{ }
        { "array" \ array* }
    } ;

: with-array ( quot -- ) array-words swap with-words ; inline

SYNTAX: [ARRAY \ ] parse-until* append! ;

SYNTAX: ARRAY[ parse-quotation* suffix! ;

: create-array-word ( str -- word )
    [ "array-" prepend create-word-in dup reset-generic ] keep
    [ array-words set-at ] keepd ;

: scan-array-word ( -- word ) scan-word-name create-array-word ;

: create-alias ( str -- word def )
    [ create-array-word ] keep parse-datum 1quotation ;

: ensure-array ( obj -- array )
    dup scalar? [ 1array >array* ] when ;

: define-unary ( word def -- )
    '[ ensure-array [ _ map ] change-underlying ]
    ( x -- x ) define-declared ;

: define-binary ( identity word def -- )
    '[
        [
            ensure-array [ underlying>> ] [ shape>> ] bi
        ] bi@ swapd
        2dup max-length [ 0 pad-head ] curry bi@ [ max ] 2map
        [ product tuck [ <cycles> ] 2bi@ _ 2map ] keep <array*>
    ] [ ( x x -- x ) define-declared ] keepd
    swap "identity" set-word-prop ;

SYNTAX: UNARY:
    [ scan-array-word parse-definition ] with-definition
    define-unary ;

SYNTAX: UNARIES:
    ";" [ create-alias define-unary ] each-token ;

SYNTAX: BINARY:
    [
        scan-object scan-array-word
        [ parse-definition ] with-array
    ] with-definition
    define-binary ;

SYNTAX: BINARY*:
    [
        scan-object scan-array-word
        parse-definition
    ] with-definition
    define-binary ;

SYNTAX: BINARIES:
    scan-object ";" [
        create-alias define-binary
    ] with each-token ;

! SIMPLE:?
SYNTAX: ARRAY:
    [
        scan-array-word scan-effect
        [ parse-definition ] with-array swap
    ] with-definition define-declared ;

SYNTAX: ARRAY*:
    [
        scan-array-word scan-effect
        parse-definition swap
    ] with-definition define-declared ;

! USE: multimethods
! RENAME: GENERIC: multi-methods => MULTI:

! UNARY: name def ;
! UNARY: name types def ;
SYNTAX: M:UNARY:
    ! scan-new-word scan-effect define-generic
    ! (METHOD:) define
    ! scan-new-method parse-definition
    ! scan-word scan-object swap create-method-in
    ;

! #2257 syntax prop.
! #2364 disc
! #2430 
! #2431 pr
