! Copyright (C) 2025 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors alien alien.c-types alien.data assocs
byte-arrays classes.algebra classes.struct combinators
compiler.cfg compiler.cfg.comparisons compiler.cfg.instructions
compiler.cfg.intrinsics compiler.cfg.registers
compiler.cfg.stack-frame compiler.codegen.gc-maps
compiler.codegen.labels compiler.codegen.relocation
compiler.constants cpu.architecture cpu.arm.64.assembler
generalizations kernel layouts literals make math math.bitwise
memory namespaces sequences system vm ;
FROM: cpu.arm.64.assembler => B ;
IN: cpu.arm.64

M: arm.64 enable-cpu-features ( -- )
    enable-alien-4-intrinsics
    enable-float-intrinsics
    enable-fsqrt
    enable-float-min/max
    enable-min/max
    enable-log2
    enable-bit-count
    ! enable-bit-test
    ;

M: arm.64 machine-registers ( -- assoc )
    {
        { int-regs ${
            X0  X1  X2  X3  X4  X5  X6  X7  X8
            X10 X11 X12 X13 X14 X15
        } }
        { float-regs ${
            V0  V1  V2  V3  V4  V5  V6  V7
            V16 V17 V18 V19 V20 V21 V22 V23
            V24 V25 V26 V27 V28 V29 V30
        } }
    } ;

M: arm.64 %safepoint ( -- )
    SAFEPOINT dup [] STR ;

: extend-offset ( register immediate -- operand )
    dup 9 >signed over = [
        [ temp ] dip MOV
        temp
    ] unless [+] ;

: loc>operand ( loc -- operand )
    [ ds-loc? DS RS ? ] [ n>> cells neg extend-offset ] bi ;

M: arm.64 %peek ( DST loc -- )
    loc>operand LDR ;

M: arm.64 immediate-comparand? ( obj -- ? )
    add/sub-immediate? ;

: (%compare-imm) ( SRC1 src2 -- )
    [ tag-fixnum ] [ \ f type-number ] if* CMP ;

: cc>cond ( cc -- cond )
    order-cc {
        ${ cc<  LT }
        ${ cc<= LE }
        ${ cc>  GT }
        ${ cc>= GE }
        ${ cc=  EQ }
        ${ cc/= NE }
    } at ;

:: (%boolean) ( DST TEMP -- )
    DST \ f type-number MOV
    t TEMP (LDR=) rel-literal ;

:: %boolean ( DST cc TEMP -- )
    DST TEMP (%boolean)
    DST TEMP DST cc CSEL ;

M: arm.64 %compare-imm ( DST SRC1 src2 cc TEMP -- )
    [ (%compare-imm) ] [ cc>cond ] [ %boolean ] tri* ;

M: arm.64 %replace ( SRC loc -- )
    loc>operand STR ;

M: arm.64 %return ( -- )
    RET ;

M: arm.64 %inc ( loc -- )
    [ ds-loc? DS RS ? dup ] [ n>> cells ] bi
    dup 0 > [ ADD ] [ neg SUB ] if ;

M: arm.64 %compare-imm-branch ( label SRC1 src2 cc -- )
    [ (%compare-imm) ] dip cc>cond B.cond ;

M: arm.64 immediate-store? ( obj -- ? )
    {
        { [ dup fixnum? ] [ tag-fixnum 16 unsigned-immediate? ] }
        { [ dup not ] [ drop t ] }
        [ drop f ]
    } cond ;

M: arm.64 stack-frame-size ( stack-frame -- n )
    (stack-frame-size) 2 cells + 16 align ;

M: arm.64 %prologue ( n -- )
    neg dup 10 >signed over = [
        [ FP LR SP ] dip [pre] STP
    ] [
        [ SP dup ] dip neg SUB
        FP LR SP [] STP
    ] if
    FP SP MOV ;

M: arm.64 %call ( word -- )
    0 BL rc-relative-arm-b rel-word-pic ;

M: arm.64 %replace-imm ( imm loc -- )
    {
        { [ over 0 = ] [
            nip XZR
            swap
        ] }
        { [ over fixnum? ] [
            [
                [ temp ] dip tag-fixnum MOV
                temp
            ] dip
        ] }
        { [ swap not ] [
            temp \ f type-number MOV
            [ temp ] dip
        ] }
    } cond %replace ;

M: arm.64 %epilogue ( n -- )
    dup 10 >signed over = [
        [ FP LR SP ] dip [post] LDP
    ] [
        FP LR SP [] LDP
        [ SP dup ] dip ADD
    ] if ;

M: arm.64 %jump ( word -- )
    PIC-TAIL 2 insns ADR
    0 B rc-relative-arm-b rel-word-pic-tail ;

M: arm.64 fused-unboxing? ( -- ? )
    t ;

M: arm.64 %load-reference ( DST src -- )
    [ swap (LDR=) rel-literal ]
    [ \ f type-number MOV ] if* ;

M: arm.64 %jump-label ( label -- )
    0 B rc-relative-arm-b label-fixup ;

: imm>halfwords ( uimm64 -- assoc )
    4 <iota> [
        [ -16 * shift 16 bits ] keep
    ] with map>alist ;

