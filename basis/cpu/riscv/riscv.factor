! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: accessors compiler.cfg.intrinsics compiler.cfg.registers
compiler.codegen.labels compiler.codegen.relocation
compiler.constants cpu.architecture cpu.riscv.assembler
generalizations kernel layouts literals math math.bitwise system
;
FROM: cpu.riscv.assembler => and neg not or xor ;
IN: cpu.riscv

M: riscv machine-registers {
    { int-regs ${
        a0 a1 a2 a3 a4 a5 a6 a7
        t0 t1 t2 t3 t4 t5 t6
    } }
    { float-regs ${
        fa0 fa1 fa2 fa3 fa4 fa5 fa6 fa7
        ft0 ft1 ft2 ft3 ft4 ft5 ft6 ft7 ft8 ft9 ft10 ft11
    } }
} ;

M: riscv frame-reg x8 ;

M: riscv complex-addressing? f ;

M: riscv gc-root-offset ( spill-slot -- n ) ;

M: riscv %load-immediate ( reg val -- ) [ zero mv ] [ swap li rel-literal ] if-zero ;
M: riscv %load-reference ( reg obj -- ) swap li rel-literal ;

: loc> ( loc -- reg imm ) [ ds-loc? ds rs ? ] [ n>> math:neg cells ] bi ;

M: riscv %peek ( vreg loc -- ) loc> lc ;
M: riscv %replace ( vreg loc -- ) loc> sc ;
M: riscv %replace-imm ( src loc -- ) [ drop zero ] dip loc> sc ;

M:: riscv %clear ( loc -- )
    t0 4752 mvi
    t0 loc loc> sc ;

M: riscv %inc ( loc -- ) loc> dupd addi ;

M: riscv stack-frame-size ( stack-frame -- n ) ;
M: riscv %call ( word -- ) jali rel-word-pic ;
M: riscv %jump ( word -- ) ji rel-word-pic-tail ;
M: riscv %jump-label ( label -- ) 0 j rc-relative-riscv-i label-fixup ;
M: riscv %return ( -- ) ret ;

M: riscv %dispatch ( src temp -- ) 2drop ;

M: riscv %slot ( dst obj slot scale tag -- ) 5drop ;
M: riscv %slot-imm ( dst obj slot tag -- ) slot-offset lc ;
M: riscv %set-slot ( src obj slot scale tag -- ) 5drop ;
M: riscv %set-slot-imm ( src obj slot tag -- ) slot-offset sc ;

M: riscv %add add ;
M: riscv %add-imm addi ;
M: riscv %sub sub ;
M: riscv %sub-imm math:neg addi ;
M: riscv %mul mul ;
M: riscv %mul-imm 3drop ;
M: riscv %and and ;
M: riscv %and-imm andi ;
M: riscv %or or ;
M: riscv %or-imm ori ;
M: riscv %xor xor ;
M: riscv %xor-imm xori ;
M: riscv %shl sll ;
M: riscv %shl-imm slli ;
M: riscv %shr srl ;
M: riscv %shr-imm srli ;
M: riscv %sar sra ;
M: riscv %sar-imm srai ;
M: riscv %min 3drop ;
M: riscv %max 3drop ;
M: riscv %not not ;
M: riscv %neg neg ;
M: riscv %log2 ( dst src -- ) 2drop ;
M: riscv %bit-count ( dst src -- ) 2drop ;
M: riscv %bit-test ( dst src1 src2 temp -- ) 4drop ;

M: riscv %copy ( dst src rep -- ) 3drop ;

M: riscv %fixnum-add ( label dst src1 src2 cc -- ) 5drop ;
M: riscv %fixnum-sub ( label dst src1 src2 cc -- ) 5drop ;
M: riscv %fixnum-mul ( label dst src1 src2 cc -- ) 5drop ;

M: riscv %add-float fadd.d ;
M: riscv %sub-float fsub.d ;
M: riscv %mul-float fmul.d ;
M: riscv %div-float fdiv.d ;
M: riscv %min-float fmin.d ;
M: riscv %max-float fmax.d ;
M: riscv %sqrt fsqrt.d ;

