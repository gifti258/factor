! Copyright (C) 2020 Doug Coleman.
! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors assocs classes.error classes.parser effects
effects.parser endian kernel lexer make math math.bitwise
math.parser parser sequences splitting vocabs.parser words
words.symbol ;
IN: cpu.arm.64.assembler.syntax

! Instruction fields

<PRIVATE

: error-word ( word -- new-class )
    name>> "-range" append create-class-in dup save-location
    tuple
    { "value" }
    [ define-error-class ] keepdd ;

: make-checker-word ( word n -- )
    [ drop dup error-word ]
    [ nip swap '[ dup _ on-bits > [ _ execute( value -- * ) ] when ] ]
    [ 2drop ( n -- n ) ] 2tri
    define-declared ;

PRIVATE>

SYNTAX: FIELD:
    scan-new-word scan-object
    [ "width" set-word-prop ] 2keep
    make-checker-word ;

<PRIVATE

: make-register-checker-word ( word n -- )
    [ drop dup error-word '[ _ execute( value -- * ) ] ]
    [ nip swap '[ "ordinal" word-prop dup _ on-bits > _ when ] ]
    [ 2drop ( n -- n ) ] 2tri
    define-declared ;

PRIVATE>

SYNTAX: REGISTER-FIELD:
    scan-new-word scan-object
    [ "width" set-word-prop ] 2keep
    make-register-checker-word ;

! Instructions

<PRIVATE

ERROR: no-field-word vocab name ;

TUPLE: integer-literal value width ;
C: <integer-literal> integer-literal

! handle 1xx0 where x = dontcare
: make-integer-literal ( string -- integer-literal )
    [ "0b" prepend { { CHAR: x CHAR: 0 } } substitute string>number ]
    [ length ] bi <integer-literal> ;

: ?lookup-word ( name vocab -- word )
    2dup lookup-word
    [ 2nip ]
    [ over [ "01x" member? ] all? [ drop make-integer-literal ] [ no-field-word ] if ] if* ;

GENERIC: width ( obj -- n )
M: word width "width" word-prop ;
M: integer-literal width width>> ;

GENERIC: value ( obj -- n )
M: integer-literal value value>> ;
M: object value ;

: arm-bitfield ( seq -- assoc )
    [ current-vocab name>> ".private" append ?lookup-word ] map
    [ dup width ] map>alist dup values [ f = ] any? [ throw ] when ;

ERROR: bad-instruction values ;

PRIVATE>

SYNTAX: ARM-INSTRUCTION:
    scan-new-word scan-effect [
      in>> arm-bitfield [ keys [ value ] map ] [ values 32 [ - ] accumulate* ] bi zip
      dup last second 0 = [ bad-instruction ] unless '[ _ bitfield* 4 >le % ]
    ] [ in>> [ string>number ] reject { } <effect> ] bi define-declared ;

! Registers

<PRIVATE

: create-register ( str width ordinal -- )
    [ create-word-in [ define-symbol ] keep ] 2dip
    "width" "ordinal" [ set-word-prop ] bi-curry@ bi-curry* bi ;

: (create-registers) ( ch exponent ordinal -- )
    [ -rot [ >dec ] [ prefix ] [ 2^ ] tri* ] keep create-register ; inline

: create-registers ( prefixes offset n -- )
    '[ _ + _ <iota> [ (create-registers) ] 2with each ] each-index ;

PRIVATE>

SYNTAX: REGISTER-BANKS: scan-token scan-datum scan-datum create-registers ;

SYNTAX: REGISTER: scan-token scan-datum scan-datum create-register ;