: %load-immediate-movz ( DST assoc -- )
    [ 0 = ] reject-keys [ 0 0 MOVZ ] [
        unclip overd
        first2 MOVZ
        [ first2 MOVK ] with each
    ] if-empty ;

: %load-immediate-movn ( DST assoc -- )
    [ 0xffff = ] reject-keys [ 0 0 MOVN ] [
        unclip overd
        first2 [ bitnot 16 bits ] dip MOVN
        [ first2 MOVK ] with each
    ] if-empty ;

M: arm.64 %load-immediate ( DST src -- )
    imm>halfwords
    dup keys [ [ 0 = ] count ] [ [ 0xffff = ] count ] bi >=
    [ %load-immediate-movz ] [ %load-immediate-movn ] if ;

M: arm.64 %clear ( loc -- )
    [ 297 ] dip %replace-imm ;

: stack@ ( n -- operand )
    [ SP ] dip 2 cells + [+] ;

: spill@ ( n -- operand )
    spill-offset stack@ ;

: ?spill-slot ( obj -- obj )
    dup spill-slot? [ n>> spill@ ] when ;

UNION: integer-rep int-rep tagged-rep ;

ERROR: %copy-not-implemented dst src rep ;

M: arm.64 %copy ( dst src rep -- )
    [ [ ?spill-slot ] bi@ ] dip {
        { [ 2over eq? ] [ 3drop ] }
        { [
            3dup
            [ [ register? ] both? ]
            [ integer-rep? ] bi* and
        ] [ drop MOV ] }
        { [
            3dup
            [ offset? ]
            [ register? ]
            [ integer-rep? ] tri* and and
        ] [ drop swap STR ] }
        { [
            3dup
            [ register? ]
            [ offset? ]
            [ integer-rep? ] tri* and and
        ] [ drop LDR ] }
        { [
            3dup
            [ offset? ]
            [ register? ]
            [ double-rep? ] tri* and and
        ] [ drop >D swap STR ] }
        { [
            3dup
            [ register? ]
            [ offset? ]
            [ double-rep? ] tri* and and
        ] [ drop [ >D ] dip LDR ] }
        { [
            3dup
            [ offset? ]
            [ register? ]
            [ float-rep? ] tri* and and
        ] [ drop >S swap STR ] }
        { [
            3dup
            [ register? ]
            [ offset? ]
            [ float-rep? ] tri* and and
        ] [ drop [ >S ] dip LDR ] }
        { [
            3dup
            [ [ register? ] both? ]
            [ vector-rep? ] bi* and
        ] [ drop MOVv ] }
        { [
            3dup
            [ offset? ]
            [ register? ]
            [ vector-rep? ] tri* and and
        ] [ drop >Q swap STR ] }
        { [
            3dup
            [ register? ]
            [ offset? ]
            [ vector-rep? ] tri* and and
        ] [ drop [ >Q ] dip LDR ] }
        [ %copy-not-implemented ]
    } cond ;

M: arm.64 param-regs ( abi -- regs )
    drop {
        { int-regs ${ X0 X1 X2 X3 X4 X5 X6 X7 } }
        { float-regs ${ V0 V1 V2 V3 V4 V5 V6 V7 } }
    } ;

M: arm.64 return-regs ( -- regs )
    {
        { int-regs ${ X0 X1 } }
        { float-regs ${ V0 } }
    } ;

M: arm.64 stack-cleanup ( stack-size return abi -- n )
    3drop 0 ;

M:: arm.64 %save-context ( TEMP1 TEMP2 -- )
    DS RS CTX context-datastack-offset [+] STP ;

M: arm.64 %vm-field ( DST offset -- )
    [ VM ] dip [+] LDR ;

M: arm.64 %c-invoke ( symbols dll gc-map -- )
    [ (LDR=BLR*) ] dip gc-map-here ;

: return-reg ( rep -- reg )
    reg-class-of return-regs at first ;

:: %store-stack-param ( vreg rep n -- )
    rep return-reg vreg rep %copy
    n stack@ rep return-reg rep %copy ;

: %store-reg-param ( vreg rep reg -- )
    -rot %copy ;

: %prepare-var-args ( reg-inputs -- )
    drop ;

: %load-reg-param ( vreg rep reg -- )
    swap %copy ;

M:: arm.64 %alien-assembly ( varargs? reg-inputs stack-inputs reg-outputs dead-outputs cleanup stack-size quot -- )
    stack-inputs [ first3 %store-stack-param ] each
    reg-inputs [ first3 %store-reg-param ] each
    varargs? [ reg-inputs %prepare-var-args ] when
    quot call( -- )
    reg-outputs [ first3 %load-reg-param ] each ;

M: arm.64 %alien-invoke ( varargs? reg-inputs stack-inputs reg-outputs dead-outputs cleanup stack-size symbols dll gc-map -- )
    '[ _ _ _ %c-invoke ] %alien-assembly ;

M:: arm.64 %check-nursery-branch ( label size cc TEMP1 TEMP2 -- )
    TEMP1 VM vm-nursery-here-offset [+] LDR
    TEMP1 dup size ADD
    TEMP2 VM vm-nursery-end-offset [+] LDR
    TEMP1 TEMP2 CMP
    cc {
        { cc<= [ label BLE ] }
        { cc/<= [ label BGT ] }
    } case ;

