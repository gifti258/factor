! Copyright (C) 2020 Doug Coleman.
! Copyright (C) 2023 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: arrays bootstrap.image.private
compiler.codegen.relocation compiler.constants compiler.units
cpu.arm.64.assembler generic.single.private kernel
kernel.private layouts locals.backend make math math.private
namespaces sequences slots.private strings.private
threads.private vocabs ;
FROM: cpu.arm.64.assembler => B ;

IN: bootstrap.assembler.arm

8 \ cell set

: stack-frame-size ( -- n ) 8 bootstrap-cells ; inline

! X0-X17  volatile     scratch registers
! X0-X8                parameter registers
! X0                   result register
! X16-X17              intra-procedure-call registers
! X18-X29 non-volatile scratch registers
! X18                  platform register (TEB pointer under Windows)
! X29/FP               frame pointer
! X30/LR  non-volatile link register

ALIAS: arg1 X0
ALIAS: arg2 X1
ALIAS: arg3 X2

ALIAS: temp0 X9
ALIAS: temp0/32 W9
ALIAS: temp1 X10
ALIAS: temp2 X11
ALIAS: temp3 X12
ALIAS: PIC-TAIL X13

ALIAS: VM X28
ALIAS: DS X27
ALIAS: RS X26
ALIAS: CTX X25

! TODO i don't think we need to save LR
: BLR* ( reg -- )
    ! LR SP -16 [pre] STR
    BLR
    ! LR SP 16 [post] LDR
    ;

! Pseudo load and branch

! pseudo load and jump
: LDR=BR ( -- word class )
    temp0 2 LDR
    temp0 BR
    8 0 <array> % f rc-absolute-cell ;

! :: jit-conditional* ( test-quot false-quot -- )
!     [ false-quot call ] B{ } make
!     [ length 4 / 1 + test-quot call ] [ % ] bi ; inline