M: riscv %single>double-float ( dst src -- ) fcvt.s.d ;
M: riscv %double>single-float ( dst src -- ) fcvt.d.s ;

M: riscv integer-float-needs-stack-frame? f ;

M: riscv %integer>float ( dst src -- ) fcvt.d.l ;
M: riscv %float>integer ( dst src -- ) fcvt.l.d ;

M: riscv %zero-vector ( dst rep -- ) 2drop ;
M: riscv %fill-vector ( dst rep -- ) 2drop ;
M: riscv %gather-vector-2 ( dst src1 src2 rep -- ) 4drop ;
M: riscv %gather-int-vector-2 ( dst src1 src2 rep -- ) 4drop ;
M: riscv %gather-vector-4 ( dst src1 src2 src3 src4 rep -- ) 6 ndrop ;
M: riscv %gather-int-vector-4 ( dst src1 src2 src3 src4 rep -- ) 6 ndrop ;
M: riscv %select-vector ( dst src n rep -- ) 4drop ;
M: riscv %shuffle-vector ( dst src shuffle rep -- ) 4drop ;
M: riscv %shuffle-vector-imm ( dst src shuffle rep -- ) 4drop ;
M: riscv %shuffle-vector-halves-imm ( dst src1 src2 shuffle rep -- ) 5drop ;
M: riscv %tail>head-vector ( dst src rep -- ) 3drop ;
M: riscv %merge-vector-head ( dst src1 src2 rep -- ) 4drop ;
M: riscv %merge-vector-tail ( dst src1 src2 rep -- ) 4drop ;
M: riscv %float-pack-vector ( dst src rep -- ) 3drop ;
M: riscv %signed-pack-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %unsigned-pack-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %unpack-vector-head ( dst src rep -- ) 3drop ;
M: riscv %unpack-vector-tail ( dst src rep -- ) 3drop ;
M: riscv %integer>float-vector ( dst src rep -- ) 3drop ;
M: riscv %float>integer-vector ( dst src rep -- ) 3drop ;
M: riscv %compare-vector ( dst src1 src2 rep cc -- ) 5drop ;
M: riscv %move-vector-mask ( dst src rep -- ) 3drop ;
M: riscv %test-vector ( dst src1 temp rep vcc -- ) 5drop ;
M: riscv %test-vector-branch ( label src1 temp rep vcc -- ) 5drop ;
M: riscv %add-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %saturated-add-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %add-sub-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %sub-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %saturated-sub-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %mul-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %mul-high-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %mul-horizontal-add-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %saturated-mul-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %div-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %min-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %max-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %avg-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %dot-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %sad-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %sqrt-vector ( dst src rep -- ) 3drop ;
M: riscv %horizontal-add-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %horizontal-sub-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %abs-vector ( dst src rep -- ) 3drop ;
M: riscv %and-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %andn-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %or-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %xor-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %not-vector ( dst src rep -- ) 3drop ;
M: riscv %shl-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %shr-vector ( dst src1 src2 rep -- ) 4drop ;
M: riscv %shl-vector-imm ( dst src1 src2 rep -- ) 4drop ;
M: riscv %shr-vector-imm ( dst src1 src2 rep -- ) 4drop ;
M: riscv %horizontal-shl-vector-imm ( dst src1 src2 rep -- ) 4drop ;
M: riscv %horizontal-shr-vector-imm ( dst src1 src2 rep -- ) 4drop ;

M: riscv %integer>scalar ( dst src rep -- ) 3drop ;
M: riscv %scalar>integer ( dst src rep -- ) 3drop ;
M: riscv %vector>scalar ( dst src rep -- ) 3drop ;
M: riscv %scalar>vector ( dst src rep -- ) 3drop ;