M: arm.64 %call-gc ( gc-map -- )
    \ minor-gc %call gc-map-here ;

M: arm.64 %reload ( dst rep src -- )
    swap %copy ;

M:: arm.64 %allot ( DST size class TEMP -- )
    DST VM vm-nursery-here-offset [+] LDR
    temp DST size data-alignment get align ADD
    temp VM vm-nursery-here-offset [+] STR
    temp class type-number tag-header MOV
    temp DST [] STR
    DST dup class type-number ADD ;

: alien@ ( reg n -- operand )
    cells alien type-number - [+] ;

M:: arm.64 %box-alien ( DST SRC TEMP -- )
    <label> :> end
    DST \ f type-number MOV
    SRC end CBZ
    DST 5 cells alien TEMP %allot
    temp \ f type-number MOV
    temp DST 1 alien@ STR ! base
    temp DST 2 alien@ STR ! expired
    SRC  DST 3 alien@ STR ! displacement
    SRC  DST 4 alien@ STR ! address
    end resolve-label ;

M: arm.64 dummy-stack-params? ( -- ? )
    f ;

M: arm.64 dummy-fp-params? ( -- ? )
    f ;

: %load-return ( DST rep -- )
    dup return-reg %load-reg-param ;

M:: arm.64 %unbox ( DST SRC func rep -- )
    arg1 SRC tagged-rep %copy
    arg2 VM MOV
    func f f %c-invoke
    DST rep %load-return ;

M: arm.64 %spill ( src rep dst -- )
    -rot %copy ;

M:: arm.64 %unbox-any-c-ptr ( DST SRC -- )
    <label> :> end
    DST XZR MOV
    SRC \ f type-number CMP
    end BEQ
    DST SRC tag-mask get AND
    DST alien type-number CMP
    DST SRC byte-array-offset ADD
    end BNE
    DST SRC alien-offset [+] LDR
    end resolve-label ;

M: arm.64 frame-reg ( -- REG )
    FP ;

: next-stack@ ( n -- operand )
    [ temp ] dip 2 cells + [+] ;

:: %load-stack-param ( vreg rep n -- )
    rep return-reg n next-stack@ rep %copy
    vreg rep return-reg rep %copy ;

M: arm.64 %callback-inputs ( reg-outputs stack-outputs -- )
    temp FP [] LDR
    [ [ first3 %load-reg-param ] each ]
    [ [ first3 %load-stack-param ] each ] bi*
    arg1 VM MOV
    arg2 XZR MOV
    "begin_callback" f f %c-invoke ;

M: arm.64 %callback-outputs ( reg-inputs -- )
    arg1 VM MOV
    "end_callback" f f %c-invoke
    [ first3 %store-reg-param ] each ;

M:: arm.64 %box ( DST SRC func rep gc-map -- )
    rep reg-class-of f param-regs at first SRC rep %copy
    rep int-rep? arg2 arg1 ? VM MOV
    func f gc-map %c-invoke
    DST int-rep %load-return ;

M: arm.64 %sar-imm ( DST SRC1 src2 -- )
    ASR ;

M:: arm.64 %dispatch ( SRC TEMP -- )
    temp 3 insns ADR
    temp dup SRC [+] LDR
    temp BR ;

M: arm.64 dummy-int-params? ( -- ? )
    f ;

M: arm.64 %load-double ( DST src -- )
    [ >D 0 LDR ] [
        double <ref>
        rc-relative-arm-b.cond/ldr rel-binary-literal
    ] bi* ;

M: arm.64 %load-memory-imm ( DST BASE offset rep c-type -- )
    or* [ extend-offset ] dip LDR* ;

M: arm.64 %store-memory-imm ( SRC BASE offset rep c-type -- )
    or* [ extend-offset ] dip STR* ;

M: arm.64 gc-root-offset ( spill-slot -- n )
    n>> spill-offset 2 cells + cell /i ;

M: arm.64 %shl-imm ( DST SRC1 src2 -- )
    LSL ;

M: arm.64 %convert-integer ( DST SRC c-type -- )
    [ [ 0 ] dip heap-size 8 * ] [ c-type-signed ] bi
    [ SBFX ] [ UBFX ] if ;

M: arm.64 value-struct? ( c-type -- ? )
    heap-size 16 <= ;

M: arm.64 complex-addressing? ( -- ? )
    f ;

M: arm.64 %double>single-float ( DST SRC -- )
    [ >S ] [ >D ] bi* FCVT ;

M: arm.64 %single>double-float ( DST SRC -- )
    [ >D ] [ >S ] bi* FCVT ;

: ?spill-slot* ( obj -- obj )
    dup spill-slot? [
        [ temp ] dip n>> spill@ LDR
        temp
    ] when ;

M: arm.64 %alien-indirect ( src varargs? reg-inputs stack-inputs reg-outputs dead-outputs cleanup stack-size gc-map -- )
    [ 8 nrot ] dip '[
        temp _ ?spill-slot* MOV
        TRAMPOLINE BLR
        _ gc-map-here
    ] %alien-assembly ;

