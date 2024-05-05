! Copyright (C) 2020 Doug Coleman.
! Copyright (C) 2023, 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors arrays assocs combinators continuations
cpu.arm.64.assembler.opcodes cpu.arm.64.assembler.syntax
generalizations grouping kernel literals make math math.bitwise
math.order math.parser sequences sequences.generalizations
shuffle vocabs.parser words ;
IN: cpu.arm.64.assembler

! Registers

REGISTER-BANKS: WX 5 31
REGISTER-BANKS: BHSDQ 3 32

REGISTER: XZR 64 31
REGISTER: WZR 32 31
REGISTER:  SP 64 31
REGISTER: WSP 32 31

ALIAS: LR X30
ALIAS: FP X29

<PRIVATE

PREDICATE: register < word "ordinal" word-prop ;

: SP? ( register -- ? ) name>> 2 tail* "SP" = ;
: ZR? ( register -- ? ) name>> 2 tail* "ZR" = ;

ERROR: incompatible-register register ;
: ?SP ( register -- register ) dup ZR? [ incompatible-register ] when ;
: !SP ( register -- register ) dup SP? [ incompatible-register ] when ;

: ?SP/?SP ( Rn Rd -- Rn Rd ) [ ?SP ] bi@ ;

: ?SP/!SP ( Rn Rd -- Rn Rd ) [ ?SP ] [ !SP ] bi* ;

: !SP/!SP ( Rn Rd -- Rn Rd ) [ !SP ] bi@ ;

: 32-bit? ( register -- ? ) "width" word-prop 32 = ;
: 64-bit? ( register -- ? ) "width" word-prop 64 = ;

: ?32-bit ( register -- register ) dup 32-bit? [ incompatible-register ] unless ;
: ?64-bit ( register -- register ) dup 64-bit? [ incompatible-register ] unless ;

: >ZR ( Rn -- ZR ) 64-bit? XZR WZR ? ;

PRIVATE>

: >32-bit ( Xn -- Wn ) name>> 1 tail CHAR: W prefix $[ current-vocab name>> ] lookup-word ;

<PRIVATE

ERROR: register-mismatch registers ;
<<
: check-registers ( n quot -- quot )
    over '[
        [ _ narray _ map dup all-equal? [ register-mismatch ] unless first ] _ nkeep
    ] ; inline
>>

GENERIC: >bw ( obj -- bw )
M: word >bw ( register -- bw ) 64-bit? 1 0 ? ;

GENERIC: >!bw ( obj -- !bw )
M: word >!bw ( register -- bw ) 32-bit? 1 0 ? ;

MACRO: (bw) ( n -- quot ) [ >bw ] check-registers ;

:  bw ( Rt -- bw Rt ) [ >bw ] keep ;
: 2bw ( Rd Rn -- bw Rd Rn ) 2 (bw) ;
: 3bw ( Rd Rn Rm -- bw Rd Rn Rm ) 3 (bw) ;
: 4bw ( Rd Rn Rm Ra -- bw Rd Rn Rm Ra ) 4 (bw) ;
: !bw ( Rt -- !bw Rt ) [ >!bw ] keep ;

:  bwd ( Rt obj --  bw Rt obj ) [ bw ] dip ;
: !bwd ( Rt obj -- !bw Rt obj ) [ !bw ] dip ;

: >var ( register -- variant ) name>> first { { CHAR: S 0 } { CHAR: D 1 } { CHAR: H 3 } } at ;

MACRO: (var) ( n -- quot ) [ >var ] check-registers ;

:  var ( R -- var R ) 1 (var) ;
: 2var ( Rn Rd -- var Rn Rd ) 2 (var) ;
: 3var ( Rm Rn Rd -- var Rm Rn Rd ) 3 (var) ;

: >fp ( register -- ldrlfp-opc ) name>> first "SDQ" index ;

: fp ( register -- opc register ) [ >fp ] keep ;

PRIVATE>

! Special-purpose registers

: FPCR ( -- op0 op1 CRn CRm op2 ) 3 3 4 4 0 ;
: FPSR ( -- op0 op1 CRn CRm op2 ) 3 3 4 4 1 ;
: NZCV ( -- op0 op1 CRn CRm op2 ) 3 3 4 2 0 ;

! Condition codes

CONSTANT: EQ 0b0000 ! Z set: equal
CONSTANT: NE 0b0001 ! Z clear: not equal
CONSTANT: CS 0b0010 ! C set: unsigned higher or same
CONSTANT: HS 0b0010 !
CONSTANT: CC 0b0011 ! C clear: unsigned lower
CONSTANT: LO 0b0011 !
CONSTANT: MI 0b0100 ! N set: negative
CONSTANT: PL 0b0101 ! N clear: positive or zero
CONSTANT: VS 0b0110 ! V set: overflow
CONSTANT: VC 0b0111 ! V clear: no overflow
CONSTANT: HI 0b1000 ! C set and Z clear: unsigned higher
CONSTANT: LS 0b1001 ! C clear or Z set: unsigned lower or same
CONSTANT: GE 0b1010 ! N equals V: greater or equal
CONSTANT: LT 0b1011 ! N not equal to V: less than
CONSTANT: GT 0b1100 ! Z clear AND (N equals V): greater than
CONSTANT: LE 0b1101 ! Z set OR (N not equal to V): less than or equal
CONSTANT: AL 0b1110 ! always
CONSTANT: NV 0b1111 ! always

