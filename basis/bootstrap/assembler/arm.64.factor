! Copyright (C) 2020 Doug Coleman.
! Copyright (C) 2023 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: bootstrap.image.private compiler.codegen.relocation
compiler.constants compiler.units cpu.arm.64.assembler
generic.single.private kernel kernel.private layouts
locals.backend math math.private namespaces slots.private
strings.private threads.private vocabs ;
IN: bootstrap.assembler.arm

8 \ cell set

big-endian off

! X0-X17  volatile     scratch registers
! X0-X8                parameter registers
! X0                   result register
! X16-X17              intra-procedure-call registers
! X18-X29 non-volatile scratch registers
! X18                  platform register (TEB pointer under Windows)
! X29/FP               frame pointer
! X30/LR  non-volatile link register

: words ( n -- n ) 4 * ; inline
: stack-frame-size ( -- n ) 8 bootstrap-cells ; inline

: return-reg ( -- reg ) X0 ; inline
: arg1 ( -- reg ) X0 ; inline
: arg2 ( -- reg ) X1 ; inline
: arg3 ( -- reg ) X2 ; inline
: arg4 ( -- reg ) X3 ; inline

: temp0 ( -- reg ) X9 ; inline
: temp1 ( -- reg ) X10 ; inline
: temp2 ( -- reg ) X11 ; inline
: temp3 ( -- reg ) X12 ; inline

: stack-reg ( -- reg ) SP ; inline
: link-reg ( -- reg ) X30 ; inline ! LR
: stack-frame-reg ( -- reg ) X29 ; inline ! FP
: vm-reg ( -- reg ) X28 ; inline
: ds-reg ( -- reg ) X27 ; inline
: rs-reg ( -- reg ) X26 ; inline
: ctx-reg ( -- reg ) X25 ; inline
: return-address ( -- reg ) X24 ; inline

: push-link-reg ( -- ) -16 stack-reg link-reg stack-frame-reg STPpre ;
: pop-link-reg ( -- ) 16 stack-reg link-reg stack-frame-reg LDPpost ;

: load0 ( -- ) 0 ds-reg temp0 LDRuoff ;
: load1 ( -- ) -8 ds-reg temp1 LDUR ;
: load2 ( -- ) -16 ds-reg temp2 LDUR ;
: load1/0 ( -- ) -8 ds-reg temp0 temp1 LDPsoff ;
: load2/1 ( -- ) -16 ds-reg temp1 temp2 LDPsoff ;
: load2/1* ( -- ) -8 ds-reg temp1 temp2 LDPsoff ;
: load3/2 ( -- ) -24 ds-reg temp2 temp3 LDPsoff ;
: load-arg1/2 ( -- ) -8 ds-reg arg2 arg1 LDPpre ;

: ndrop ( n -- ) bootstrap-cells ds-reg dup SUBi ;

: pop0 ( -- ) -8 ds-reg temp0 LDRpost ;
: pop1 ( -- ) -8 ds-reg temp1 LDRpost ;
: popr ( -- ) -8 rs-reg temp0 LDRpost ;
: pop-arg1 ( -- ) -8 ds-reg arg1 LDRpost ;
: pop-arg2 ( -- ) -8 ds-reg arg2 LDRpost ;

: push0 ( -- ) 8 ds-reg temp0 STRpre ;
: push1 ( -- ) 8 ds-reg temp1 STRpre ;
: push2 ( -- ) 8 ds-reg temp2 STRpre ;
: push3 ( -- ) 8 ds-reg temp3 STRpre ;
: pushr ( -- ) 8 rs-reg temp0 STRpre ;
: push-arg2 ( -- ) 8 ds-reg arg2 STRpre ;

: push-down0 ( n -- ) neg bootstrap-cells ds-reg temp0 STRpre ;