: jit-conditional* ( test-quot false-quot -- )
    [ '[ 4 / 1 + @ ] ] dip jit-conditional ; inline

! pseudo load and call
: LDR=BLR ( -- word class )
    temp0 3 LDR
    temp0 BLR*
    [ B ]
    [ 8 0 <array> % f rc-absolute-cell ] jit-conditional* ;

! TODO only used for verification labeling!
: B-BRK ( uimm16 -- ) [ B ] [ BRK ] jit-conditional* ;

! Contexts

! Retrieves the addresses of the datastack and retainstack tops
! from the corresponding fields in the ctx struct.
! CTX must already have been loaded.
: jit-restore-context ( -- )
    0xcc00 B-BRK
    DS CTX context-datastack-offset [+] LDR
    RS CTX context-retainstack-offset [+] LDR ;

: jit-switch-context ( reg -- )
    0xcc01 B-BRK
    ! ! Push a bogus return address so the GC can track this frame back
    ! ! to the owner
    ! 0 CALL
    0 BL ! ?!

    ! ! Make the new context the current one
    ! CTX swap MOV
    ! VM vm-context-offset [+] CTX MOV
    CTX swap MOV
    CTX VM vm-context-offset [+] STR

    ! ! Load new stack pointer
    ! RSP CTX context-callstack-top-offset [+] MOV
    temp0 CTX context-callstack-top-offset [+] LDR
    SP temp0 MOV

    ! ! Load new ds, rs registers
    jit-restore-context

    CTX jit-update-tib ;

! Loads the address of the ctx struct into CTX.
: jit-load-context ( -- )
    0xcc02 B-BRK
    CTX VM vm-context-offset [+] LDR ;

! Saves the addresses of the callstack, datastack, and retainstack tops
! into the corresponding fields in the ctx struct.
: jit-save-context ( -- )
    0xcc03 B-BRK
    jit-load-context
    ! The reason for -8 I think is because we are anticipating a CALL
    ! instruction. After the call instruction, the contexts frame_top
    ! will point to the origin jump address.
    temp0 SP MOV
    temp0 dup 16 SUB
    temp0 CTX context-callstack-top-offset [+] STR
    DS CTX context-datastack-offset [+] STR
    RS CTX context-retainstack-offset [+] STR ;

: jit-pop-context-and-param ( -- )
    0xcc04 B-BRK
    arg1 DS -8 [post] LDR
    arg1 arg1 alien-offset ADD
    arg1 arg1 [] LDR
    arg2 DS -8 [post] LDR ;

: jit-set-context ( -- )
    0xcc05 B-BRK
    jit-pop-context-and-param
    jit-save-context
    arg1 jit-switch-context
    SP dup 16 ADD
    arg2 DS 8 [pre] STR ;

: jit-start-context ( -- )
    0xcc06 B-BRK
    ! Create the new context in arg1. Have to save context
    ! twice, first before calling new_context() which may GC,
    ! and again after popping the two parameters from the stack.
    jit-save-context
    arg1 VM MOV
    "new_context" LDR=BLR rel-dlsym

    arg1 DS -8 [post] LDR
    arg2 DS -8 [post] LDR
    jit-save-context
    arg1 jit-switch-context
    arg2 DS 8 [pre] STR
    temp0 arg1 quot-entry-point-offset [+] LDR
    temp0 BR ;

: jit-delete-current-context ( -- )
    0xcc07 B-BRK
    arg1 VM MOV
    "delete_context" LDR=BLR rel-dlsym ;

! Resets the active context and instead the passed in quotation
! becomes the new code that it executes.
: jit-start-context-and-delete ( -- )
    0xcc08 B-BRK
    ! Updates the context to match the values in the data and retain
    ! stack registers. reset_context can GC.
    jit-save-context

    ! Resets the context. The top two ds items are preserved.
    arg1 VM MOV
    "reset_context" LDR=BLR rel-dlsym

    ! Switches to the same context I think.
    CTX jit-switch-context

    ! Pops the quotation from the stack and puts it in arg1.
    arg1 DS -8 [post] LDR

    ! Jump to quotation arg1
    temp0 arg1 quot-entry-point-offset [+] LDR
    temp0 BR ;

{
    { (set-context) [
        0xcc10 BRK
        jit-set-context
    ] }
    { (set-context-and-delete) [
        0xcc11 BRK
        jit-delete-current-context
        jit-set-context
    ] }
    { (start-context) [
        0xcc12 BRK
        jit-start-context
    ] }
    { (start-context-and-delete) [
        0xcc13 BRK
        jit-start-context-and-delete
    ] }
} define-sub-primitives

! Quotation compilation

! https://elixir.bootlin.com/linux/latest/source/arch/arm64/kernel/stacktrace.c#L22
! Perform setup for a quotation
[
    0x17 B-BRK
    ! make room for LR plus magic number of callback, 16byte align
    SP dup stack-frame-size SUB
    LR SP -16 [pre] STR
] JIT-PROLOG jit-define

[
    0x19 B-BRK
    ! CTX is preserved across the call because it is non-volatile
    ! in the C ABI
    jit-save-context
    ! call the primitive
    arg1 VM MOV
    f LDR=BLR rel-dlsym
    jit-restore-context
] JIT-PRIMITIVE jit-define

! This is used when a word is called at the end of a quotation.
! JIT-WORD-CALL is used for other word calls.
[
    0x1a B-BRK
    [ 4 * PIC-TAIL swap ADR ]
    [ LDR=BR rel-word-pic-tail ] jit-conditional*
] JIT-WORD-JUMP jit-define

! This is used when a word is called.
! JIT-WORD-JUMP is used if the word is the last piece of code in a quotation.
[
    0x1b B-BRK
    LDR=BLR rel-word-pic
] JIT-WORD-CALL jit-define

! if-statement control flow
[
    0x1d B-BRK
    temp0 DS -8 [post] LDR
    temp0 \ f type-number CMP
    [ BEQ ]
    [ LDR=BR rel-word ] jit-conditional*
    LDR=BR rel-word
] JIT-IF jit-define

[
    0x1e B-BRK
    temp0 LDR= rc-absolute-cell rel-safepoint
    temp0 temp0 [] STR
] JIT-SAFEPOINT jit-define

! Perform teardown for a quotation
[
    0x1f B-BRK
    LR SP 16 [post] LDR
    SP dup stack-frame-size ADD
] JIT-EPILOG jit-define

! Return to the outer stack frame
[
    0x20 B-BRK
    RET
] JIT-RETURN jit-define

! Push a literal value to the stack
[
    0x22 B-BRK
    temp0 LDR= f rc-absolute-cell rel-literal
    temp0 DS 8 [pre] STR
] JIT-PUSH-LITERAL jit-define

: >r ( -- )
    temp0 DS -8 [post] LDR
    temp0 RS 8 [pre] STR ;

: r> ( -- )
    temp0 RS -8 [post] LDR
    temp0 DS 8 [pre] STR ;

[
    0x24 B-BRK
    >r
    LDR=BLR rel-word
    r>
] JIT-DIP jit-define

[
    0x26 B-BRK
    >r >r
    LDR=BLR rel-word
    r> r>
] JIT-2DIP jit-define

[
    0x28 B-BRK
    >r >r >r
    LDR=BLR rel-word
    r> r> r>
] JIT-3DIP jit-define

[
    0x2910 B-BRK
    temp0 DS -8 [post] LDR
    temp0 dup quot-entry-point-offset [+] LDR
]
[ 0x2911 B-BRK temp0 BLR* ]
[ 0x2912 B-BRK temp0 BR ]
\ (call) define-combinator-primitive

[
    0x2920 B-BRK
    temp0 DS -8 [post] LDR
    temp0 dup word-entry-point-offset [+] LDR
]
[ 0x2921 B-BRK temp0 BLR* ]
[ 0x2922 B-BRK temp0 BR ]
\ (execute) define-combinator-primitive

[
    0x29 BRK
    temp0 DS -8 [post] LDR
    temp0 dup word-entry-point-offset ADD
    temp0 BR
] JIT-EXECUTE jit-define

[
    0x2b B-BRK
    arg2 arg1 MOV
    arg1 VM MOV
    "begin_callback" LDR=BLR rel-dlsym

    0x2b01 B-BRK

    ! Call lazy-jit-compile
    temp0 arg1 quot-entry-point-offset [+] LDR
    temp0 BLR*

    0x2b02 B-BRK

    arg1 VM MOV
    "end_callback" LDR=BLR rel-dlsym
] \ c-to-factor define-sub-primitive

! External entry points

[
    0x2c00 B-BRK
    jit-save-context
    arg2 VM MOV
    "lazy_jit_compile" LDR=BLR rel-dlsym
    temp0 arg1 quot-entry-point-offset [+] LDR
]
[ 0x2c01 B-BRK temp0 BLR* ]
! Jump to boot quot
[ 0x2c02 BRK temp0 BR ]
\ lazy-jit-compile define-combinator-primitive

{
    { unwind-native-frames [
        0x2d BRK
        ! unwind-native-frames is marked as "special" in
        ! vm/quotations.cpp so it does not have a standard
        ! prolog.

        ! Unwind stack frames
        SP arg2 MOV

        ! Load VM pointer into VM register, since we're entering
        ! from C code
        VM LDR= 0 rc-absolute-cell rel-vm

        ! Load ds and rs registers
        jit-load-context
        jit-restore-context

        ! Clear the fault flag
        XZR VM vm-fault-flag-offset [+] STR

        ! Call quotation
        temp0 arg1 quot-entry-point-offset [+] LDR
        temp0 BR
    ] }
    ! Because Aarch64 can reset the FP status register without
    ! touching the control register, we don't have to return the
    ! contents of the control register just to restore it in
    ! set-fpu-state.
    { fpu-state [
        0x2e BRK
    ] }
    ! Clear FP exception bits
    { set-fpu-state [
        0x2f BRK
        FPSR XZR MSR
    ] }
} define-sub-primitives

! The *-signal-handler subprimitives are special-cased in
! vm/quotations.cpp to not trigger generation of a stack frame,
! so they can perform their own prolog/epilog, preserving
! registers.
!
! TODO
! It is important that the total is 192/64 and that it matches
! the constants in vm/cpu-x86.*.hpp
: jit-signal-handler-prolog ( -- )
    X0 X1 SP -16 [pre] STP
    X2 X3 SP -16 [pre] STP
    X4 X5 SP -16 [pre] STP
    X6 X7 SP -16 [pre] STP
    X8 X9 SP -16 [pre] STP
    X10 X11 SP -16 [pre] STP
    X12 X13 SP -16 [pre] STP
    X14 X15 SP -16 [pre] STP
    X16 X17 SP -16 [pre] STP
    X18 X19 SP -16 [pre] STP
    X20 X21 SP -16 [pre] STP
    X22 X23 SP -16 [pre] STP
    X24 X25 SP -16 [pre] STP
    X26 X27 SP -16 [pre] STP
    X28 X29 SP -16 [pre] STP
    X0 NZCV MRS
    X30 X0 SP -16 [pre] STP

    ! Register parameter area 32 bytes, unused on platforms
    ! other than windows 64 bit, but including it doesn't hurt.
    SP dup 4 bootstrap-cells SUB ;

: jit-signal-handler-epilog ( -- )
    ! SP SP 7 bootstrap-cells [+] LEA
    ! POPF
    ! signal-handler-save-regs reverse [ POP ] each ;
    SP dup 4 bootstrap-cells ADD
    X30 X0 SP 16 [post] LDP
    NZCV X0 MSR
    X28 X29 SP 16 [post] LDP
    X26 X27 SP 16 [post] LDP
    X24 X25 SP 16 [post] LDP
    X22 X23 SP 16 [post] LDP
    X20 X21 SP 16 [post] LDP
    X18 X19 SP 16 [post] LDP
    X16 X17 SP 16 [post] LDP
    X14 X15 SP 16 [post] LDP
    X12 X13 SP 16 [post] LDP
    X10 X11 SP 16 [post] LDP
    X8 X9 SP 16 [post] LDP
    X6 X7 SP 16 [post] LDP
    X4 X6 SP 16 [post] LDP
    X2 X3 SP 16 [post] LDP
    X0 X1 SP 16 [post] LDP ;

{
    { signal-handler [
        0x30 BRK
        jit-signal-handler-prolog
        jit-save-context
        temp0 VM vm-signal-handler-addr-offset [+] LDR
        temp0 BLR*
        jit-signal-handler-epilog
        RET
    ] }
    { leaf-signal-handler [
        0x31 BRK
        jit-signal-handler-prolog
        jit-save-context
        temp0 VM vm-signal-handler-addr-offset [+] LDR
        temp0 BLR*
        jit-signal-handler-epilog
        ! Pop the fake leaf frame
        SP dup leaf-stack-frame-size bootstrap-cell - ADD
        RET
    ] }
} define-sub-primitives

! C to Factor entry point
! Set up and execute the boot quot, then perform a teardown and return to C++
[
    ! Save all non-volatile registers
    X18 X19 SP -16 [pre] STP
    X20 X21 SP -16 [pre] STP
    X22 X23 SP -16 [pre] STP
    X24 X25 SP -16 [pre] STP
    X26 X27 SP -16 [pre] STP
    X28 X29 SP -16 [pre] STP
    ! Leave room for old context
    X30     SP -16 [pre] STR
    FP SP MOV

    jit-save-tib

    ! Load VM
    VM LDR= 0 rc-absolute-cell rel-vm

    ! Save old context
    CTX VM vm-context-offset [+] LDR
    CTX SP 8 [+] STR

    ! Switch over to the spare context
    CTX VM vm-spare-context-offset [+] LDR
    CTX VM vm-context-offset [+] STR

    ! Save C callstack pointer
    temp0 SP MOV
    temp0 CTX context-callstack-save-offset [+] STR

    ! Load Factor stack pointers
    temp0 CTX context-callstack-bottom-offset [+] LDR
    SP temp0 MOV

    CTX jit-update-tib
    jit-install-seh

    RS CTX context-retainstack-offset [+] LDR
    DS CTX context-datastack-offset [+] LDR

    0x3501 BRK

    ! Call c-to-factor
    LDR=BLR rel-word

    0x3502 B-BRK

    ! Load C callstack pointer
    CTX VM vm-context-offset [+] LDR

    temp0 CTX context-callstack-save-offset [+] LDR
    SP temp0 MOV

    ! Load old context
    CTX SP 8 [+] LDR
    CTX VM vm-context-offset [+] STR

    jit-restore-tib

    ! Restore non-volatile registers
    X30     SP 16 [post] LDR
    X28 X29 SP 16 [post] LDP
    X26 X27 SP 16 [post] LDP
    X24 X25 SP 16 [post] LDP
    X22 X23 SP 16 [post] LDP
    X20 X21 SP 16 [post] LDP
    X18 X19 SP 16 [post] LDP

    RET
] CALLBACK-STUB jit-define

! Polymorphic inline caches

[
    0x36 B-BRK
    temp0 DS [] LDR f rc-absolute-arm64-ldr rel-untagged
] PIC-LOAD jit-define

[
    0x37 B-BRK
    temp1 temp0 tag-mask get AND
] PIC-TAG jit-define

[
    0x38 B-BRK
    temp1 temp0 tag-mask get AND
    temp1 tuple type-number CMP
    [ BNE ]
    [ temp1 temp0 tuple-class-offset [+] LDR ] jit-conditional*
] PIC-TUPLE jit-define

[
    0x39 B-BRK
    temp1 0 CMP f rc-absolute-arm64-cmp rel-untagged
] PIC-CHECK-TAG jit-define

[
    0x3a B-BRK
    temp0 LDR= f rc-absolute-cell rel-literal
    temp0 temp1 CMP
] PIC-CHECK-TUPLE jit-define

[
    0x3b B-BRK
    [ BNE ]
    [ LDR=BR rel-word ] jit-conditional*
] PIC-HIT jit-define

! Inline cache miss entry points

: jit-load-return-address ( -- )
    PIC-TAIL SP stack-frame-size bootstrap-cell - [+] LDR ;

! These are always in tail position with an existing stack
! frame, and the stack. The frame setup takes this into account.
: jit-inline-cache-miss ( -- )
    0x3d00 B-BRK
    jit-save-context
    arg1 PIC-TAIL MOV
    arg2 VM MOV
    ! Call factor`inline_cache_miss
    LDR=BLR nip rel-inline-cache-miss
    jit-load-context
    jit-restore-context ;

[
    0x3c B-BRK
    jit-load-return-address
    jit-inline-cache-miss
]
[ temp0 BLR* ]
[ temp0 BR ]
\ inline-cache-miss define-combinator-primitive

[
    0x3d B-BRK
    jit-inline-cache-miss
]
[ temp0 BLR* ]
[ temp0 BR ]
\ inline-cache-miss-tail define-combinator-primitive

! Megamorphic caches

[
    0x3e B-BRK
    ! class = tag(object)
    temp1 temp0 tag-bits get dup UBFIZ
    temp1 tuple type-number tag-fixnum CMP
    [ BNE ]
    [ temp1 temp0 tuple-class-offset [+] LDR ] jit-conditional*
    ! cache = <relocation magic>
    temp0 LDR= f rc-absolute-cell rel-literal
    ! key = class & (cache.length - 1)
    temp2 temp0 mega-cache-size get 1 - bootstrap-cells AND
    ! cache += array-start-offset
    temp0 dup array-start-offset ADD
    ! cache += key
    temp0 dup temp2 ADD
    ! *cache == class
    temp2 temp1 [] LDR
    temp2 temp0 CMP
    [ BNE ]
    [
        ! megamorphic-cache-hits++
        temp2 LDR= rc-absolute-cell rel-megamorphic-cache-hits
        temp1 temp2 [] LDR
        temp1 dup 1 ADD
        temp1 temp2 [] STR
        ! goto cache[bootstrap-cell] + word-entry-point-offset
        temp0 dup bootstrap-cell [+] LDR
        temp0 dup word-entry-point-offset ADD
        temp0 BR
    ] jit-conditional*
] MEGA-LOOKUP jit-define

! Math

! Fixnum arithmetic
{
    { fixnum+fast [
        0x100 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 temp0 ADD
        temp0 DS -8 [pre] STR
    ] }
    { fixnum-fast [
        0x101 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 temp0 SUB
        temp0 DS -8 [pre] STR
    ] }
    { fixnum*fast [
        0x102 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 dup tag-bits get ASR
        temp0 temp0 temp1 MUL
        temp0 DS -8 [pre] STR
    ] }
} define-sub-primitives

! Overflowing fixnum arithmetic
{
    { fixnum+ [
        0x110 B-BRK
        arg1 arg2 DS -8 [pre] LDP
        jit-save-context
        temp0 arg1 arg2 ADDS
        temp0 DS [] STR
        [ BVC ]
        [
            arg3 VM MOV
            "overflow_fixnum_add" LDR=BLR rel-dlsym
        ] jit-conditional*
    ] }
    { fixnum- [
        0x111 B-BRK
        arg1 arg2 DS -8 [pre] LDP
        jit-save-context
        temp0 arg1 arg2 SUBS
        temp0 DS [] STR
        [ BVC ]
        [
            arg3 VM MOV
            "overflow_fixnum_subtract" LDR=BLR rel-dlsym
        ] jit-conditional*
    ] }
    { fixnum* [
        0x112 B-BRK
        arg1 arg2 DS -8 [pre] LDP
        jit-save-context
        arg1 dup tag-bits get ASR
        temp0 arg1 arg2 MUL
        temp0 DS [] STR
        temp1 arg1 arg2 SMULH
        temp1 temp0 63 <ASR> CMP
        [ BEQ ]
        [
            arg3 VM MOV
            "overflow_fixnum_multiply" LDR=BLR rel-dlsym
        ] jit-conditional*
    ] }
} define-sub-primitives

! Comparisons
: jit-compare ( cond -- )
    temp1 temp0 DS -8 [+] LDP
    temp2 LDR= t rc-absolute-cell rel-literal
    temp3 \ f type-number MOV
    temp1 temp0 CMP
    [ temp0 temp2 temp3 ] dip CSEL
    temp0 DS -8 [pre] STR ;

{
    { both-fixnums? [
        0x120 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp0 temp1 ORR
        temp0 tag-mask get TST
        temp0 1 tag-fixnum MOV
        temp1 \ f type-number MOV
        temp0 temp0 temp1 EQ CSEL
        temp0 DS -8 [pre] STR
    ] }
    {     eq?  [ 0x121 B-BRK EQ jit-compare ] }
    { fixnum>  [ 0x122 B-BRK GT jit-compare ] }
    { fixnum>= [ 0x123 B-BRK GE jit-compare ] }
    { fixnum<  [ 0x124 B-BRK LT jit-compare ] }
    { fixnum<= [ 0x125 B-BRK LE jit-compare ] }
} define-sub-primitives

! Modular arithmetic
{
    { fixnum/i-fast [
        0x130 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 temp0 SDIV
        temp0 dup tag-bits get LSL
        temp0 DS -8 [pre] STR
    ] }
    { fixnum-mod [
        0x131 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp2 temp1 temp0 SDIV
        temp0 dup temp2 temp1 MSUB
        temp0 DS -8 [pre] STR
    ] }
    { fixnum/mod-fast [
        0x132 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp2 temp1 temp0 SDIV
        temp0 dup temp2 temp1 MSUB
        temp2 dup tag-bits get LSL
        temp2 temp0 DS -8 [+] STP
    ] }
} define-sub-primitives

! Bitwise arithmetic
{
    { fixnum-bitand [
        0x140 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 temp0 AND
        temp0 DS -8 [pre] STR
    ] }
    { fixnum-bitnot [
        0x141 B-BRK
        temp0 DS [] LDR
        temp0 temp0 tag-mask get bitnot EOR
        temp0 DS [] STR
    ] }
    { fixnum-bitor [
        0x142 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 temp0 ORR
        temp0 DS -8 [pre] STR
    ] }
    { fixnum-bitxor [
        0x143 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 temp0 EOR
        temp0 DS -8 [pre] STR
    ] }
    { fixnum-shift-fast [
        0x144 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 dup tag-bits get ASR
        temp2 temp1 temp0 LSL
        temp0 temp0 NEG
        temp1 temp1 temp0 ASR
        temp1 dup tag-mask get bitnot AND
        temp0 0 CMP
        temp0 temp1 temp2 PL CSEL
        temp0 DS -8 [pre] STR
    ] }
} define-sub-primitives

! Locals
{
    { drop-locals [
        0x200 B-BRK
        temp0 DS -8 [post] LDR
        RS dup temp0 tag-bits get 3 - <ASR> SUB
    ] }
    { get-local [
        0x201 B-BRK
        temp0 DS [] LDR
        temp0 dup tag-bits get 3 - ASR
        temp0 RS temp0 [+] LDR
        temp0 DS [] STR
    ] }
    { load-local [
        0x202 B-BRK
        >r
    ] }
} define-sub-primitives

! Objects
{
    { slot [
        0x300 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 dup tag-bits get 3 - ASR
        temp1 dup tag-mask get bitnot AND
        temp0 temp1 temp0 [+] LDR
        temp0 DS -8 [pre] STR
    ] }
    { string-nth-fast [
        0x301 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp1 dup tag-bits get ASR
        temp0 dup string-offset ADD
        temp0/32 temp0 temp1 [+] LDRB
        temp0 dup tag-bits get LSL
        temp0 DS -8 [pre] STR
    ] }
    { tag [
        0x302 B-BRK
        temp0 DS [] LDR
        temp0 dup tag-bits get dup UBFIZ
        temp0 DS [] STR
    ] }
} define-sub-primitives

! Shuffle words
{
    ! Drops
    {  drop [
        0x400 B-BRK
        DS dup  8 SUB
    ] }
    { 2drop [
        0x401 B-BRK
        DS dup 16 SUB
    ] }
    { 3drop [
        0x402 B-BRK
        DS dup 24 SUB
    ] }
    { 4drop [
        0x403 B-BRK
        DS dup 32 SUB
    ] }

    ! Dups
    {  dup [
        0x410 B-BRK
        temp0 DS [] LDR
        temp0 DS 8 [pre] STR
    ] }
    { 2dup [
        0x411 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp1 DS 8 [pre] STR
        temp0 DS 8 [pre] STR
    ] }
    { 3dup [
        0x412 B-BRK
        temp2 temp1 DS -16 [+] LDP
        temp0 DS [] LDR
        temp2 temp1 DS 8 [pre] STP
        temp0 DS 16 [pre] STR
    ] }
    { 4dup [
        0x413 B-BRK
        temp3 temp2 DS -24 [+] LDP
        temp1 temp0 DS -8 [+] LDP
        temp3 temp2 DS 8 [pre] STP
        temp1 DS 16 [pre] STR
        temp0 DS 8 [pre] STR
    ] }
    { dupd [
        0x414 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp1 DS [] STR
        temp0 DS 8 [pre] STR
    ] }

    ! Misc shuffle words
    { over [
        0x420 B-BRK
        temp1 DS -8 [+] LDR
        temp1 DS 8 [pre] STR
    ] }
    { pick [
        0x421 B-BRK
        temp2 DS -16 [+] LDR
        temp2 DS 8 [pre] STR
    ] }

    ! Nips
    { nip [
        0x430 B-BRK
        temp0 DS [] LDR
        temp0 DS -8 [pre] STR
    ] }
    { 2nip [
        0x431 B-BRK
        temp0 DS [] LDR
        temp0 DS -16 [pre] STR
    ] }

    ! Swaps
    { -rot [
        0x440 B-BRK
        temp2 temp1 DS -16 [+] LDP
        temp0 DS [] LDR
        temp0 temp2 DS -16 [+] STP
        temp1 DS [] STR
    ] }
    { rot [
        0x441 B-BRK
        temp2 temp1 DS -16 [+] LDP
        temp0 DS [] LDR
        temp1 temp0 DS -16 [+] STP
        temp2 DS [] STR
    ] }
    { swap [
        0x442 B-BRK
        temp1 temp0 DS -8 [+] LDP
        temp0 temp1 DS -8 [+] STP
    ] }
    { swapd [
        0x443 B-BRK
        temp2 temp1 DS -16 [+] LDP
        temp1 temp2 DS -16 [+] STP
    ] }
} define-sub-primitives

[
    0x500 BRK
    temp0 DS -8 [post] LDR
    jit-load-context
    arg1 CTX context-callstack-bottom-offset [+] LDR
    arg2 temp0 callstack-top-offset ADD
    arg3 temp0 callstack-length-offset [+] LDR
    arg1 dup arg3 tag-bits get <LSR> SUB
    SP arg1 MOV
    SP dup 32 SUB
    "factor_memcpy" LDR=BLR rel-dlsym
    SP dup 32 ADD
    RET
] \ set-callstack define-sub-primitive

[ "bootstrap.assembler.arm" forget-vocab ] with-compilation-unit