! SIMD arrangement specifiers

:  8B ( -- Q size ) 0 0 ;
: 16B ( -- Q size ) 1 0 ;
:  4H ( -- Q size ) 0 1 ;
:  8H ( -- Q size ) 1 1 ;
:  2S ( -- Q size ) 0 2 ;
:  4S ( -- Q size ) 1 2 ;
:  2D ( -- Q size ) 1 3 ;

! Immediates

<PRIVATE

ERROR: immediate-width n bits ;
: ?uimm ( n bits -- n ) 2dup bits pick = [ drop ] [ immediate-width ] if ;

: ?simm ( n bits -- n ) 2dup >signed pick = [ bits ] [ immediate-width ] if ;

ERROR: scaling n shift ;
: ?>> ( n shift -- n' ) 2dup bits [ neg shift ] [ scaling ] if-zero ;

: uimm? ( n bits -- n' ? ) [ bits ] keepd [ = ] 2keep [ ? ] keepdd ;

: simm? ( n shift -- n' ? )
    [ [ >signed ] keepd [ = ] 2keep ] keep [ [ ? ] keepdd ] dip swap [ bits ] dip ;

: >>uimm? ( n shift bits -- n' ? )
    [ [ [ bits zero? ] [ neg shift ] 2bi ] dip [ [ bits ] keepd = and ] keepd ] keepdd
    [ ? ] keepdd ;

! Arithmetic immediates

: imm-lower? ( imm n -- ? ) neg shift zero? ; inline

: imm-upper? ( imm n -- ? ) [ bits ] [ -2 * shift ] 2bi [ zero? ] both? ; inline

ERROR: immediate-range n bits ;
: split-imm ( imm -- shift imm' )
    12 {
        { [ 2dup imm-lower? ] [ drop 0 ] }
        { [ 2dup imm-upper? ] [ drop -12 shift 1 ] }
        [ immediate-range ]
    } cond swap ;

PRIVATE>

: arithmetic-immediate? ( imm -- ? ) 12 [ imm-lower? ] [ imm-upper? ] 2bi or ;

! Logical immediates

<PRIVATE

ERROR: bitmask-immediate n ;
: ?bitmask ( imm imm-size -- imm )
    dupd on-bits 0 [ = ] bi-curry@ bi or [ dup bitmask-immediate ] when ; inline

: element-size ( imm imm-size -- imm element-size )
    [ 2dup 2/ [ neg shift ] 2keep '[ _ on-bits bitand ] same? ] [ 2/ ] while ; inline

: bit-transitions ( imm element-size -- seq )
    [ >bin ] dip CHAR: 0 pad-head 2 circular-clump ; inline

ERROR: bitmask-element n ;
: ?element ( imm element-size -- element )
    [ bits ] keep dupd bit-transitions [ first2 = not ] count
    2 = [ dup bitmask-element ] unless ; inline

: >Nimms ( element element-size -- N imms )
    [ bit-count 1 - ] [ log2 1 + ] bi*
    7 [ on-bits ] bi@ bitxor bitor
    6 toggle-bit [ -6 shift ] [ 6 bits ] bi ; inline

: >immr ( element element-size -- immr )
    [ bit-transitions "10" swap index 1 + ] keep mod ; inline

: (encode-bitmask) ( imm imm-size -- (N)immrimms )
    [ bits ] [ ?bitmask ] [ element-size ] tri
    [ ?element ] keep [ >Nimms ] [ >immr ] 2bi
    { 12 0 6 } bitfield* ; inline

: encode-bitmask ( imm bw -- (N)immrimms ) zero? 32 64 ? (encode-bitmask) ;

PRIVATE>

: logical-immediate? ( imm64 -- ? )
    [ 64 [ ?bitmask ] [ element-size ] bi ?element drop t ] [ 2drop f ] recover ;

! Extended and shifted registers

<PRIVATE

TUPLE: operand register amount type ;
M: operand >bw register>> >bw ;
M: operand >!bw register>> >!bw ;

: ?Wm ( Wm shift -- Wm shift ) [ ?32-bit !SP ] dip ;
: ?Xm ( Xm shift -- Xm shift ) [ ?64-bit !SP ] dip ;

TUPLE: extended-register < operand ;
C: <extended-register> extended-register

TUPLE: shifted-register < operand ;
: <shifted-register> ( Rm amount type -- sr )
    [ over >bw 5 + ?uimm ] dip shifted-register boa ;

GENERIC: encode ( er/sr -- Rm/type Rm/type imm )
M: extended-register encode [ register>> ] [ type>> ] [ amount>> ] tri ;
M: shifted-register encode [ type>> ] [ register>> ] [ amount>> ] tri ;

PRIVATE>

: <UXTB> ( Rm uimm3 -- er ) ?Wm 0 <extended-register> ;
: <UXTH> ( Rm uimm3 -- er ) ?Wm 1 <extended-register> ;
: <UXTW> ( Rm uimm3 -- er ) ?Wm 2 <extended-register> ;
: <UXTX> ( Rm uimm3 -- er ) ?Xm 3 <extended-register> ;
: <SXTB> ( Rm uimm3 -- er ) ?Wm 4 <extended-register> ;
: <SXTH> ( Rm uimm3 -- er ) ?Wm 5 <extended-register> ;
: <SXTW> ( Rm uimm3 -- er ) ?Wm 6 <extended-register> ;
: <SXTX> ( Rm uimm3 -- er ) ?Xm 7 <extended-register> ;
: <LSL*> ( Rm uimm3 -- er ) over >bw 2 + <extended-register> ;

: <LSL> ( Rm uimm5/6 -- sr ) 0 <shifted-register> ;
: <LSR> ( Rm uimm5/6 -- sr ) 1 <shifted-register> ;
: <ASR> ( Rm uimm5/6 -- sr ) 2 <shifted-register> ;
: <ROR> ( Rm uimm5/6 -- sr ) 3 <shifted-register> ;

! Adressing modes

<PRIVATE

TUPLE: address register offset ;
: register/offset ( address -- register offset ) [ register>> ] [ offset>> ] bi ;

TUPLE: pre-index < address ;
TUPLE: post-index < address ;
TUPLE: immediate-offset < address ;
TUPLE: register-offset < address ;

: ?Xn/SP ( Xn offset -- Xn offset ) [ ?64-bit ?SP ] dip ;

PRIVATE>

: [pre] ( Xn simm -- address ) ?Xn/SP pre-index boa ;
: [post] ( Xn simm -- address ) ?Xn/SP post-index boa ;

GENERIC: [+] ( Xn operand -- address )
M: extended-register [+] ?Xn/SP register-offset boa ;
M: register [+] 0 <LSL*> [+] ;
M: integer [+] ?Xn/SP immediate-offset boa ;

: [] ( Xn -- address ) 0 [+] ;

! Load and store instructions

<PRIVATE

: LDRpre ( Rt address -- imm9 Rn Rt ) register/offset 9 ?simm spin !SP ;

: ?Wt ( Wt offset -- Wt offset ) [ ?32-bit ] dip ;
: ?Xt ( Xt offset -- Wt offset ) [ ?64-bit ] dip ;

ERROR: offset n ;
: LDRoff ( Rt address bits uoff ldur -- imm Rn Rt )
    {
        [ !SP ]
        [ register/offset ]
        [ 12 >>uimm? ]
        [ '[ spin @ ] ]
        [ '[ 9 simm? [ spin @ ] [ offset ] if ] if ]
    } spread ; inline

ERROR: extend-type n ;
: ?extend-type ( type -- type ) dup 1 bit? [ extend-type ] unless ;

ERROR: extend-amount n m ;
: ?extend-amount ( amount n -- S )
    {
        { [ over zero? ] [ 2drop 0 ] }
        { [ 2dup = ] [ 2drop 1 ] }
        [ extend-amount ]
    } cond ;

: LDRr ( Rt address bits -- Rm option S Rn Rt )
    [ register/offset spin !SP ] dip '[ encode [ ?extend-type ] dip _ ?extend-amount ] 2dip ;

PRIVATE>

GENERIC: LDR ( Rt address/literal -- )
M: pre-index LDR bwd LDRpre LDRpre-encode ;
M: post-index LDR bwd LDRpre LDRpost-encode ;
M: immediate-offset LDR bwd pick 2 + [ LDRuoff-encode ] [ LDUR-encode ] LDRoff ;
M: register-offset LDR bwd pick 2 + LDRr LDRr-encode ;
M: integer LDR bwd 19 ?simm swap LDRl-encode ;

GENERIC: LDRB ( Wt address -- )
M: pre-index LDRB ?Wt LDRpre LDRBpre-encode ;
M: post-index LDRB ?Wt LDRpre LDRBpost-encode ;
M: immediate-offset LDRB ?Wt 0 [ LDRBuoff-encode ] [ LDURB-encode ] LDRoff ;
M: register-offset LDRB ?Wt 0 LDRr LDRBr-encode ;

GENERIC: LDRH ( Wt address -- )
M: pre-index LDRH ?Wt LDRpre LDRHpre-encode ;
M: post-index LDRH ?Wt LDRpre LDRHpost-encode ;
M: immediate-offset LDRH ?Wt 1 [ LDRHuoff-encode ] [ LDURH-encode ] LDRoff ;
M: register-offset LDRH ?Wt 1 LDRr LDRHr-encode ;

GENERIC: LDRSB ( Rt address -- )
M: pre-index LDRSB !bwd LDRpre LDRSBpre-encode ;
M: post-index LDRSB !bwd LDRpre LDRSBpost-encode ;
M: immediate-offset LDRSB !bwd 0 [ LDRSBuoff-encode ] [ LDURSB-encode ] LDRoff ;
M: register-offset LDRSB !bwd 0 LDRr LDRSBr-encode ;

GENERIC: LDRSH ( Rt address -- )
M: pre-index LDRSH !bwd LDRpre LDRSHpre-encode ;
M: post-index LDRSH !bwd LDRpre LDRSHpost-encode ;
M: immediate-offset LDRSH !bwd 1 [ LDRSHuoff-encode ] [ LDURSH-encode ] LDRoff ;
M: register-offset LDRSH !bwd 1 LDRr LDRSHr-encode ;

GENERIC: LDRSW ( Xt address/literal -- )
M: pre-index LDRSW ?Xt LDRpre LDRSWpre-encode ;
M: post-index LDRSW ?Xt LDRpre LDRSWpost-encode ;
M: immediate-offset LDRSW ?Xt 2 [ LDRSWuoff-encode ] [ LDURSW-encode ] LDRoff ;
M: register-offset LDRSW ?Xt 2 LDRr LDRSWr-encode ;
M: integer LDRSW ?Xt 19 ?simm swap LDRSWl-encode ;

GENERIC: STR ( Rt address/literal -- )
M: pre-index STR bwd LDRpre STRpre-encode ;
M: post-index STR bwd LDRpre STRpost-encode ;
M: immediate-offset STR bwd pick 2 + [ STRuoff-encode ] [ STUR-encode ] LDRoff ;
M: register-offset STR bwd pick 2 + LDRr STRr-encode ;

GENERIC: STRB ( Wt address -- )
M: pre-index STRB ?Wt LDRpre STRBpre-encode ;
M: post-index STRB ?Wt LDRpre STRBpost-encode ;
M: immediate-offset STRB ?Wt 0 [ STRBuoff-encode ] [ STURB-encode ] LDRoff ;
M: register-offset STRB ?Wt 0 LDRr STRBr-encode ;

GENERIC: STRH ( Wt address -- )
M: pre-index STRH ?Wt LDRpre STRHpre-encode ;
M: post-index STRH ?Wt LDRpre STRHpost-encode ;
M: immediate-offset STRH ?Wt 1 [ STRHuoff-encode ] [ STURH-encode ] LDRoff ;
M: register-offset STRH ?Wt 1 LDRr STRHr-encode ;

<PRIVATE

: (LDP) ( Rt Rt2 address -- bw imm7 Rt2 Rn Rt )
    [ 2bw !SP ] dip register/offset 5 npick 2 + ?>> 7 ?simm -rot roll ;

PRIVATE>

GENERIC: LDP ( Rt Rt2 address -- )
M: pre-index LDP (LDP) LDPpre-encode ;
M: post-index LDP (LDP) LDPpost-encode ;
M: immediate-offset LDP (LDP) LDPsoff-encode ;

<PRIVATE

: (LDPSW) ( Rt Rt2 address -- imm7 Rt2 Rn Rt )
    [ [ ?64-bit !SP ] bi@ ] dip register/offset 2 ?>> 7 ?simm -rot roll ;

PRIVATE>

GENERIC: LDPSW ( Rt Rt2 address -- )
M: pre-index LDPSW (LDPSW) LDPSWpre-encode ;
M: post-index LDPSW (LDPSW) LDPSWpost-encode ;
M: immediate-offset LDPSW (LDPSW) LDPSWsoff-encode ;

GENERIC: STP ( Rt Rt2 adress -- )
M: pre-index STP (LDP) STPpre-encode ;
M: post-index STP (LDP) STPpost-encode ;
M: immediate-offset STP (LDP) STPsoff-encode ;

! Branch instructions

! B but that is breakpoint
: Br ( simm26 -- ) 26 ?simm B-encode ;

<PRIVATE

: B.cond ( simm19 cond -- ) [ 19 ?simm ] dip B.cond-encode ;

PRIVATE>

: BEQ ( simm19 -- ) EQ B.cond ;
: BNE ( simm19 -- ) NE B.cond ;
: BCS ( simm19 -- ) CS B.cond ;
: BHS ( simm19 -- ) HS B.cond ;
: BCC ( simm19 -- ) CC B.cond ;
: BLO ( simm19 -- ) LO B.cond ;
: BMI ( simm19 -- ) MI B.cond ;
: BPL ( simm19 -- ) PL B.cond ;
: BVS ( simm19 -- ) VS B.cond ;
: BVC ( simm19 -- ) VC B.cond ;
: BHI ( simm19 -- ) HI B.cond ;
: BLS ( simm19 -- ) LS B.cond ;
: BGE ( simm19 -- ) GE B.cond ;
: BLT ( simm19 -- ) LT B.cond ;
: BGT ( simm19 -- ) GT B.cond ;
: BLE ( simm19 -- ) LE B.cond ;
: BAL ( simm19 -- ) AL B.cond ;
: BNV ( simm19 -- ) NV B.cond ;

: BR ( Xn -- ) ?64-bit !SP BR-encode ;
: RET ( -- ) X30 RET-encode ;

: BL ( simm26 -- ) 26 ?simm BL-encode ;
: BLR ( Xn -- ) ?64-bit !SP BLR-encode ;

<PRIVATE

: (CBZ) ( Rt simm19 -- bw simm19 Rt ) bwd 19 ?simm swap !SP ;

PRIVATE>

: CBZ ( Rt simm19 -- ) (CBZ) CBZ-encode ;
: CBNZ ( Rt simm19 -- ) (CBZ) CBNZ-encode ;

<PRIVATE

: (TBZ) ( Rt uimm6 simm14 -- b5 b40 simm14 Rt )
    [ bw !SP ] [ rot 5 + ?uimm [ -5 shift ] [ 5 bits ] bi ] [ 14 ?simm ] tri* roll ;

PRIVATE>

: TBZ ( Rt uimm6 simm14 -- ) (TBZ) TBZ-encode ;
: TBNZ ( Rt uimm6 simm14 -- ) (TBZ) TBNZ-encode ;

<PRIVATE

: (ADR) ( Xd simm -- immlo immhi Xd ) [ 2 bits ] [ -2 shift 19 ?simm ] bi rot ?64-bit ; inline

PRIVATE>

: ADR ( Xd simm21 -- ) (ADR) ADR-encode ;
: ADRP ( Xd simm33 -- ) 12 ?>> (ADR) ADRP-encode ;

! Pseudo load with immediate literal pool
! Provide literal through relocation
: LDR= ( Rt -- )
    [ 2 LDR ] [ >bw
        [ 2 + Br ]
        [ 1 + 4 * 0 <array> % ] bi
    ] bi ;

! Arithmetic operations

<PRIVATE

: ?ADDer-bw ( Rd Rn er -- bw Rd Rn er )
    [ [ >bw ] tri@ [ = ] [ >= and ] bi-curry* [ swap ] tri ] 3keep
    roll [ 3array register-mismatch ] unless ;

ERROR: shift-amount n ;
: ADDer ( Rd Rn er -- bw Rm option imm3 Rn Rd )
    ?ADDer-bw spin [ encode dup 0 4 between? [ shift-amount ] unless ] 2dip ;

ERROR: ROR-in-arithmetic-instruction ;
: !ROR ( sr -- sr ) dup type>> 3 = [ ROR-in-arithmetic-instruction ] when ;

: ADDsr ( Rd Rn sr -- bw shift2 Rm imm6 Rn Rd ) !ROR 3bw spin !SP/!SP [ encode ] 2dip ;

: ADDr ( Rd Rn r -- Rd Rn er/sr ) 0 2pick [ SP? ] either? [ <LSL*> ] [ <LSL> ] if ;

: ADDi ( Rd Rn imm -- bw sh imm12 Rn Rd ) [ 2bw ] dip spin [ split-imm ] 2dip ;

PRIVATE>

GENERIC: ADD ( Rd Rn operand -- )
M: extended-register ADD ADDer ?SP/?SP ADDer-encode ;
M: shifted-register ADD ADDsr ADDsr-encode ;
M: register ADD ADDr ADD ;
M: integer ADD ADDi ?SP/?SP ADDi-encode ;

GENERIC: ADDS ( Rd Rn operand -- )
M: extended-register ADDS ADDer ?SP/!SP ADDSer-encode ;
M: shifted-register ADDS ADDsr ADDSsr-encode ;
M: register ADDS ADDr ADDS ;
M: integer ADDS ADDi ?SP/!SP ADDSi-encode ;

GENERIC: SUB ( Rd Rn operand -- )
M: extended-register SUB ADDer ?SP/?SP SUBer-encode ;
M: shifted-register SUB ADDsr SUBsr-encode ;
M: register SUB ADDr SUB ;
M: integer SUB ADDi ?SP/?SP SUBi-encode ;

GENERIC: SUBS ( Rd Rn operand -- )
M: extended-register SUBS ADDer ?SP/!SP SUBSer-encode ;
M: shifted-register SUBS ADDsr SUBSsr-encode ;
M: register SUBS ADDr SUBS ;
M: integer SUBS ADDi ?SP/!SP SUBSi-encode ;

: ADC ( Rd Rn Rm -- ) 3bw [ !SP ] tri@ spin ADC-encode ;
: ADCS ( Rd Rn Rm -- ) 3bw [ !SP ] tri@ spin ADCS-encode ;

: SBC ( Rd Rn Rm -- ) 3bw [ !SP ] tri@ spin SBC-encode ;
: SBCS ( Rd Rn Rm -- ) 3bw [ !SP ] tri@ spin SBCS-encode ;

<PRIVATE

: NEGsr ( Rd operand -- bw shift2 Rm imm6 Rd ) !ROR 2bw swap !SP [ encode ] dip ;

PRIVATE>

GENERIC: NEG ( Rd operand -- )
M: shifted-register NEG NEGsr NEGsr-encode ;
M: register NEG 0 <LSL> NEG ;

GENERIC: NEGS ( Rd operand -- )
M: shifted-register NEGS NEGsr NEGSsr-encode ;
M: register NEGS 0 <LSL> NEGS ;

: NGC ( Rd Rm -- ) 2bw !SP/!SP swap NGC-encode ;
: NGCS ( Rd Rm -- ) 2bw !SP/!SP swap NGCS-encode ;

! Logical operations

<PRIVATE

: ANDsr ( Rd Rn sr -- bw shift2 Rm imm6 Rn Rd ) 3bw spin !SP/!SP [ encode ] 2dip ;

: ANDi ( Rd Rn imm -- bw (N)immrimms Rn Rd ) [ 2bw ] dip reach encode-bitmask spin ;

PRIVATE>

GENERIC: AND ( Rd Rn operand -- )
M: shifted-register AND ANDsr ANDsr-encode ;
M: register AND 0 <LSL> AND ;
M: integer AND ANDi ?SP/!SP ANDi-encode ;

GENERIC: ANDS ( Rd Rn operand -- )
M: shifted-register ANDS ANDsr ANDSsr-encode ;
M: register ANDS 0 <LSL> ANDS ;
M: integer ANDS ANDi !SP/!SP ANDSi-encode ;

GENERIC: EOR ( Rd Rn operand -- )
M: shifted-register EOR ANDsr EORsr-encode ;
M: register EOR 0 <LSL> EOR ;
M: integer EOR ANDi ?SP/!SP EORi-encode ;

GENERIC: ORR ( Rd Rn operand -- )
M: shifted-register ORR ANDsr ORRsr-encode ;
M: register ORR 0 <LSL> ORR ;
M: integer ORR ANDi ?SP/!SP ORRi-encode ;

GENERIC: BIC ( Rd Rn operand -- )
M: shifted-register BIC ANDsr BICsr-encode ;
M: register BIC 0 <LSL> BIC ;

GENERIC: BICS ( Rd Rn operand -- )
M: shifted-register BICS ANDsr BICSsr-encode ;
M: register BICS 0 <LSL> BICS ;

GENERIC: EON ( Rd Rn operand -- )
M: shifted-register EON ANDsr EONsr-encode ;
M: register EON 0 <LSL> EON ;

GENERIC: ORN ( Rd Rn operand -- )
M: shifted-register ORN ANDsr ORNsr-encode ;
M: register ORN 0 <LSL> ORN ;

GENERIC: MVN ( Rd operand -- )
M: shifted-register MVN 2bw swap [ encode ] dip MVNsr-encode ;
M: register MVN 0 <LSL> MVN ;

! Move operations

<PRIVATE

! TODO i think we can optimize this
: split-move-imm ( imm -- shift uimm16 )
    64 bits 0 swap
    [ dup [ 16 bits 0 = ] [ -16 shift 0 > ] bi and ] [ -16 shift [ 1 + ] dip ] while ;

: move-immediate? ( imm -- ? ) split-move-imm [ 4 < ] [ dup 16 bits = ] bi* and ;

: MOV-imm ( Rd imm -- bw shift uimm16 Rd ) bwd swap !SP [ split-move-imm ] dip ;

PRIVATE>

GENERIC: MOV ( Rd operand -- )
M: register MOV 2bw swap 2dup [ SP? ] either? [ MOVsp-encode ] [ MOVr-encode ] if ;
<PRIVATE ERROR: mov-immediate imm ; PRIVATE>
M: integer MOV {
    { [ dup move-immediate? ] [ MOV-imm MOVZ-encode ] }
    { [ dup bitnot move-immediate? ] [ bitnot MOV-imm MOVN-encode ] }
    { [ dup logical-immediate? ] [ bwd pick encode-bitmask swap ?SP MOVbi-encode ] }
    [ mov-immediate ]
} cond ;

<PRIVATE

: (MOV) ( Rd uimm16 shift -- bw shift imm16 Rd ) [ !SP bw ] [ 16 ?uimm ] [ 4 ?>> ] tri* spin ;

PRIVATE>

: MOVK ( Rd uimm16 shift -- ) (MOV) MOVK-encode ;
: MOVN ( Rd uimm16 shift -- ) (MOV) MOVK-encode ;
: MOVZ ( Rd uimm16 shift -- ) (MOV) MOVZ-encode ;

! Shift operations

<PRIVATE

: ASR-imm ( Rd Rn imm -- bw bw immr bw Rn Rd )
    [ 2bw !SP/!SP ] dip spin [ dupd over [ 5 + ?uimm ] keep ] 2dip ;

PRIVATE>

GENERIC: ASR ( Rd Rn operand -- )
M: integer ASR ASR-imm ASRi-encode ;
M: register ASR 3bw spin !SP/!SP ASRr-encode ;

GENERIC: LSL ( Rd Rn operand -- )
M: integer LSL [ 2bw !SP/!SP ] dip spin [ dupd over 5 + [ ?uimm bitnot [ 1 + ] keep ] [ '[ _ bits ] bi@ ] bi ] 2dip LSLi-encode ;
M: register LSL 3bw spin !SP/!SP LSLr-encode ;

GENERIC: LSR ( Rd Rn operand -- )
M: integer LSR ASR-imm LSRi-encode ;
M: register LSR 3bw spin !SP/!SP LSRr-encode ;

GENERIC: ROR ( Rd Rn operand -- )
M: integer ROR [ 2bw !SP/!SP ] dip spin [ dupd over 5 + ?uimm ] 2dip [ tuck ] dip RORi-encode ;
M: register ROR 3bw spin !SP/!SP RORr-encode ;

: UBFIZ ( Rd Rn lsb width -- ) [ 2bw !SP/!SP ] 2dip 2swap swap [ dupdd pick 5 + [ '[ _ ?uimm neg ] [ 1 - ] bi* ] [ '[ _ bits ] bi@ ] bi ] 2dip UBFIZ-encode ;

! Multiply operations

: MUL ( Rd Rn Rm -- ) 3bw spin [ !SP ] tri@ MUL-encode ;

: MNEG ( Rd Rn Rm -- ) 3bw spin [ !SP ] tri@ MNEG-encode ;

: MADD ( Rd Rn Rm Ra -- ) 4bw 2swap swap [ !SP ] 4 napply MADD-encode ;

: MSUB ( Rd Rn Rm Ra -- ) 4bw 2swap swap [ !SP ] 4 napply MSUB-encode ;

: SMADDL ( Xd Wn Wm Xa -- ) [ ?64-bit ] 3dip [ [ ?32-bit ] bi@ ] dip ?64-bit [ !SP ] 4 napply SMADDL-encode ;

: SMSUBL ( Xd Wn Wm Xa -- ) [ ?64-bit ] 3dip [ [ ?32-bit ] bi@ ] dip ?64-bit [ !SP ] 4 napply SMSUBL-encode ;

: UMADDL ( Xd Wn Wm Xa -- ) [ ?64-bit ] 3dip [ [ ?32-bit ] bi@ ] dip ?64-bit [ !SP ] 4 napply UMADDL-encode ;

: UMSUBL ( Xd Wn Wm Xa -- ) [ ?64-bit ] 3dip [ [ ?32-bit ] bi@ ] dip ?64-bit [ !SP ] 4 napply UMSUBL-encode ;

: SMULL ( Xd Wn Wm -- ) [ ?64-bit ] 2dip [ ?32-bit ] bi@ [ !SP ] tri@ SMULL-encode ;

: SMNEGL ( Xd Wn Wm -- ) [ ?64-bit ] 2dip [ ?32-bit ] bi@ [ !SP ] tri@ SMNEGL-encode ;

: UMULL ( Xd Wn Wm -- ) [ ?64-bit ] 2dip [ ?32-bit ] bi@ [ !SP ] tri@ UMULL-encode ;

: UMNEGL ( Xd Wn Wm -- ) [ ?64-bit ] 2dip [ ?32-bit ] bi@ [ !SP ] tri@ UMNEGL-encode ;

: SMULH ( Xd Xn Xm -- ) spin [ ?64-bit !SP ] tri@ SMULH-encode ;

: UMULH ( Xd Xn Xm -- ) spin [ ?64-bit !SP ] tri@ UMULH-encode ;

! Division operations

: SDIV ( Rd Rn Rm -- ) 3bw spin [ !SP ] tri@ SDIV-encode ;

: UDIV ( Rd Rn Rm -- ) 3bw spin [ !SP ] tri@ UDIV-encode ;

! Comparison operations

<PRIVATE

: inject-ZR ( Rn operand -- RZR Rn operand ) [ [ >ZR ] keep ] dip ;

PRIVATE>

: CMN ( Rn operand -- ) inject-ZR ADDS ;

: CMP ( Rn operand -- ) inject-ZR SUBS ;

: TST ( Rn operand -- ) inject-ZR ANDS ;

! Conditional operations

<PRIVATE

: (CSEL) ( Rd Rn Rm cond -- bw Rm cond Rn Rd ) [ 3bw [ !SP ] tri@ ] dip 2swap swap ;

PRIVATE>

: CSEL ( Rd Rn Rm cond -- ) (CSEL) CSEL-encode ;

: CSINC ( Rd Rn Rm cond -- ) (CSEL) CSINC-encode ;

: CSINV ( Rd Rn Rm cond -- ) (CSEL) CSINV-encode ;

: CSNEG ( Rd Rn Rm cond -- ) (CSEL) CSNEG-encode ;

: CINC ( Rd Rn cond -- ) dupd CSINC ;

: CINV ( Rd Rn cond -- ) dupd CSINV ;

: CNEG ( Rd Rn cond -- ) dupd CSNEG ;

<PRIVATE

: (CSET) ( Rd cond -- Rd RZR RZR cond ) [ !SP dup >ZR dup ] dip 1 bitxor ;

PRIVATE>

: CSET ( Rd cond -- ) (CSET) CSINC ;

: CSETM ( Rd cond -- ) (CSET) CSINV ;

<PRIVATE

: CCMPr ( Rn Rm nzcv cond -- bw Rm cond4 Rn nzcv )
    [ 2bw !SP/!SP ] 2dip [ 4 ?uimm ] bi@ swapd 2swap ;

: CCMPi ( Rn imm5 nzcv cond -- bw imm5 cond4 Rn nzcv )
    [ bw !SP ] 3dip [ 5 ?uimm ] 2dip [ 4 ?uimm ] bi@ swapd 2swap ;

PRIVATE>

GENERIC#: CCMP 2 ( Rn Rm/imm nzcv cond -- )
M: register CCMP CCMPr CCMPr-encode ;
M: integer CCMP CCMPi CCMPi-encode ;

GENERIC#: CCMN 2 ( Rn Rm/imm nzcv cond -- )
M: register CCMN CCMPr CCMNr-encode ;
M: integer CCMN CCMPi CCMNi-encode ;

! Special instructions

: CLZ ( Rn Rd -- ) 2bw !SP/!SP swap CLZ-encode ;

: CLS ( Rn Rd -- ) 2bw !SP/!SP swap CLS-encode ;

: MRS ( Rt op0 op1 CRn CRm op2 -- ) 6 nrot !SP ?64-bit MRS-encode ;

: MSR ( op0 op1 CRn CRm op2 Rt -- ) !SP ?64-bit MSRr-encode ;

: SVC ( uimm16 -- ) 16 ?uimm SVC-encode ;

: NOP ( -- ) NOP-encode ;

! Other base instructions

: BRK ( uimm16 -- ) 16 ?uimm BRK-encode ;

: CNT ( Rd Rn -- ) 2bw !SP/!SP swap CNT-encode ;

: HLT ( uimm16 -- ) 16 ?uimm HLT-encode ;

! FP data movement instructions

<PRIVATE

: (FMOVgen) ( Rn Rd -- sf ftype rmode opcode )
    [ name>> first ] bi@ 2array {
        { { 72 87 } { 0 3 0 6 } }
        { { 72 88 } { 1 3 0 6 } }
        { { 87 72 } { 0 3 0 7 } }
        { { 87 83 } { 0 0 0 7 } }
        { { 83 87 } { 0 0 0 6 } }
        { { 88 72 } { 1 3 0 7 } }
        { { 88 68 } { 1 1 0 7 } }
        { { 68 88 } { 1 1 0 6 } }
    } at first4 ;

PRIVATE>

: FMOVgen ( Rn Rd -- ) [ (FMOVgen) ] 2keep FMOVgen-encode ;

! FP data conversion instructions

: FCVT ( Rd Rn -- ) swap [ [ >var ] bi@ ] 2keep FCVT-encode ;

: FCVTZSsi ( Rd Rn -- ) [ [ >bw ] [ >var ] bi* ] 2keep swap FCVTZSsi-encode ;

: SCVTFsi ( Rn Rd -- ) [ [ >bw ] [ >var ] bi* ] 2keep SCVTFsi-encode ;

! FP data processing instructions

: FSQRTs ( Rd Rn -- )   2var swap FSQRTs-encode ;

: FADDs ( Rd Rn Rm -- ) 3var spin FADDs-encode ;

: FSUBs ( Rd Rn Rm -- ) 3var spin FSUBs-encode ;

: FMULs ( Rd Rn Rm -- ) 3var spin FMULs-encode ;

: FDIVs ( Rd Rn Rm -- ) 3var spin FDIVs-encode ;

: FMAXs ( Rd Rn Rm -- ) 3var spin FMAXs-encode ;

: FMINs ( Rd Rn Rm -- ) 3var spin FMINs-encode ;