: store0 ( -- ) 0 ds-reg temp0 STRuoff ;
: store1 ( -- ) 0 ds-reg temp1 STRuoff ;
: store0/1 ( -- ) -8 ds-reg temp1 temp0 STPsoff ;
: store0/2 ( -- ) -8 ds-reg temp2 temp0 STPsoff ;
: store2/0 ( -- ) -8 ds-reg temp0 temp2 STPsoff ;
: store1/0 ( -- ) -8 ds-reg temp0 temp1 STPsoff ;
: store1/2 ( -- ) -16 ds-reg temp2 temp1 STPsoff ;

:: tag* ( reg -- ) tag-bits get reg reg LSLi ;
:: untag ( reg -- ) tag-bits get reg reg ASRi ;

: tagged>offset0 ( -- ) 1 temp0 temp0 ASRi ;

[
    stack-frame-size neg stack-reg link-reg stack-frame-reg STPpre
    stack-reg stack-frame-reg MOVsp
] JIT-PROLOG jit-define

: jit-load-context ( -- )
    vm-context-offset vm-reg ctx-reg LDRuoff ;

: jit-save-context ( -- )
    jit-load-context
    ! The reason for -16 I think is because we are anticipating a CALL
    ! instruction. After the call instruction, the contexts frame_top
    ! will point to the origin jump address.
    stack-reg temp0 MOVsp
    ! 16 stack-reg temp0 SUBi
    context-callstack-top-offset ctx-reg temp0 STRuoff
    context-datastack-offset ctx-reg ds-reg STRuoff
    context-retainstack-offset ctx-reg rs-reg STRuoff ;

: jit-restore-context ( -- )
    context-datastack-offset ctx-reg ds-reg LDRuoff
    context-retainstack-offset ctx-reg rs-reg LDRuoff ;

: absolute-call ( -- word class )
    3 words temp0 LDRl
    temp0 BLR
    3 words Br
    NOP NOP f rc-absolute-cell ; inline

: jit-call ( name -- )
    absolute-call rel-dlsym ;

[
    jit-save-context
    vm-reg arg1 MOVr
    f jit-call
    jit-restore-context
] JIT-PRIMITIVE jit-define

: absolute-jump ( -- word class )
    2 words temp0 LDRl
    temp0 BR
    NOP NOP f rc-absolute-cell ; inline

[
    5 words return-address ADR
    absolute-jump rel-word-pic-tail
] JIT-WORD-JUMP jit-define

[
    absolute-call rel-word-pic
] JIT-WORD-CALL jit-define

[
    ! pop boolean
    pop0
    ! compare boolean with f
    \ f type-number temp0 CMPi
    ! skip over true branch if equal
    5 words EQ B.cond
    ! jump to true branch
    absolute-jump rel-word
    ! jump to false branch
    absolute-jump rel-word
] JIT-IF jit-define

[
    3 words temp0 LDRl
    0 temp0 W0 STRuoff
    3 words Br
    NOP NOP rc-absolute-cell rel-safepoint
] JIT-SAFEPOINT jit-define

[
    stack-frame-size stack-reg link-reg stack-frame-reg LDPpost
] JIT-EPILOG jit-define

[ f RET ] JIT-RETURN jit-define

[
    ! load literal
    2 words temp0 LDRl
    3 words Br
    NOP NOP f rc-absolute-cell rel-literal
    ! store literal on datastack
    push0
] JIT-PUSH-LITERAL jit-define

: >r ( -- ) pop0 pushr ;
: r> ( -- ) popr push0 ;

[
    >r
    absolute-call rel-word
    r>
] JIT-DIP jit-define

[
    >r >r
    absolute-call rel-word
    r> r>
] JIT-2DIP jit-define

[
    >r >r >r
    absolute-call rel-word
    r> r> r>
] JIT-3DIP jit-define

: jit-call-quot ( -- )
    quot-entry-point-offset arg1 temp0 LDUR
    temp0 BLR ;

: jit-jump-quot ( -- )
    quot-entry-point-offset arg1 temp0 LDUR
    temp0 BR ;

