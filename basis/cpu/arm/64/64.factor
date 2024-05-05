! Copyright (C) 2023 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors assocs compiler.cfg compiler.cfg.comparisons
compiler.cfg.instructions compiler.cfg.intrinsics
compiler.cfg.stack-frame compiler.codegen.labels
compiler.codegen.relocation compiler.constants continuations
cpu.architecture cpu.arm cpu.arm.64.assembler generalizations
kernel layouts math math.order sequences system words.symbol ;
IN: cpu.arm.64

<< ALIAS: eh? f >>

: words ( n -- n ) 4 * ; inline

: temp0 ( -- reg ) X9 ; inline
: pic-tail-reg ( -- reg ) X12 ; inline

M: arm.64 ds-reg X27 ;
M: arm.64 rs-reg X26 ;

! M: arm.64 vm-stack-space 0 ;

! TODO fix shifts
! bitnot move-immediate?
! logical-immediate?
M: arm.64 %load-immediate ( reg val -- )
    [ XZR MOV ] [
        { 0 1 2 3 } [
            tuck -16 * shift 0xffff bitand
        ] with map>alist [ 0 = ] reject-values
        unclip
        overd first2 rot MOVZ
        [ first2 rot MOVK ] with each
    ] if-zero ;

M: arm.64 %load-reference ( reg obj -- )
    [ swap LDR= f rc-absolute-cell rel-literal ]
    [ \ f type-number MOV ] if* ;

M: arm.64 %load-float ( reg val -- )
    [ fp 2 LDRlfp ] dip
    2 Br
    4 0 <array> rc-absolute rel-binary-literal ;

M: arm.64 %load-double
    [ fp 2 LDRlfp ] dip
    3 Br
    8 0 <array> rc-absolute-cell rel-binary-literal ;

M: arm.64 %load-vector 3drop ;

M: arm.64 complex-addressing? eh? ; ! x86: t
M: arm.64 dummy-fp-params? f ; ! x86.64.windows: t
M: arm.64 dummy-int-params? f ; ! ppc.64.linux: t
M: arm.64 dummy-stack-params? f ; ! ppc.64.linux: t
M: arm.64 float-right-align-on-stack? f ; ! ppc.64.linux: t
M: arm.64 fused-unboxing? eh? ; ! x86: t
M: arm.64 integer-float-needs-stack-frame? f ; ! x86.sse: f
M: arm.64 long-long-odd-register? f ; ! ppc.32: t
M: arm.64 long-long-on-stack? f ; ! x86.32: t
M: arm.64 return-struct-in-registers? drop eh? ;
M: arm.64 struct-return-on-stack? f ; ! x86.32.not-linux: t
M: arm.64 test-instruction? t ; ! t
M: arm.64 value-struct? drop eh? ;

M: arm.64 %add ADD ;
M: arm.64 %add-imm ADD ;
M: arm.64 %sub SUB ;
M: arm.64 %sub-imm SUB ;
M: arm.64 %mul MUL ;
M: arm.64 %mul-imm [ temp0 XZR ] dip ADDi temp0 MUL ;

M: arm.64 %neg NEG ;

M: arm.64 %min
    2dup CMPr
    rot LT CSEL ;

M: arm.64 %max
    2dup CMPr
    rot GT CSEL ;

M: arm.64 %log2 ( dst src -- ) '[ CLZ ] [ dup 64 SUB ] [ dup MVN ] tri ;

M: arm.64 %bit-count CNT ;

M: arm.64 %bit-test
    ! [ 2^ swap TSTi ] dip
    ! swap dup EQ CSEL ;
    TBNZ

M: arm.64 %and AND ;
M: arm.64 %and-imm AND ;
M: arm.64 %not MVN ;
M: arm.64 %or ORR ;
M: arm.64 %or-imm ORR ;
M: arm.64 %sar ASR ;
M: arm.64 %sar-imm ASR ;
M: arm.64 %shl LSL ;
M: arm.64 %shl-imm LSL ;
M: arm.64 %shr LSR ;
M: arm.64 %shr-imm LSR ;
M: arm.64 %xor EOR ;
M: arm.64 %xor-imm EOR ;

