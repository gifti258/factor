! Copyright (C) 2022 Giftpflanze.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors array-programming.syntax arrays assocs
combinators.extras generalizations kernel math
math.combinatorics math.constants math.functions math.libm
math.matrices math.order math.parser math.primes math.statistics
multiline present prettyprint.custom random sequences
sequences.extras sequences.repeating sets shuffle splitting
strings unicode ;
IN: array-programming

INSTANCE: array* sequence

M: array* length shape>> first ;

M: array* nth
    bounds-check [ dup 1 + ] [
        [ underlying>> ] [ shape>> ] bi
        rest [ product '[ [ _ * ] bi@ ] dip subseq ] keep
        dup empty? [ drop first ] [ <array*> ] if
    ] bi* ;

M: array* set-nth immutable ;

M: array* pprint-delims drop \ ARRAY{ \ } ;

M: array* >pprint-sequence underlying>> ;

M: array* pprint* pprint-object ;

! SYMBOLS: c m p s v ;

PREDICATE: c < array* dress-code>> c = ;
PREDICATE: m < array* dress-code>> m = ;
PREDICATE: p < array* dress-code>> p = ;
PREDICATE: s < array* dress-code>> s = ;
PREDICATE: v < array* dress-code>> v = ;

/*
TUPLE: c < array* ;
TUPLE: m < array* ;
TUPLE: p < array* ;
TUPLE: s < array* ;
TUPLE: v < array* ;
*/

UNION: any scalar array* ;

: >n ( ? -- n ) 1 0 ? ;

ARRAY*: append ( vector vector -- array )
    [ ensure-array [ underlying>> ] [ shape>> unclip ] bi ] bi@
    ! shuffle( u1 r1 f1 u2 r2 f2 -- u1 f1 u2 f2 r1 r2 )
    swap 5roll [ max ] 2map
    ! shuffle( u1 f1  u2 f2  r -- u1 r f1  u2 r f2  r f1 f2 )
    [ [ swap ] curry 2bi@ ] keep 5 npick pick
    [ [ prefix product <cycles> ] 3bi@ append ]
    [ + suffix ] 3bi* <array*> ;

ARRAY*: collapse ( array -- array )
    [ product 1array ] change-shape ;

! ARRAY*: compress ( n -- array ) narray >array* ; inline

! implement empty array identity lookup
ARRAY*: dreduce ( array defspec -- scalar )
    [ underlying>> [ ] ] dip map-reduce ; inline

ARRAY*: dress ( array symbol -- array ) >>dress-code ;

ARRAY*: dressed ( array -- array symbol )
    dup dup array*? [ dress-code>> ] [ drop f ] if ;

ARRAY*: extract ( array n -- array elt )
    swap [ remove-nth >array* ] [ nth ] 2bi ;

ARRAY*: grade ( vector -- vector vector ) dup arg-sort >array* ;

ARRAY*: in ( set vector -- x )
    [ underlying>> >array ] bi@
    swap [ member? >n ] curry map >array* ;

ARRAY*: index ( vector vector -- vector )
    [ underlying>> >array ] bi@
    swap [ index ARRAY{ } v array-dress or ] curry map >array* ;

ARRAY*: iota ( n -- vector ) <iota> >array* ;

ARRAY*: join ( vector str -- str )
    [ [ present ] map ] dip join ;

ARRAY*: length ( array -- array n ) dup length ;

ARRAY*: outer ( v1 v2 quot -- array )
    [ cartesian-map concat ] 2keepd [ length ] bi@ * <array*>
    ; inline

ARRAY*: remove ( array vector/scalar -- array ) drop ;

ARRAY*: reshape ( array vector -- array )
    [ nip underlying>> ] curry change-shape ;

ARRAY*: reverse ( array -- array ) reverse ;

ARRAY*: rotate ( array vector -- array ) drop ;

ARRAY*: scatter ( vector vector -- array ) drop ;

ARRAY*: select ( array vector -- array ) drop ;

ARRAY*: shape ( array -- array vector ) dup shape>> >array* ;

ARRAY*: slice ( array array -- array ) drop ;

ARRAY*: split ( str str -- vector ) split ;

ARRAY*: spread ( array quot -- array ) drop ;

ARRAY*: strip ( array -- array ) [ drop f ] change-dress-code ;

ARRAY*: subscript ( array array -- array ) swap nths ;

ARRAY*: transpose ( array n -- array ) drop ;

BINARIES: 0 + - ;
BINARIES: 1 * / ;

BINARY: 1 % mod ;
BINARY*: 1 ** ^ ;

BINARY: -1 & bitand ;
BINARY: 0 | bitor ;
BINARY: 0 ^ bitxor ;

! number= ?
! f == 0
BINARY: f == = >n ;
BINARY: f != = not >n ;
BINARY: f > > >n ;
BINARY: f < < >n ;
BINARY: f >= >= >n ;
BINARY: f <= <= >n ;

! f =/= 0
BINARY: f === = >n ;

BINARY: f eq = >n ;
BINARY: f ne = not >n ;
BINARY: f gt after? >n ;
BINARY: f lt before? >n ;
BINARY: f ge after=? >n ;
BINARY: f le before=? >n ;

! f =/= ""
BINARY: f eql = ;

BINARY*: f <=> <=> { { +lt+ -1 } { +eq+ 0 } { +gt+ 1 } } at ;
BINARY: f cmp <=> ;

BINARY: 0 || [ 0 = not ] bi@ or >n ;
BINARY: 1 && [ 0 = not ] bi@ and >n ;

! UNARY: ! factorial ;

UNARY: ? random-unit * ;

BINARY: f atan2 fatan2 ;

! UNARY: abs abs ;

UNARIES: abs cos neg sin sqrt tan ;

BINARIES: f intersect max min union ;

UNARY: amean mean ;

BINARY: 1 and && ;

BINARY: 1 choose nCk ;

UNARY: cmean ;

UNARY: complex first2 polar> ;

BINARY: f corr zip pearson-r ;

! UNARY: cos cos ;

UNARY: defined >n ;

UNARY: distinct members ;

ARRAY*: e ( -- e ) e ;

ARRAY: eps ( -- ε ) epsilon ;

UNARY: exp e^ ;

BINARY*: 0 gcd gcd nip ;

UNARY: gmean geometric-mean ;

UNARY: h2d hex> ;

UNARY: hmean harmonic-mean ;

UNARY: hoelder ;

UNARY: idmatrix <identity-matrix> ;

UNARY: im imaginary-part ;

UNARY: int >integer ;

! BINARY*: f intersect intersect ;

UNARY: ln log ;

! BINARY*: f max max ;

UNARY: median median ;

! BINARY*: f min min ;

! UNARY: neg neg ;

UNARY: not 0 = >n ;

BINARY: 0 or || ;

ARRAY: pi ( -- pi ) pi ;

UNARY: polar >polar 2array f p array* boa ;

UNARY: prime prime? >n ;

UNARY: qmean ;

UNARY: re real-part ;

! UNARY: sin sin ;

! UNARY: sqrt sqrt ;

BINARY: f subset swap subset? >n ;

! UNARY: tan tan ;

! BINARY*: f union union ;

UNARY: chr 1string ;

BINARY: "" concat append ;

! UNARY: execute call ; inline

ARRAY: gplot ( vector -- ) drop ;

ARRAY: help ( defspec -- ) drop ;

UNARY: lc >lower ;

ARRAY: type ( array -- array symbol ) dup ;
! N U B -- niladic unary binary
! F -- built-in function
! V -- variable (symbol)
! W -- user-defined word
! S A D -- scalar array dressed data structure

UNARY: uc >upper ;

! Complex numbers
! abs = abs
! neg = conjugate
! + = array-+ +
! - = array-- -
! * = *
! / = /
! re = real-part
! im = imaginary-part
! polar(c) = >polar
! complex(p) = polar>
! == = =
! != = = not

! Polar tuples
! ==
! !=

! Linear Algebra
! *(m,v) m*v
! *(m,m) m*

! Sets
! distinct(s)
! intersect(s,s)
! subset(s,s)
! union(s,s)