[ pop-arg1 ]
[ jit-call-quot ]
[ jit-jump-quot ]
\ (call) define-combinator-primitive

[
    pop0
    word-entry-point-offset temp0 temp0 LDUR
]
[ temp0 BLR ]
[ temp0 BR ]
\ (execute) define-combinator-primitive

[
    pop0
    word-entry-point-offset temp0 temp0 LDUR
    temp0 BR
] JIT-EXECUTE jit-define

:: jit-call-1arg ( arg1s name -- )
    arg1s arg1 MOVr
    name jit-call ;

[
    arg1 arg2 MOVr
    vm-reg "begin_callback" jit-call-1arg

    ! call the quotation
    jit-call-quot

    vm-reg "end_callback" jit-call-1arg
] \ c-to-factor define-sub-primitive

[
    jit-save-context
    vm-reg arg2 MOVr
    "lazy_jit_compile" jit-call
]
[ jit-call-quot ]
[ jit-jump-quot ]
\ lazy-jit-compile define-combinator-primitive

{
    { unwind-native-frames [
        ! unwind-native-frames is marked as "special" in
        ! vm/quotations.cpp so it does not have a standard prolog
        ! Unwind stack frames
        arg2 stack-reg MOVsp

        ! Load VM pointer into vm-reg, since we're entering from
        ! C code
        2 words vm-reg LDRl
        3 words Br
        NOP NOP 0 rc-absolute-cell rel-vm

        ! Load ds and rs registers
        jit-load-context
        jit-restore-context

        ! Clear the fault flag
        vm-fault-flag-offset vm-reg XZR STRuoff

        ! Call quotation
        jit-jump-quot
    ] }

    { fpu-state [ FPSR XZR MSRr ] }
    { set-fpu-state [ ] }
} define-sub-primitives

! The *-signal-handler subprimitives are special-cased in vm/quotations.cpp
! not to trigger generation of a stack frame, so they can
! perform their own prolog/epilog preserving registers.
!
! It is important that the total is 288 and that it matches the
! constant in vm/cpu-arm.64.hpp
: jit-signal-handler-prolog ( -- )
    ! Push all registers and flags -> 256 bytes.
    -16 SP X1 X0 STPpre
    -16 SP X3 X2 STPpre
    -16 SP X5 X4 STPpre
    -16 SP X7 X6 STPpre
    -16 SP X9 X8 STPpre
    -16 SP X11 X10 STPpre
    -16 SP X13 X12 STPpre
    -16 SP X15 X14 STPpre
    -16 SP X17 X16 STPpre
    -16 SP X19 X18 STPpre
    -16 SP X21 X20 STPpre
    -16 SP X23 X22 STPpre
    -16 SP X25 X24 STPpre
    -16 SP X27 X26 STPpre
    -16 SP X29 X28 STPpre
    NZCV X0 MRS
    -16 SP X0 X30 STPpre

    ! Register parameter area 32 bytes, unused on platforms other than
    ! windows 64 bit, but including it doesn't hurt -> 288 bytes.
    4 bootstrap-cells stack-reg stack-reg SUBi ;

: jit-signal-handler-epilog ( -- )
    4 bootstrap-cells stack-reg stack-reg ADDi
    16 SP X0 X30 LDPpost
    NZCV X0 MSRr
    16 SP X29 X28 LDPpost
    16 SP X27 X26 LDPpost
    16 SP X25 X24 LDPpost
    16 SP X23 X22 LDPpost
    16 SP X21 X20 LDPpost
    16 SP X19 X18 LDPpost
    16 SP X17 X16 LDPpost
    16 SP X15 X14 LDPpost
    16 SP X13 X12 LDPpost
    16 SP X11 X10 LDPpost
    16 SP X9 X8 LDPpost
    16 SP X7 X6 LDPpost
    16 SP X5 X4 LDPpost
    16 SP X3 X2 LDPpost
    16 SP X1 X0 LDPpost ;