M: arm.64 %copy ( dst src rep -- )
    2over eq? [ 3drop ] [
        ! [ [ ?spill-slot ] bi@ ] dip
        ! 2over [ register? ] both?
        ! [ copy-register* ] [ copy-memory* ] if
        3drop
    ] if ;

: fixnum-overflow ( label dst src1 src2 cc quot -- )
    [ call ] curry dip {
        { cc-o VS }
        { cc/o VC }
    } at B.cond ; inline

M: arm.64 %fixnum-add [ ADD ] fixnum-overflow ;
M: arm.64 %fixnum-sub [ SUB ] fixnum-overflow ;
M: arm.64 %fixnum-mul [ MUL ] fixnum-overflow ;

M: arm.64 %add-float FADDs ;
M: arm.64 %sub-float FSUBs ;
M: arm.64 %mul-float FMULs ;
M: arm.64 %div-float FDIVs ;
M: arm.64 %min-float FMINs ;
M: arm.64 %max-float FMAXs ;
M: arm.64 %sqrt FSQRTs ;

M: arm.64 %single>double-float FCVT ;
M: arm.64 %double>single-float FCVT ;

M: arm.64 %integer>float SCVTFsi ;
M: arm.64 %float>integer FCVTZSsi ;

M: arm.64 %zero-vector 2drop ;
M: arm.64 %fill-vector 2drop ;
M: arm.64 %gather-vector-2 4drop ;
M: arm.64 %gather-int-vector-2 4drop ;
M: arm.64 %gather-vector-4 6 ndrop ;
M: arm.64 %gather-int-vector-4 6 ndrop ;
M: arm.64 %select-vector 4drop ;
M: arm.64 %shuffle-vector 4drop ;
M: arm.64 %shuffle-vector-imm 4drop ;
M: arm.64 %shuffle-vector-halves-imm 5drop ;
M: arm.64 %tail>head-vector 3drop ;
M: arm.64 %merge-vector-head 4drop ;
M: arm.64 %merge-vector-tail 4drop ;
M: arm.64 %float-pack-vector 3drop ;
M: arm.64 %signed-pack-vector 4drop ;
M: arm.64 %unsigned-pack-vector 4drop ;
M: arm.64 %unpack-vector-head 3drop ;
M: arm.64 %unpack-vector-tail 3drop ;
M: arm.64 %integer>float-vector 3drop ;
M: arm.64 %float>integer-vector 3drop ;
M: arm.64 %compare-vector 5drop ;
M: arm.64 %move-vector-mask 3drop ;
M: arm.64 %test-vector 5drop ;
M: arm.64 %test-vector-branch 5drop ;
M: arm.64 %add-vector 4drop ;
M: arm.64 %saturated-add-vector 4drop ;
M: arm.64 %add-sub-vector 4drop ;
M: arm.64 %sub-vector 4drop ;
M: arm.64 %saturated-sub-vector 4drop ;
M: arm.64 %mul-vector 4drop ;
M: arm.64 %mul-high-vector 4drop ;
M: arm.64 %mul-horizontal-add-vector 4drop ;
M: arm.64 %saturated-mul-vector 4drop ;
M: arm.64 %div-vector 4drop ;
M: arm.64 %min-vector 4drop ;
M: arm.64 %max-vector 4drop ;
M: arm.64 %avg-vector 4drop ;
M: arm.64 %dot-vector 4drop ;
M: arm.64 %sad-vector 4drop ;
M: arm.64 %sqrt-vector 3drop ;
M: arm.64 %horizontal-add-vector 4drop ;
M: arm.64 %horizontal-sub-vector 4drop ;
M: arm.64 %abs-vector 3drop ;
M: arm.64 %and-vector 4drop ;
M: arm.64 %andn-vector 4drop ;
M: arm.64 %or-vector 4drop ;
M: arm.64 %xor-vector 4drop ;
M: arm.64 %not-vector 3drop ;
M: arm.64 %shl-vector 4drop ;
M: arm.64 %shr-vector 4drop ;
M: arm.64 %shl-vector-imm 4drop ;
M: arm.64 %shr-vector-imm 4drop ;
M: arm.64 %horizontal-shl-vector-imm 4drop ;
M: arm.64 %horizontal-shr-vector-imm 4drop ;