! intrinsics

M: arm.64 immediate-arithmetic? ( n -- ? )
    add/sub-immediate? ;

M: arm.64 %and-imm ( DST SRC1 src2 -- )
    AND ;

M: arm.64 %compare ( dst src1 src2 cc temp -- )
    [ CMP ] [ cc>cond ] [ %boolean ] tri* ;

M: arm.64 %compare-integer-imm ( dst src1 src2 cc temp -- )
    %compare ;

M: arm.64 %compare-branch ( label src1 src2 cc -- )
    [ CMP ] dip cc>cond B.cond ;

M: arm.64 %compare-integer-imm-branch ( label src1 src2 cc -- )
    %compare-branch ;

M: arm.64 %slot-imm ( DST OBJ slot tag -- )
    slot-offset extend-offset LDR ;

M: arm.64 %set-slot-imm ( SRC OBJ slot tag -- )
    slot-offset extend-offset STR ;

M: arm.64 %add-imm ( DST SRC1 src2 -- )
    ADDS ;

M: arm.64 %sub-imm ( DST SRC1 src2 -- )
    SUBS ;

M: arm.64 %and ( DST SRC1 SRC2 -- )
    AND ;

M: arm.64 %add ( DST SRC1 SRC2 -- )
    ADDS ;

M: arm.64 %or ( DST SRC1 SRC2 -- )
    ORR ;

M: arm.64 %xor ( DST SRC1 SRC2 -- )
    EOR ;

M: arm.64 %not ( DST SRC -- )
    MVN ;

M: arm.64 %xor-imm ( DST SRC1 src2 -- )
    EOR ;

: fixnum-overflow ( label DST SRC1 SRC2 cc quot -- )
    dip {
        { cc-o [ BVS ] }
        { cc/o [ BVC ] }
    } case ; inline

M: arm.64 %fixnum-add ( label DST SRC1 SRC2 cc -- )
    [ ADDS ] fixnum-overflow ;

M:: arm.64 %fixnum-mul ( label DST SRC1 SRC2 cc -- )
    temp SRC1 SRC2 SMULH
    DST SRC1 SRC2 MUL
    temp DST 63 <ASR> CMP
    label cc {
        { cc-o [ BNE ] }
        { cc/o [ BEQ ] }
    } case ;

M: arm.64 %neg ( DST SRC -- )
    NEG ;

M: arm.64 %sar ( DST SRC1 SRC2 -- )
    ASR ;

M: arm.64 immediate-bitwise? ( n -- ? )
    logical-64-bit-immediate? ;

! :: (%slot) ( OBJ SLOT scale tag -- register SLOT scale )
!     tag 0 = [ OBJ ] [
!         temp OBJ tag dup neg? [ neg ADD ] [ SUB ] if
!         temp
!     ] if SLOT scale ; inline

M: arm.64 %slot ( DST OBJ SLOT scale tag -- )
    ! (%slot) <LSL> [+] LDR ;
    2drop [+] LDR ;

M: arm.64 %set-slot ( SRC OBJ SLOT scale tag -- )
    ! (%slot) <LSL> [+] STR ;
    2drop [+] STR ;

:: (%write-barrier) ( CARD TEMP -- )
    temp card-mark MOV
    CARD dup card-bits LSR
    TEMP VM vm-cards-offset-offset [+] LDR
    temp CARD TEMP [+] STRB
    CARD dup deck-bits card-bits - LSR
    TEMP VM vm-decks-offset-offset [+] LDR
    temp CARD TEMP [+] STRB ;

M:: arm.64 %write-barrier ( SRC SLOT scale tag CARD TEMP -- )
    ! CARD SRC SLOT scale tag (%slot) <LSL*> ADD
    CARD SRC SLOT ADD
    CARD TEMP (%write-barrier) ;

M:: arm.64 %write-barrier-imm ( SRC slot tag CARD TEMP -- )
    CARD SRC slot tag slot-offset ADD
    CARD TEMP (%write-barrier) ;

M: arm.64 %shl ( DST SRC1 SRC2 -- )
    LSL ;

M: arm.64 %mul ( DST SRC1 SRC2 -- )
    MUL ;

M: arm.64 %sub ( DST SRC1 SRC2 -- )
    SUBS ;

M: arm.64 %shr-imm ( DST SRC1 src2 -- )
    LSR ;

:: (%memory) ( BASE DISP scale offset -- operand )
    temp BASE offset ADD
    temp DISP scale <LSL*> [+] ;

M: arm.64 %load-memory ( dst BASE DISP scale offset rep c-type -- )
    or* [ (%memory) ] dip LDR* ;

M: arm.64 %store-memory ( value BASE DISP scale offset rep c-type -- )
    or* [ (%memory) ] dip STR* ;

M: arm.64 %fixnum-sub ( label DST SRC1 SRC2 cc -- )
    [ SUBS ] fixnum-overflow ;

M:: arm.64 %mul-imm ( DST SRC1 src2 -- )
    temp XZR MOV
    temp dup src2 ADD
    DST SRC1 temp MUL ;