M: riscv %zero-vector-reps ( -- reps ) f ;
M: riscv %fill-vector-reps ( -- reps ) f ;
M: riscv %gather-vector-2-reps ( -- reps ) f ;
M: riscv %gather-int-vector-2-reps ( -- reps ) f ;
M: riscv %gather-vector-4-reps ( -- reps ) f ;
M: riscv %gather-int-vector-4-reps ( -- reps ) f ;
M: riscv %select-vector-reps ( -- reps ) f ;
M: riscv %alien-vector-reps ( -- reps ) f ;
M: riscv %shuffle-vector-reps ( -- reps ) f ;
M: riscv %shuffle-vector-imm-reps ( -- reps ) f ;
M: riscv %shuffle-vector-halves-imm-reps ( -- reps ) f ;
M: riscv %merge-vector-reps ( -- reps ) f ;
M: riscv %float-pack-vector-reps ( -- reps ) f ;
M: riscv %signed-pack-vector-reps ( -- reps ) f ;
M: riscv %unsigned-pack-vector-reps ( -- reps ) f ;
M: riscv %unpack-vector-head-reps ( -- reps ) f ;
M: riscv %unpack-vector-tail-reps ( -- reps ) f ;
M: riscv %integer>float-vector-reps ( -- reps ) f ;
M: riscv %float>integer-vector-reps ( -- reps ) f ;
M: riscv %compare-vector-reps ( cc -- reps ) ;
M: riscv %compare-vector-ccs ( rep cc -- {cc,swap?}s not? ) ;
M: riscv %move-vector-mask-reps ( -- reps ) f ;
M: riscv %test-vector-reps ( -- reps ) f ;
M: riscv %add-vector-reps ( -- reps ) f ;
M: riscv %saturated-add-vector-reps ( -- reps ) f ;
M: riscv %add-sub-vector-reps ( -- reps ) f ;
M: riscv %sub-vector-reps ( -- reps ) f ;
M: riscv %saturated-sub-vector-reps ( -- reps ) f ;
M: riscv %mul-vector-reps ( -- reps ) f ;
M: riscv %mul-high-vector-reps ( -- reps ) f ;
M: riscv %mul-horizontal-add-vector-reps ( -- reps ) f ;
M: riscv %saturated-mul-vector-reps ( -- reps ) f ;
M: riscv %div-vector-reps ( -- reps ) f ;
M: riscv %min-vector-reps ( -- reps ) f ;
M: riscv %max-vector-reps ( -- reps ) f ;
M: riscv %avg-vector-reps ( -- reps ) f ;
M: riscv %dot-vector-reps ( -- reps ) f ;
M: riscv %sad-vector-reps ( -- reps ) f ;
M: riscv %sqrt-vector-reps ( -- reps ) f ;
M: riscv %horizontal-add-vector-reps ( -- reps ) f ;
M: riscv %horizontal-sub-vector-reps ( -- reps ) f ;
M: riscv %abs-vector-reps ( -- reps ) f ;
M: riscv %and-vector-reps ( -- reps ) f ;
M: riscv %andn-vector-reps ( -- reps ) f ;
M: riscv %or-vector-reps ( -- reps ) f ;
M: riscv %xor-vector-reps ( -- reps ) f ;
M: riscv %not-vector-reps ( -- reps ) f ;
M: riscv %shl-vector-reps ( -- reps ) f ;
M: riscv %shr-vector-reps ( -- reps ) f ;
M: riscv %shl-vector-imm-reps ( -- reps ) f ;
M: riscv %shr-vector-imm-reps ( -- reps ) f ;
M: riscv %horizontal-shl-vector-imm-reps ( -- reps ) f ;
M: riscv %horizontal-shr-vector-imm-reps ( -- reps ) f ;

M: riscv %unbox-alien ( dst src -- ) 2drop ;
M: riscv %unbox-any-c-ptr ( dst src -- ) 2drop ;
M: riscv %box-alien ( dst src temp -- ) 3drop ;
M: riscv %box-displaced-alien ( dst displacement base temp base-class -- ) 5drop ;

M: riscv %convert-integer ( dst src c-type -- ) 3drop ;

M: riscv %load-memory-imm ( dst base offset rep c-type -- ) 5drop ;
M: riscv %store-memory-imm ( dst base offset rep c-type -- ) 5drop ;

M: riscv %alien-global ( dst symbol library -- ) 3drop ;
M: riscv %vm-field ( dst offset -- ) 2drop ;
M: riscv %set-vm-field ( src offset -- ) 2drop ;