M: arm.64 %integer>scalar 3drop ;
M: arm.64 %scalar>integer 3drop ;
M: arm.64 %vector>scalar 3drop ;
M: arm.64 %scalar>vector 3drop ;

M: arm.64 %zero-vector-reps f ;
M: arm.64 %fill-vector-reps f ;
M: arm.64 %gather-vector-2-reps f ;
M: arm.64 %gather-int-vector-2-reps f ;
M: arm.64 %gather-vector-4-reps f ;
M: arm.64 %gather-int-vector-4-reps f ;
M: arm.64 %select-vector-reps f ;
M: arm.64 %alien-vector-reps f ;
M: arm.64 %shuffle-vector-reps f ;
M: arm.64 %shuffle-vector-imm-reps f ;
M: arm.64 %shuffle-vector-halves-imm-reps f ;
M: arm.64 %merge-vector-reps f ;
M: arm.64 %float-pack-vector-reps f ;
M: arm.64 %signed-pack-vector-reps f ;
M: arm.64 %unsigned-pack-vector-reps f ;
M: arm.64 %unpack-vector-head-reps f ;
M: arm.64 %unpack-vector-tail-reps f ;
M: arm.64 %integer>float-vector-reps f ;
M: arm.64 %float>integer-vector-reps f ;
M: arm.64 %compare-vector-reps drop f ;
M: arm.64 %compare-vector-ccs nip eh? ;
M: arm.64 %move-vector-mask-reps f ;
M: arm.64 %test-vector-reps f ;
M: arm.64 %add-vector-reps f ;
M: arm.64 %saturated-add-vector-reps f ;
M: arm.64 %add-sub-vector-reps f ;
M: arm.64 %sub-vector-reps f ;
M: arm.64 %saturated-sub-vector-reps f ;
M: arm.64 %mul-vector-reps f ;
M: arm.64 %mul-high-vector-reps f ;
M: arm.64 %mul-horizontal-add-vector-reps f ;
M: arm.64 %saturated-mul-vector-reps f ;
M: arm.64 %div-vector-reps f ;
M: arm.64 %min-vector-reps f ;
M: arm.64 %max-vector-reps f ;
M: arm.64 %avg-vector-reps f ;
M: arm.64 %dot-vector-reps f ;
M: arm.64 %sad-vector-reps f ;
M: arm.64 %sqrt-vector-reps f ;
M: arm.64 %horizontal-add-vector-reps f ;
M: arm.64 %horizontal-sub-vector-reps f ;
M: arm.64 %abs-vector-reps f ;
M: arm.64 %and-vector-reps f ;
M: arm.64 %andn-vector-reps f ;
M: arm.64 %or-vector-reps f ;
M: arm.64 %xor-vector-reps f ;
M: arm.64 %not-vector-reps f ;
M: arm.64 %shl-vector-reps f ;
M: arm.64 %shr-vector-reps f ;
M: arm.64 %shl-vector-imm-reps f ;
M: arm.64 %shr-vector-imm-reps f ;
M: arm.64 %horizontal-shl-vector-imm-reps f ;
M: arm.64 %horizontal-shr-vector-imm-reps f ;

M: arm.64 %unbox-alien 2drop ;
M: arm.64 %unbox-any-c-ptr 2drop ;
M: arm.64 %box-alien 3drop ;
M: arm.64 %box-displaced-alien 5drop ;

M: arm.64 %convert-integer 3drop ;

M: arm.64 %load-memory 7 ndrop ;
M: arm.64 %load-memory-imm 5drop ;
M: arm.64 %store-memory 7 ndrop ;
M: arm.64 %store-memory-imm 5drop ;

M: arm.64 %alien-global 3drop ;
M: arm.64 %vm-field 2drop ;
M: arm.64 %set-vm-field 2drop ;

M: arm.64 %allot 4drop ;
M: arm.64 %write-barrier 6 ndrop ;
M: arm.64 %write-barrier-imm 5drop ;

M: arm.64 stack-frame-size
    (stack-frame-size) cell + 16 align ;

M: arm.64 %call
    LR SP -16 [,]! STR
    0 BL rc-relative-arm64-branch rel-word-pic
    LR SP 16 [], LDR ;

M: arm.64 %epilogue
    cell + 16 align [ SP dup ADDr ] unless-zero ;