{
    { signal-handler [
        jit-signal-handler-prolog
        jit-save-context
        vm-signal-handler-addr-offset vm-reg temp0 LDRuoff
        temp0 BLR
        jit-signal-handler-epilog
        pop-link-reg
        f RET
    ] }
    { leaf-signal-handler [
        jit-signal-handler-prolog
        jit-save-context
        vm-signal-handler-addr-offset vm-reg temp0 LDRuoff
        temp0 BLR
        jit-signal-handler-epilog
        ! Pop the fake leaf frame along with our return address
        leaf-stack-frame-size stack-reg link-reg stack-frame-reg LDPpost
        f RET
    ] }
} define-sub-primitives

! C to Factor entry point
[
    ! Save all non-volatile registers
    -16 SP X19 X18 STPpre
    -16 SP X21 X20 STPpre
    -16 SP X23 X22 STPpre
    -16 SP X25 X24 STPpre
    -16 SP X27 X26 STPpre
    -16 SP X29 X28 STPpre
    -16 SP X30 STRpre
    stack-reg stack-frame-reg MOVsp

    jit-save-tib

    ! Load VM into vm-reg
    2 words vm-reg LDRl
    3 words Br
    NOP NOP 0 rc-absolute-cell rel-vm

    ! Save old context
    vm-context-offset vm-reg ctx-reg LDRuoff
    8 SP ctx-reg STRuoff

    ! Switch over to the spare context
    vm-spare-context-offset vm-reg ctx-reg LDRuoff
    vm-context-offset vm-reg ctx-reg STRuoff

    ! Save C callstack pointer
    stack-reg temp0 MOVsp
    context-callstack-save-offset ctx-reg temp0 STRuoff

    ! Load Factor stack pointers
    context-callstack-bottom-offset ctx-reg temp0 LDRuoff
    temp0 stack-reg MOVsp

    ctx-reg jit-update-tib
    jit-install-seh

    context-retainstack-offset ctx-reg rs-reg LDRuoff
    context-datastack-offset ctx-reg ds-reg LDRuoff

    ! Call into Factor code
    3 words temp0 LDRl
    temp0 BLR
    3 words Br
    NOP NOP f rc-absolute-cell rel-word

    ! Load C callstack pointer
    vm-context-offset vm-reg ctx-reg LDRuoff

    context-callstack-save-offset ctx-reg temp0 LDRuoff
    temp0 stack-reg MOVsp

    ! Load old context
    8 SP ctx-reg LDRuoff
    vm-context-offset vm-reg ctx-reg STRuoff

    jit-restore-tib

    ! Restore non-volatile registers
    16 SP X30 LDRpost
    16 SP X29 X28 LDPpost
    16 SP X27 X26 LDPpost
    16 SP X25 X24 LDPpost
    16 SP X23 X22 LDPpost
    16 SP X21 X20 LDPpost
    16 SP X19 X18 LDPpost

    f RET
] CALLBACK-STUB jit-define

! Polymorphic inline caches

! Load a value from a stack position
[
    4 words temp2 ADR
    3 temp2 temp2 LDRBuoff
    temp2 ds-reg temp1 LDRr
    2 words Br
    NOP f rc-absolute-1 rel-untagged
] PIC-LOAD jit-define

[
    tag-mask get temp1 temp1 ANDSi
] PIC-TAG jit-define

[
    temp1 temp0 MOVr
    tag-mask get temp1 temp1 ANDi
    tuple type-number temp1 CMPi
    [ NE B.cond ] [
        tuple-class-offset temp0 temp1 LDUR
    ] jit-conditional*
] PIC-TUPLE jit-define

[
    4 words temp2 ADR
    3 temp2 temp2 LDRBuoff
    temp2 temp1 CMPr
    2 words Br
    NOP f rc-absolute-1 rel-untagged
] PIC-CHECK-TAG jit-define

[
    3 words temp2 LDRl
    temp2 temp1 CMPr
    3 words Br
    NOP NOP f rc-absolute-cell rel-literal
] PIC-CHECK-TUPLE jit-define