:: %box-displaced-alien/f ( DST DISP -- )
    temp \ f type-number MOV
    temp DST 1 alien@ STR
    DISP DST 3 alien@ STR
    DISP DST 4 alien@ STR ;

:: %box-displaced-alien/alien ( DST DISP BASE TEMP -- )
    ! set new alien's base to base.base
    temp BASE 1 alien@ LDR
    temp DST  1 alien@ STR
    ! compute displacement
    temp BASE 3 alien@ LDR
    temp dup DISP ADD
    temp DST  3 alien@ STR
    ! compute address
    temp BASE 4 alien@ LDR
    temp dup DISP ADD
    temp DST  4 alien@ STR ;

:: %box-displaced-alien/byte-array ( DST DISP BASE TEMP -- )
    BASE DST 1 alien@ STR
    DISP DST 3 alien@ STR
    temp BASE DISP ADD
    temp dup byte-array-offset ADD
    temp DST 4 alien@ STR ;

:: %box-displaced-alien/dynamic ( DST DISP BASE TEMP end -- )
    <label> :> not-f
    <label> :> not-alien
    ! check base type
    temp BASE tag-mask get AND
    ! is base f?
    temp \ f type-number CMP
    not-f BNE
    ! fill in new object
    DST DISP %box-displaced-alien/f
    end B
    not-f resolve-label
    ! is base an alien?
    temp alien type-number CMP
    not-alien BNE
    DST DISP BASE TEMP %box-displaced-alien/alien
    end B
    ! base has to be a byte array now
    not-alien resolve-label
    DST DISP BASE TEMP %box-displaced-alien/byte-array ;

M:: arm.64 %box-displaced-alien ( DST DISP BASE TEMP base-class -- )
    <label> :> end
    ! if displacement is zero, return the base
    DST BASE MOV
    DISP end CBZ
    ! allocate new object
    DST 5 cells alien TEMP %allot
    ! set expired to f
    temp \ f type-number MOV
    temp DST 2 alien@ STR
    DST DISP BASE TEMP {
        { [ base-class \ f class<= ] [ 2drop %box-displaced-alien/f ] }
        { [ base-class \ alien class<= ] [ %box-displaced-alien/alien ] }
        { [ base-class \ byte-array class<= ] [ %box-displaced-alien/byte-array ] }
        [ end %box-displaced-alien/dynamic ]
    } cond
    end resolve-label ;

M: arm.64 %set-vm-field ( SRC offset -- )
    [ VM ] dip [+] STR ;

M: arm.64 %or-imm ( DST SRC1 src2 -- )
    ORR ;

M: arm.64 %unbox-alien ( DST SRC -- )
    alien-offset [+] LDR ;

M:: arm.64 %local-allot ( DST size align offset -- )
    DST SP offset local-allot-offset 2 cells + ADD ;

M: arm.64 %load-float ( DST val -- )
    [ >S 0 LDR ] [
        alien.c-types:float <ref>
        rc-relative-arm-b.cond/ldr rel-binary-literal
    ] bi* ;

M: arm.64 return-struct-in-registers? ( c-type -- ? )
    heap-size 16 <= ;

M: arm.64 struct-return-on-stack? ( -- ? )
    f ;

! float intrinsics

M: arm.64 integer-float-needs-stack-frame? ( -- ? )
    f ;

M: arm.64 %integer>float ( DST SRC -- )
    [ >D ] dip SCVTFsi ;

M: arm.64 %add-float ( DST SRC1 SRC2 -- )
    [ >D ] tri@ FADDs ;

M: arm.64 %mul-float ( DST SRC1 SRC2 -- )
    [ >D ] tri@ FMULs ;

:: %csel-float<> ( DST TEMP -- )
    DST TEMP (%boolean)
    3 insns BEQ
    2 insns BVS
    DST TEMP MOV ;

:: %csel-float/<> ( DST TEMP -- )
    DST TEMP (%boolean)
    2 insns BEQ
    2 insns BVC
    DST TEMP MOV ;

:: (%compare-float) ( DST cc TEMP -- )
    cc {
        { cc<    [ DST LO TEMP %boolean ] }
        { cc<=   [ DST LS TEMP %boolean ] }
        { cc>    [ DST GT TEMP %boolean ] }
        { cc>=   [ DST GE TEMP %boolean ] }
        { cc=    [ DST EQ TEMP %boolean ] }
        { cc<>   [ DST    TEMP %csel-float<>  ] }
        { cc<>=  [ DST VC TEMP %boolean ] }
        { cc/<   [ DST HS TEMP %boolean ] }
        { cc/<=  [ DST HI TEMP %boolean ] }
        { cc/>   [ DST LE TEMP %boolean ] }
        { cc/>=  [ DST LT TEMP %boolean ] }
        { cc/=   [ DST NE TEMP %boolean ] }
        { cc/<>  [ DST    TEMP %csel-float/<> ] }
        { cc/<>= [ DST VS TEMP %boolean ] }
    } case ;

M: arm.64 %compare-float-ordered ( DST SRC1 SRC2 cc TEMP -- )
    [ [ >D ] bi@ FCMPE ] 2dip (%compare-float) ;

M: arm.64 %sub-float ( DST SRC1 SRC2 -- )
    [ >D ] tri@ FSUBs ;