M: riscv %allot ( dst size class temp -- ) 4drop ;
M: riscv %write-barrier ( src slot scale tag temp1 temp2 -- ) 6 ndrop ;
M: riscv %write-barrier-imm ( src slot tag temp1 temp2 -- ) 5drop ;

M: riscv %check-nursery-branch ( label size cc temp1 temp2 -- ) 5drop ;
M: riscv %call-gc ( gc-map -- ) drop ;

M:: riscv %prologue ( n -- )
    sp sp n cells math:neg addi
    ra sp 0 sc ;

M:: riscv %epilogue ( n -- )
    ra sp 0 lc
    sp sp n cells addi ;

M: riscv %safepoint ( -- ) safepoint dup 0 sd ;

M: riscv test-instruction? t ;

M: riscv %compare ( dst src1 src2 cc temp -- ) 5drop ;
M: riscv %compare-imm ( dst src1 src2 cc temp -- ) 5drop ;
M: riscv %compare-integer-imm ( dst src1 src2 cc temp -- ) 5drop ;
M: riscv %test ( dst src1 src2 cc temp -- ) 5drop ;
M: riscv %test-imm ( dst src1 src2 cc temp -- ) 5drop ;
M: riscv %compare-float-ordered ( dst src1 src2 cc temp -- ) 5drop ;
M: riscv %compare-float-unordered ( dst src1 src2 cc temp -- ) 5drop ;

M: riscv %compare-branch ( label cc src1 scr2 -- ) 4drop ;
M: riscv %compare-imm-branch ( label cc src1 scr2 -- ) 4drop ;
M: riscv %compare-integer-imm-branch ( label cc src1 scr2 -- ) 4drop ;
M: riscv %test-branch ( label cc src1 scr2 -- ) 4drop ;
M: riscv %test-imm-branch ( label cc src1 scr2 -- ) 4drop ;
M: riscv %compare-float-ordered-branch ( label cc src1 scr2 -- ) 4drop ;
M: riscv %compare-float-unordered-branch ( label cc src1 scr2 -- ) 4drop ;

M: riscv %spill ( src rep dst -- ) 3drop ;
M: riscv %reload ( dst rep src -- ) 3drop ;

M: riscv fused-unboxing? f ;

M: riscv immediate-arithmetic? ( n -- ? ) dup 12 >signed = ;
M: riscv immediate-bitwise? ( n -- ? ) immediate-arithmetic? ;
M: riscv immediate-comparand? ( n -- ? ) immediate-arithmetic? ;
M: riscv immediate-store? ( n -- ? ) 0 = ;

M: riscv return-regs {
    { int-regs ${ a0 a1 } }
    { float-regs ${ fa0 } }
} ;
M: riscv param-regs drop {
    { int-regs ${ a0 a1 a2 a3 a4 a5 a6 a7 } }
    { float-regs ${ fa0 fa1 fa2 fa3 fa4 fa5 fa6 fa7 } }
} ;
M: riscv return-struct-in-registers? ( c-type -- ? ) ;
M: riscv value-struct? ( c-type -- ? ) ;
M: riscv dummy-stack-params? f ;
M: riscv dummy-int-params? f ;
M: riscv dummy-fp-params? f ;
M: riscv long-long-on-stack? f ;
M: riscv long-long-odd-register? f ;
M: riscv float-right-align-on-stack? f ;
M: riscv struct-return-on-stack? f ;

M: riscv %unbox ( dst src func rep -- ) 4drop ;
M: riscv %local-allot ( dst size align offset -- ) 4drop ;
M: riscv %box ( dst src func rep gc-map -- ) 5drop ;
M: riscv %save-context ( temp1 temp2 -- ) 2drop ;
M: riscv %c-invoke ( symbols dll gc-map -- ) 3drop ;
M: riscv %alien-invoke 10 ndrop ;
M: riscv %alien-indirect 9 ndrop ;
M: riscv %alien-assembly 8 ndrop ;
M: riscv %callback-inputs 2drop ;
M: riscv %callback-outputs drop ;
M: riscv stack-cleanup 2drop ;
M: riscv enable-cpu-features
    enable-float-min/max
    enable-alien-4-intrinsics
    enable-float-intrinsics
    enable-fsqrt ;