[
    5 words NE B.cond
    absolute-jump rel-word
] PIC-HIT jit-define

! Inline cache miss entry points
: jit-load-return-address ( -- )
    8 stack-reg return-address LDRuoff
    3 words return-address return-address ADDi ;

! These are always in tail position with an existing stack
! frame, and the stack. The frame setup takes this into account.
: jit-inline-cache-miss ( -- )
    jit-save-context
    return-address arg1 MOVr
    vm-reg arg2 MOVr
    absolute-call nip rel-inline-cache-miss
    jit-load-context
    jit-restore-context ;

[ jit-load-return-address jit-inline-cache-miss ]
[ arg1 BLR ]
[ arg1 BR ]
\ inline-cache-miss define-combinator-primitive

[ jit-inline-cache-miss ]
[ arg1 BLR ]
[ arg1 BR ]
\ inline-cache-miss-tail define-combinator-primitive

! Megamorphic caches
[
    ! class = ...
    temp1 temp0 MOVr
    tag-mask get temp1 temp1 ANDi
    temp1 tag*
    tuple type-number tag-fixnum temp1 CMPi
    [ NE B.cond ] [
        tuple-class-offset temp0 temp1 LDUR
    ] jit-conditional*
    ! cache = ...
    2 words temp0 LDRl
    3 words Br
    NOP NOP f rc-absolute-cell rel-literal
    ! key = hashcode(class)
    temp1 temp2 MOVr
    ! key &= cache.length - 1
    mega-cache-size get 1 - bootstrap-cells temp2 temp2 ANDi
    ! cache += array-start-offset
    array-start-offset temp0 temp0 ADDi
    ! cache += key
    temp2 temp0 temp0 ADDr
    ! if(get(cache) == class)
    0 temp0 temp2 LDRuoff
    temp1 temp2 CMPr
    [ NE B.cond ] [
        ! megamorphic_cache_hits++
        2 words temp1 LDRl
        3 words Br
        NOP NOP rc-absolute-cell rel-megamorphic-cache-hits
        1 temp3 MOVwi
        temp3 temp1 STADD
        ! goto get(cache + bootstrap-cell)
        bootstrap-cell temp0 temp0 LDRuoff
        word-entry-point-offset temp0 temp0 LDUR
        temp0 BR
        ! fall-through on miss
    ] jit-conditional*
] MEGA-LOOKUP jit-define

: jit-pop-context-and-param ( -- )
    pop-arg1
    alien-offset arg1 arg1 LDUR
    pop-arg2 ;

: jit-switch-context ( reg -- )
    ! Push a bogus return address so the GC can track this frame back
    ! to the owner
    ! 0 words temp0 ADR
    ! -16 stack-reg temp0 stack-frame-reg STPpre

    ! Make the new context the current one
    ctx-reg MOVr
    vm-context-offset vm-reg ctx-reg STRuoff

    ! Load new stack pointer
    context-callstack-top-offset ctx-reg temp0 LDRuoff
    temp0 stack-reg MOVsp

    ! Load new ds, rs registers
    jit-restore-context

    ctx-reg jit-update-tib ;

: jit-push-param ( -- )
    push-arg2 ;

: jit-set-context ( -- )
    jit-pop-context-and-param
    jit-save-context
    arg1 jit-switch-context
    ! 16 stack-reg stack-reg ADDi
    jit-push-param ;

: jit-delete-current-context ( -- )
    vm-reg "delete_context" jit-call-1arg ;

: jit-pop-quot-and-param ( -- )
    pop1 pop-arg2 ;

: jit-start-context ( -- )
    ! Create the new context in return-reg. Have to save context
    ! twice, first before calling new_context() which may GC,
    ! and again after popping the two parameters from the stack.
    jit-save-context
    vm-reg "new_context" jit-call-1arg

    jit-pop-quot-and-param
    jit-save-context
    return-reg jit-switch-context
    jit-push-param
    temp1 arg1 MOVr
    jit-jump-quot ;