M: arm.64 %compare-float-unordered ( DST SRC1 SRC2 cc TEMP -- )
    [ [ >D ] bi@ FCMP ] 2dip (%compare-float) ;

M: arm.64 %float>integer ( DST SRC -- )
    >D FCVTZSsi ;

M: arm.64 %div-float ( DST SRC1 SRC2 -- )
    [ >D ] tri@ FDIVs ;

: %branch-float<> ( label -- )
    3 insns BEQ
    2 insns BVS
    B ;

: %branch-float/<> ( label -- )
    2 insns BEQ
    2 insns BVC
    B ;

: (%compare-float-branch) ( label cc -- )
    {
        { cc<    [ BLO ] }
        { cc<=   [ BLS ] }
        { cc>    [ BGT ] }
        { cc>=   [ BGE ] }
        { cc=    [ BEQ ] }
        { cc<>   [ %branch-float<> ] }
        { cc<>=  [ BVC ] }
        { cc/<   [ BHS ] }
        { cc/<=  [ BHI ] }
        { cc/>   [ BLE ] }
        { cc/>=  [ BLT ] }
        { cc/=   [ BNE ] }
        { cc/<>  [ %branch-float/<> ] }
        { cc/<>= [ BVS ] }
    } case ;

M: arm.64 %compare-float-ordered-branch ( label SRC1 SRC2 cc -- )
    [ [ >D ] bi@ FCMPE ] dip (%compare-float-branch) ;

M: arm.64 %compare-float-unordered-branch ( label SRC1 SRC2 cc -- )
    [ [ >D ] bi@ FCMP ] dip (%compare-float-branch) ;

! fsqrt intrinsic

M: arm.64 %sqrt ( DST SRC -- )
    [ >D ] bi@ FSQRTs ;

! float min/max intrinsics

M: arm.64 %max-float ( DST SRC1 SRC2 -- )
    [ >D ] tri@ FMAXs ;

M: arm.64 %min-float ( DST SRC1 SRC2 -- )
    [ >D ] tri@ FMINs ;

! min/max intrinsics

M:: arm.64 %min ( DST SRC1 SRC2 -- )
    SRC1 SRC2 CMP
    DST SRC1 SRC2 LE CSEL ;

M:: arm.64 %max ( DST SRC1 SRC2 -- )
    SRC1 SRC2 CMP
    DST SRC1 SRC2 GE CSEL ;

! log2 intrinsic

M:: arm.64 %log2 ( DST SRC -- )
    DST SRC CLZ
    DST DST 64 SUB
    DST DST MVN ;

! bit-count intrinsic

M:: arm.64 %bit-count ( DST SRC -- )
    fp-temp >D SRC FMOV
    fp-temp dup CNTv
    fp-temp dup 0 ADDV
    DST fp-temp >D FMOV ;

! bit-test intrinsic

! M:: arm.64 %bit-test ( DST SRC1 src2 TEMP -- )
!     DST TEMP (%boolean)
!     SRC1 SRC2 2 insns TBZ
!     DST TEMP MOV ;

! M: arm.64 test-instruction? t ;
!
! M: arm.64 %test-branch ( label SRC1 SRC2 cc -- )
!     [ TST ] dip cc>cond B.cond ;
!
! M: arm.64 %test-imm-branch ( label SRC1 SRC2 cc -- )
!     %test-branch ;
!
! M: arm.64 %test ( DST SRC1 SRC2 cc TEMP -- )
!     [ TST ] [ cc>cond ] [ %boolean ] tri* ;
!
! M: arm.64 %test-imm ( DST SRC1 SRC2 cc TEMP -- )
!     %test ;

! SIMD

CONSTANT: int-vector-reps
    {
        char-16-rep
        uchar-16-rep
        short-8-rep
        ushort-8-rep
        int-4-rep
        uint-4-rep
        longlong-2-rep
        ulonglong-2-rep
    }

CONSTANT: float-vector-reps
    {
        float-4-rep
        double-2-rep
    }

M: arm.64 %zero-vector-reps vector-reps ;
M: arm.64 %fill-vector-reps vector-reps ;
M: arm.64 %gather-vector-2-reps { double-2-rep longlong-2-rep ulonglong-2-rep } ;
M: arm.64 %gather-int-vector-2-reps { longlong-2-rep ulonglong-2-rep } ;
M: arm.64 %gather-vector-4-reps { float-4-rep int-4-rep uint-4-rep } ;
M: arm.64 %gather-int-vector-4-reps { int-4-rep uint-4-rep } ;
M: arm.64 %select-vector-reps f ;
M: arm.64 %alien-vector-reps f ;
M: arm.64 %shuffle-vector-reps { char-16-rep uchar-16-rep } ;
M: arm.64 %shuffle-vector-imm-reps vector-reps ;
M: arm.64 %shuffle-vector-halves-imm-reps vector-reps ;
M: arm.64 %merge-vector-reps vector-reps ;
M: arm.64 %float-pack-vector-reps { double-2-rep } ;
M: arm.64 %signed-pack-vector-reps int-vector-reps ;
M: arm.64 %unsigned-pack-vector-reps int-vector-reps ;
M: arm.64 %unpack-vector-head-reps vector-reps ;
M: arm.64 %unpack-vector-tail-reps vector-reps ;
M: arm.64 %integer>float-vector-reps { int-4-rep longlong-2-rep } ;
M: arm.64 %float>integer-vector-reps float-vector-reps ;
M: arm.64 %compare-vector-reps { cc< cc<= cc> cc>= cc= cc<> } member? vector-reps and ;