M: arm.64 %jump
    4 pic-tail-reg ADR
    0 Br rc-relative-arm64-branch rel-word-pic-tail ;

M: arm.64 %jump-label
    0 Br rc-relative-arm64-branch label-fixup ;

M: arm.64 %prologue
    cell - 16 align [ SP dup SUBr ] unless-zero ;

M: arm.64 %return RET ;

M: arm.64 %safepoint
    3 words temp0 LDRl
    0 temp0 W0 STRuoff
    3 words Br
    NOP NOP rc-absolute-cell rel-safepoint ;

M: arm.64 %compare 5drop ;
M: arm.64 %compare-imm 5drop ;
M: arm.64 %compare-integer-imm 5drop ;
M: arm.64 %test 5drop ;
M: arm.64 %test-imm 5drop ;
M: arm.64 %compare-float-ordered 5drop ;
M: arm.64 %compare-float-unordered 5drop ;

M: arm.64 %compare-branch 4drop ;
M: arm.64 %compare-imm-branch 4drop ;
M: arm.64 %compare-integer-imm-branch 4drop ;
M: arm.64 %test-branch 4drop ;
M: arm.64 %test-imm-branch 4drop ;
M: arm.64 %compare-float-ordered-branch 4drop ;
M: arm.64 %compare-float-unordered-branch 4drop ;

M: arm.64 %dispatch 2drop ;

M: arm.64 %c-invoke 3drop ;

M: arm.64 %call-gc drop ;
M: arm.64 %check-nursery-branch 5drop ;

M: arm.64 %clear drop ;
M: arm.64 %peek 2drop ;
M: arm.64 %replace 2drop ;
M: arm.64 %replace-imm 2drop ; ! imm SP 0 [,] STRuoff
M: arm.64 %inc drop ;

M: arm.64 machine-registers {
    {
        int-regs {
            X0 X1 X2 X3 X4 X5 X6 X7
            X8 X9 X10 X11 X12 X13 X14 X15
            X19 X20 X21 X22 X23 X24
        }
    } {
        float-regs {
            V0 V1 V2 V3 V4 V5 V6 V7
            V16 V17 V18 V19 V20 V21 V22 V23 V24 V25 V26 V27 V28
            V29 V30 V31
        }
    }
} ;

M: arm.64 param-regs drop {
    { int-regs { X0 X1 X2 X3 X4 X5 X6 X7 X8 } }
    { float-regs { V0 V1 V2 V3 V4 V5 V6 V7 } }
} ;

M: arm.64 return-regs {
    { int-regs { X0 X1 X2 X3 X4 X5 X6 X7 X8 } }
    { float-regs { V0 V1 V2 V3 V4 V5 V6 V7 } }
} ;

M: arm.64 %set-slot 5drop ;
M: arm.64 %set-slot-imm 4drop ;
M: arm.64 %slot 5drop ;
M: arm.64 %slot-imm 4drop ;

M: arm.64 %spill 3drop ;
M: arm.64 %reload 3drop ;
M: arm.64 gc-root-offset ;

M: arm.64 immediate-arithmetic? arithmetic-immediate? ;
M: arm.64 immediate-bitwise? logical-immediate? ;
M: arm.64 immediate-comparand? drop eh? ; ! %compare-imm
M: arm.64 immediate-store? drop eh? ; ! %replace-imm

M: arm.64 %unbox 4drop ;
M: arm.64 %unbox-long-long 4drop ;
M: arm.64 %local-allot 4drop ;
M: arm.64 %box 5drop ;
M: arm.64 %box-long-long 5drop ;
M: arm.64 %save-context 2drop ;

M: arm.64 %alien-invoke 10 ndrop ;
M: arm.64 %alien-indirect 9 ndrop ;
M: arm.64 %alien-assembly 8 ndrop ;
M: arm.64 %callback-inputs 2drop ;
M: arm.64 %callback-outputs drop ;
M: arm.64 stack-cleanup 2drop ;
M: arm.64 enable-cpu-features
    enable-min/max
    enable-log2
    enable-bit-test
    enable-alien-4-intrinsics
    enable-float-min/max
    enable-bit-count
    enable-float-intrinsics
    enable-fsqrt ;