! Resets the active context and instead the passed in quotation
! becomes the new code that it executes.
: jit-start-context-and-delete ( -- )
    ! Updates the context to match the values in the data and retain
    ! stack registers. reset_context can GC.
    jit-save-context

    ! Resets the context. The top two ds items are preserved.
    vm-reg "reset_context" jit-call-1arg

    ! Switches to the same context I think.
    ctx-reg jit-switch-context

    ! Pops the quotation from the stack and puts it in arg1.
    pop-arg1

    ! Jump to quotation arg1
    jit-jump-quot ;

{
    { (set-context) [ jit-set-context ] }
    { (set-context-and-delete) [ jit-delete-current-context jit-set-context ] }
    { (start-context) [ jit-start-context ] }
    { (start-context-and-delete) [ jit-start-context-and-delete ] }
} define-sub-primitives

! Non-overflowing fixnum math
: jit-math ( insn -- )
    load1/0
    [ temp0 temp1 temp0 ] dip execute( arg2 arg1 dst -- )
    1 push-down0 ;

{
    { fixnum+fast [ \ ADDr jit-math ] }
    { fixnum-fast [ \ SUBr jit-math ] }
    { fixnum*fast [
        load1/0
        temp0 untag
        temp1 temp0 temp0 MUL
        1 push-down0
    ] }
} define-sub-primitives

! Overflowing fixnum math
: jit-overflow ( insn func -- )
    load-arg1/2
    jit-save-context
    [ [ arg2 arg1 temp0 ] dip call ] dip
    store0
    [ VC B.cond ] [
        vm-reg arg3 MOVr
        jit-call
    ] jit-conditional* ; inline

{
    { fixnum+ [ [ ADDSr ] "overflow_fixnum_add" jit-overflow ] }
    { fixnum- [ [ SUBSr ] "overflow_fixnum_subtract" jit-overflow ] }
    { fixnum* [
        load-arg1/2
        jit-save-context
        arg1 untag
        arg2 arg1 temp0 MUL
        store0
        arg2 arg1 temp1 SMULH
        63 temp0 temp0 ASRi
        temp0 temp1 CMPr
        [ EQ B.cond ] [
            arg2 untag
            vm-reg arg3 MOVr
            "overflow_fixnum_multiply" jit-call
        ] jit-conditional*
    ] }
} define-sub-primitives

! Division and modulo
: jit-fixnum-/mod ( -- )
    load1/0
    temp0 temp1 temp2 SDIV
    temp1 temp0 temp2 temp0 MSUB ;

{
    { fixnum-mod [
        jit-fixnum-/mod
        1 push-down0
    ] }
    { fixnum/i-fast [
        jit-fixnum-/mod
        tag-bits get temp2 temp0 LSLi
        1 push-down0
    ] }
    { fixnum/mod-fast [
        jit-fixnum-/mod
        temp2 tag*
        store2/0
    ] }
} define-sub-primitives

! Comparisons
: jit-compare ( cond -- )
    2 words temp3 LDRl
    3 words Br
    NOP NOP t rc-absolute-cell rel-literal
    \ f type-number temp2 MOVwi
    load1/0
    temp0 temp1 CMPr
    [ temp2 temp3 temp0 ] dip CSEL
    1 push-down0 ;