M: arm.64 %compare-vector-ccs
    nip {
        { cc<  [ { { cc>  t } } f ] }
        { cc<= [ { { cc>= t } } f ] }
        { cc>  [ { { cc>  f } } f ] }
        { cc>= [ { { cc>= f } } f ] }
        { cc=  [ { { cc=  f } } f ] }
        { cc<> [ { { cc=  f } } t ] }
    } case ;

M: arm.64 %move-vector-mask-reps vector-reps ;
M: arm.64 %add-vector-reps vector-reps ;
M: arm.64 %saturated-add-vector-reps int-vector-reps ;
M: arm.64 %sub-vector-reps vector-reps ;
M: arm.64 %saturated-sub-vector-reps int-vector-reps ;
M: arm.64 %mul-vector-reps vector-reps ;
M: arm.64 %mul-high-vector-reps int-vector-reps ;
M: arm.64 %mul-horizontal-add-vector-reps vector-reps ;
M: arm.64 %div-vector-reps float-vector-reps ;
M: arm.64 %min-vector-reps vector-reps ;
M: arm.64 %max-vector-reps vector-reps ;
M: arm.64 %avg-vector-reps int-vector-reps ;
M: arm.64 %dot-vector-reps int-vector-reps ;
M: arm.64 %sad-vector-reps int-vector-reps ;
M: arm.64 %sqrt-vector-reps float-vector-reps ;
M: arm.64 %horizontal-add-vector-reps int-vector-reps ;
M: arm.64 %abs-vector-reps vector-reps ;
M: arm.64 %and-vector-reps int-vector-reps ;
M: arm.64 %andn-vector-reps int-vector-reps ;
M: arm.64 %or-vector-reps int-vector-reps ;
M: arm.64 %xor-vector-reps int-vector-reps ;
M: arm.64 %not-vector-reps int-vector-reps ;
M: arm.64 %shl-vector-reps int-vector-reps ;
M: arm.64 %shr-vector-reps int-vector-reps ;
M: arm.64 %shl-vector-imm-reps int-vector-reps ;
M: arm.64 %shr-vector-imm-reps int-vector-reps ;

: >spec ( rep -- size )
    {
        { char-16-rep 0 }
        { uchar-16-rep 0 }
        { short-8-rep 1 }
        { ushort-8-rep 1 }
        { int-4-rep 2 }
        { uint-4-rep 2 }
        { longlong-2-rep 3 }
        { ulonglong-2-rep 3 }
        { float-4-rep 1 }
        { double-2-rep 3 }
    } at ;

: integer/float ( Rd Rn Rm rep int-op fp-op -- )
    [ [ >spec ] [ scalar-rep? ] bi ] 2dip if ; inline

: signed/unsigned ( Rd Rn Rm rep u-op s-op -- )
    [ [ >spec ] [ signed-int-vector-rep? ] bi ] 2dip if ; inline

: signed/unsigned/float ( Rd Rn Rm rep s-op u-op f-op -- )
    {
        { [ reach signed-int-vector-rep? ] [ 2drop ] }
        { [ reach unsigned-int-vector-rep? ] [ drop nip ] }
        { [ reach float-vector-rep? ] [ 2nip ] }
    } cond [ >spec ] dip call( Rd Rn Rm rep -- ) ; inline

M: arm.64 %zero-vector
    drop dup dup EORv ;

M: arm.64 %fill-vector
    drop dup dup BICv ;

M:: arm.64 %gather-vector-2 ( DST SRC1 SRC2 rep -- )
    DST SRC1 0 0 rep INSelt
    DST SRC2 1 0 rep INSelt ;

M:: arm.64 %gather-int-vector-2 ( DST SRC1 SRC2 rep -- )
    DST SRC1 0 rep INSgen
    DST SRC2 1 rep INSgen ;

M:: arm.64 %gather-vector-4 ( DST SRC1 SRC2 SRC3 SRC4 rep -- )
    DST SRC1 0 0 rep INSelt
    DST SRC1 1 0 rep INSelt
    DST SRC1 2 0 rep INSelt
    DST SRC1 3 0 rep INSelt ;

M:: arm.64 %gather-int-vector-4 ( DST SRC1 SRC2 SRC3 SRC4 rep -- )
    DST SRC1 0 rep INSgen
    DST SRC2 1 rep INSgen
    DST SRC3 2 rep INSgen
    DST SRC4 3 rep INSgen ;

M: arm.64 %select-vector UMOV ;

M: arm.64 %shuffle-vector ( DST SRC SHUFFLE rep -- )
    drop TBL ;

ERROR: not-implemented ;

M: arm.64 %shuffle-vector-imm ( DST SRC shuffle rep -- )
    4drop not-implemented ;