{
    { both-fixnums? [
        load1/0
        temp1 temp0 temp0 ORRr
        tag-mask get temp0 TSTi
        \ f type-number temp0 MOVwi
        1 tag-fixnum temp1 MOVwi
        temp0 temp1 temp0 EQ CSEL
        1 push-down0
    ] }

    { eq? [ EQ jit-compare ] }
    { fixnum> [ GT jit-compare ] }
    { fixnum>= [ GE jit-compare ] }
    { fixnum< [ LT jit-compare ] }
    { fixnum<= [ LE jit-compare ] }

    ! Bit manipulation
    { fixnum-bitand [ \ ANDr jit-math ] }
    { fixnum-bitnot [
        load0
        temp0 temp0 MVN
        tag-mask get temp0 temp0 EORi
        store0
    ] }
    { fixnum-bitor [ \ ORRr jit-math ] }
    { fixnum-bitxor [ \ EORr jit-math ] }
    { fixnum-shift-fast [
        load1/0
        temp0 untag
        temp1 temp2 MOVr
        temp0 temp1 temp1 LSLr
        temp0 temp0 NEG
        temp0 temp2 temp2 ASRr
        tag-mask get bitnot temp2 temp2 ANDi
        0 temp0 CMPi
        temp2 temp1 temp0 MI CSEL
        1 push-down0
    ] }

    ! Locals
    { drop-locals [
        pop0
        tagged>offset0
        temp0 rs-reg rs-reg SUBr
    ] }
    { get-local [
        load0
        tagged>offset0
        temp0 rs-reg temp0 LDRr
        store0
    ] }
    { load-local [ >r ] }

    ! Objects
    { slot [
        ! load object and slot number
        load1/0
        ! turn slot number into offset
        tagged>offset0
        ! mask off tag
        tag-mask get bitnot temp1 temp1 ANDi
        ! load slot value
        temp1 temp0 temp0 LDRr
        ! push to stack
        1 push-down0
    ] }

    { string-nth-fast [
        load1/0
        temp1 untag
        string-offset temp0 temp0 ADDi
        temp1 temp0 temp0 LDRBr
        temp0 tag*
        1 push-down0
    ] }

    { tag [
        load0
        tag-mask get temp0 temp0 ANDi
        temp0 tag*
        store0
    ] }

    ! Shufflers

    ! Drops
    { drop [ 1 ndrop ] }
    { 2drop [ 2 ndrop ] }
    { 3drop [ 3 ndrop ] }
    { 4drop [ 4 ndrop ] }

    ! Dups
    { dup [ load0 push0 ] }
    { 2dup [ load1/0 push1 push0 ] }
    { 3dup [ load2 load1/0 push2 push1 push0 ] }
    { 4dup [ load3/2 load1/0 push3 push2 push1 push0 ] }
    { dupd [ load1/0 store1 push0 ] }

    ! Misc shufflers
    { over [ load1 push1 ] }
    { pick [ load2 push2 ] }

    ! Nips
    { nip [ load0 1 push-down0 ] }
    { 2nip [ load0 2 push-down0 ] }

    ! Swaps
    { -rot [ pop0 load2/1* store0/2 push1 ] }
    { rot [ pop0 load2/1* store1/0 push2 ] }
    { swap [ load1/0 store0/1 ] }
    { swapd [ load2/1 store1/2 ] }

    { set-callstack [
        ! Load callstack object
        pop0
        ! Get ctx->callstack_bottom
        jit-load-context
        context-callstack-bottom-offset ctx-reg arg1 LDRuoff
        ! Get top of callstack object -- 'src' for memcpy
        callstack-top-offset temp0 arg2 ADDi
        ! Get callstack length, in bytes --- 'len' for memcpy
        callstack-length-offset temp0 arg3 LDUR
        tag-bits get arg3 arg3 LSRi
        ! Compute new stack pointer -- 'dst' for memcpy
        arg3 arg1 arg1 SUBr
        ! Install new stack pointer
        arg1 stack-reg MOVsp
        ! Call memcpy; arguments are now in the correct registers
        ! Create register shadow area for Win64
        32 stack-reg stack-reg SUBi
        "factor_memcpy" jit-call
        ! Tear down register shadow area
        32 stack-reg stack-reg ADDi
        ! Return with new callstack
        stack-frame-size stack-reg link-reg stack-frame-reg LDPpost
        f RET
    ] }
} define-sub-primitives

[ "bootstrap.arm.64" forget-vocab ] with-compilation-unit