M: arm.64 %shuffle-vector-halves-imm  ( DST SRC1 SRC2 shuffle rep -- )
    5drop not-implemented ;

M: arm.64 %tail>head-vector drop dupd 8 EXT ;
M: arm.64 %merge-vector-head >spec TRN1 ;
M: arm.64 %merge-vector-tail >spec TRN2 ;
M: arm.64 %float-pack-vector >spec FCVTN ;
M: arm.64 %signed-pack-vector >spec [ nip SQXTN ] 4keep nipd SQXTN2 ;
M: arm.64 %unsigned-pack-vector >spec [ nip SQXTUN ] 4keep nipd SQXTUN2 ;
M: arm.64 %unpack-vector-head SXTL ;
M: arm.64 %unpack-vector-tail SHLL ;
M: arm.64 %integer>float-vector >spec SCVTFvi ;
M: arm.64 %float>integer-vector >spec 2/ FCVTZSvi ;

M: arm.64 %compare-vector
    {
        { cc=  [ [ CMEQ ] [ FCMEQ ] integer/float ] }
        { cc>  [ [ CMHI ] [ CMGT ] [ FCMGT ] signed/unsigned/float ] }
        { cc>= [ [ CMHS ] [ CMGE ] [ FCMGE ] signed/unsigned/float ] }
    } case ;

:: %move-int-vector-mask ( DST SRC -- )
    DST SRC CMLT
    fp-temp >Q 2 insns LDR
    5 insns B
    {
        0x01 0x02 0x04 0x08 0x10 0x20 0x40 0x80
        0x01 0x02 0x04 0x08 0x10 0x20 0x40 0x80
    } %
    DST dup fp-temp ANDv
    fp-temp DST 0 SHLL
    DST dup 0 SHLL2
    fp-temp dup 0 ADDV
    DST dup 0 ADDV
    DST dup fp-temp 0 ZIP1 ;

M: arm.64 %move-vector-mask ( DST SRC rep -- )
    {
        { double-2-rep [ 2drop not-implemented ] }
        { float-4-rep [ 2drop not-implemented ] }
        [ drop %move-int-vector-mask ]
    } case ;

M:: arm.64 %mul-high-vector ( DST SRC1 SRC2 rep -- )
    DST SRC1 SRC2 rep [ SMULL ] [ UMULL ] signed/unsigned
    fp-temp SRC1 SRC2 rep [ SMULL2 ] [ UMULL2 ] signed/unsigned
    rep scalar-rep-of rep-size 2 shift :> imm
    DST DST imm rep SHRN
    DST fp-temp imm rep SHRN2 ;

M: arm.64 %mul-horizontal-add-vector [ MLAv ] [ FMLAv ] integer/float ;
M: arm.64 %add-vector [ ADDv ] [ FADDv ] integer/float ;
M: arm.64 %saturated-add-vector [ SQADD ] [ UQADD ] signed/unsigned ;
M: arm.64 %sub-vector [ SUBv ] [ FSUBv ] integer/float ;
M: arm.64 %saturated-sub-vector [ SQSUB ] [ UQSUB ] signed/unsigned ;
M: arm.64 %mul-vector [ MULv ] [ FMULv ] integer/float ;
M: arm.64 %div-vector >spec FDIVv ;
M: arm.64 %min-vector [ SMINv ] [ UMINv ] [ FMINv ] signed/unsigned/float ;
M: arm.64 %max-vector [ SMAXv ] [ UMAXv ] [ FMAXv ] signed/unsigned/float ;
M: arm.64 %avg-vector [ SHADD ] [ UHADD ] signed/unsigned ; ! srhadd, urhadd?
M: arm.64 %dot-vector [ SDOT ] [ UDOT ] signed/unsigned ;
M: arm.64 %sad-vector [ [ SABD ] [ UABD ] signed/unsigned ] 4keep 2nip dupd >spec ADDV ;
M: arm.64 %sqrt-vector >spec FSQRTv ;
M: arm.64 %horizontal-add-vector >spec ADDPv ;
M: arm.64 %abs-vector [ ABSv ] [ FABSv ] integer/float ;
M: arm.64 %and-vector drop ANDv ;
M: arm.64 %andn-vector drop BICv ;
M: arm.64 %or-vector drop ORRv ;
M: arm.64 %xor-vector drop EORv ;
M: arm.64 %not-vector drop MVNv ;
M: arm.64 %shl-vector [ SSHL ] [ USHL ] signed/unsigned ;
M: arm.64 %shr-vector [ 2nipd dupd >spec NEGv ] 4keep %shl-vector ;
M: arm.64 %shl-vector-imm >spec SHL ;
M: arm.64 %shr-vector-imm [ SSHR ] [ USHR ] signed/unsigned ;
M: arm.64 %integer>scalar drop [ >D ] dip FMOV ;
M: arm.64 %scalar>integer drop >D FMOV ;
M: arm.64 %vector>scalar %copy ;
M: arm.64 %scalar>vector %copy ;

M: arm.64 %load-vector ( DST src rep -- )
    drop
    [ >Q 0 LDR ]
    [ rc-relative-arm-b.cond/ldr rel-binary-literal ] bi* ;
