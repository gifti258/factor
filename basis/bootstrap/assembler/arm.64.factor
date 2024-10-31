! Copyright (C) 2020 Doug Coleman.
! Copyright (C) 2023 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: bootstrap.image.private compiler.codegen.relocation
compiler.constants compiler.units cpu.arm.64.assembler
generic.single.private kernel kernel.private layouts
locals.backend math math.private namespaces slots.private
strings.private threads.private vocabs ;
IN: bootstrap.assembler.arm

big-endian off

8 \ cell set
: stack-frame-size ( -- n ) 8 bootstrap-cells ; inline

[
    0x17 B-BRK
    FP LR SP stack-frame-size neg [pre] STP
    FP SP MOV
] JIT-PROLOG jit-define

: jit-save-context ( -- )
    0xc4 B-BRK
    ! The reason for -16 I think is because we are anticipating a CALL
    ! instruction. After the call instruction, the contexts frame_top
    ! will point to the origin jump address.
    temp SP MOV
    ! temp SP 16 SUB
    temp CTX context-callstack-top-offset [+] STR
    DS CTX context-datastack-offset [+] STR
    RS CTX context-retainstack-offset [+] STR ;

: jit-restore-context ( -- )
    0xc2 B-BRK
    DS CTX context-datastack-offset [+] LDR
    RS CTX context-retainstack-offset [+] LDR ;

[
    0x19 B-BRK
    jit-save-context
    0xc1 B-BRK
    arg1 VM MOV
    f LDR=BLR rel-dlsym
    jit-restore-context
] JIT-PRIMITIVE jit-define

[
    0x1a B-BRK
    [ PIC-TAIL swap ADR ] [
        LDR=BR rel-word-pic-tail
    ] jit-conditional*
] JIT-WORD-JUMP jit-define

[
    0x1b B-BRK
    LDR=BLR rel-word-pic
] JIT-WORD-CALL jit-define

[
    0x1d B-BRK
    ds-0 DS -8 [post] LDR
    ds-0 \ f type-number CMP
    ! skip over true branch if equal
    [ BEQ ] [
        ! jump to true branch
        LDR=BR rel-word
    ] jit-conditional*
    ! jump to false branch
    LDR=BR rel-word
] JIT-IF jit-define

[
    0x1e B-BRK
    SAFEPOINT dup [] STR
] JIT-SAFEPOINT jit-define

[
    0x1f B-BRK
    FP LR SP stack-frame-size [post] LDP
] JIT-EPILOG jit-define

[
    0x20 B-BRK
    RET
] JIT-RETURN jit-define

[
    0x22 B-BRK
    ds-0 LDR= rel-literal
    0xc1 B-BRK
    ds-0 DS 8 [pre] STR
] JIT-PUSH-LITERAL jit-define

: >r ( -- )
    0xc2 B-BRK
    ds-0 DS -8 [post] LDR
    ds-0 RS 8 [pre] STR ;

: r> ( -- )
    0xc2 B-BRK
    ds-0 RS -8 [post] LDR
    ds-0 DS 8 [pre] STR ;

[
    0x24 B-BRK
    >r
    0xc4 B-BRK
    LDR=BLR rel-word
    r>
] JIT-DIP jit-define

[
    0x26 B-BRK
    >r >r
    0xc4 B-BRK
    LDR=BLR rel-word
    r> r>
] JIT-2DIP jit-define

[
    0x28 B-BRK
    >r >r >r
    0xc4 B-BRK
    LDR=BLR rel-word
    r> r> r>
] JIT-3DIP jit-define

[
    0x2910 B-BRK
    ! arg1 is a surprise tool that will be important later
    arg1 DS -8 [post] LDR
    temp arg1 quot-entry-point-offset [+] LDR
]
[ 0x2911 B-BRK temp BLR ]
[ 0x2912 B-BRK temp BR ]
\ (call) define-combinator-primitive

[
    0x2920 B-BRK
    temp DS -8 [post] LDR
    temp dup word-entry-point-offset [+] LDR
]
[ 0x2921 B-BRK temp BLR ]
[ 0x2922 B-BRK temp BR ]
\ (execute) define-combinator-primitive

[
    0x29 B-BRK
    temp DS -8 [post] LDR
    temp dup word-entry-point-offset [+] LDR
    temp BR
] JIT-EXECUTE jit-define

[
    0x2b B-BRK
    arg2 arg1 MOV
    arg1 VM MOV
    "begin_callback" LDR=BLR rel-dlsym

    0xc2 B-BRK
    temp RETURN quot-entry-point-offset [+] LDR
    temp BLR

    0xc1 B-BRK
    arg1 VM MOV
    "end_callback" LDR=BLR rel-dlsym
] \ c-to-factor define-sub-primitive

[
    0x2c00 B-BRK
    jit-save-context
    0xc1 B-BRK
    arg2 VM MOV
    "lazy_jit_compile" LDR=BLR rel-dlsym
    0xc1 B-BRK
    temp RETURN quot-entry-point-offset [+] LDR
]
[ 0x2c01 B-BRK temp BLR ]
[ 0x2c02 B-BRK temp BR ]
\ lazy-jit-compile define-combinator-primitive

{
    { unwind-native-frames [
        SP arg2 MOV
        VM LDR= rel-vm
        jit-restore-context
        XZR VM vm-fault-flag-offset [+] STR
        temp arg1 quot-entry-point-offset [+] LDR
        temp BR
    ] }
    { fpu-state [ FPSR XZR MSR ] }
    { set-fpu-state [ ] }
} define-sub-primitives

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
    SP dup 4 bootstrap-cells SUB ;

: jit-signal-handler-epilog ( -- )
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
        jit-signal-handler-prolog
        jit-save-context
        temp VM vm-signal-handler-addr-offset [+] LDR
        temp BLR
        jit-signal-handler-epilog
        FP LR SP 16 [post] LDP
        RET
    ] }
    { leaf-signal-handler [
        jit-signal-handler-prolog
        jit-save-context
        temp VM vm-signal-handler-addr-offset [+] LDR
        temp BLR
        jit-signal-handler-epilog
        FP LR SP leaf-stack-frame-size [post] LDP
        RET
    ] }
} define-sub-primitives
! C to Factor entry point
[
    ! Save all non-volatile registers
    X18 X19 SP -16 [pre] STP
    X20 X21 SP -16 [pre] STP
    X22 X23 SP -16 [pre] STP
    X24 X25 SP -16 [pre] STP
    X26 X27 SP -16 [pre] STP
    X28 X29 SP -16 [pre] STP
    X30     SP -16 [pre] STR
    FP SP MOV

    jit-save-teb

    VM LDR= rel-vm
    SAFEPOINT (LDR=) rel-safepoint
    MEGA-HITS (LDR=) rel-megamorphic-cache-hits
    CACHE-MISS (LDR=) rel-inline-cache-miss
    CARDS-OFFSET (LDR=) rel-cards-offset
    DECKS-OFFSET (LDR=) rel-decks-offset

    ! Save old context
    CTX VM vm-context-offset [+] LDR
    CTX SP 8 [+] STR

    ! Switch over to the spare context
    CTX VM vm-spare-context-offset [+] LDR
    CTX VM vm-context-offset [+] STR

    ! Save C callstack pointer
    temp SP MOV
    temp CTX context-callstack-save-offset [+] STR

    ! Load Factor stack pointers
    temp CTX context-callstack-bottom-offset [+] LDR
    SP temp MOV

    jit-update-teb

    RS CTX context-retainstack-offset [+] LDR
    DS CTX context-datastack-offset [+] LDR

    ! Call into Factor code
    LDR=BLR rel-word

    ! Load C callstack pointer
    CTX VM vm-context-offset [+] LDR

    temp CTX context-callstack-save-offset [+] LDR
    SP temp MOV

    ! Load old context
    CTX SP 8 [+] LDR
    CTX VM vm-context-offset [+] STR

    jit-restore-teb

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
    obj DS [] LDR f rc-absolute-arm-ldr rel-untagged
] PIC-LOAD jit-define

[
    0x37 B-BRK
    type obj tag-mask get ANDS
] PIC-TAG jit-define

[
    0x38 B-BRK
    type obj tag-mask get AND
    type tuple type-number CMP
    [ BNE ] [
        0xc1 B-BRK
        type obj tuple-class-offset [+] LDR
    ] jit-conditional*
] PIC-TUPLE jit-define

[
    0x39 B-BRK
    type 0 CMP f rc-absolute-arm-cmp rel-untagged
] PIC-CHECK-TAG jit-define

[
    0x3a B-BRK
    temp LDR= rel-literal
    0xc1 B-BRK
    type temp CMP
] PIC-CHECK-TUPLE jit-define

[
    0x3b B-BRK
    [ BNE ] [
        LDR=BR rel-word
    ] jit-conditional*
] PIC-HIT jit-define

: jit-load-return-address ( -- )
    0xc2 B-BRK
    PIC-TAIL SP 8 [+] LDR
    PIC-TAIL dup 5 insns ADD ;

: jit-inline-cache-miss ( -- )
    jit-save-context
    0xc2 B-BRK
    arg1 PIC-TAIL MOV
    arg2 VM MOV
    0xc0 B-BRK
    CACHE-MISS BLR
    jit-restore-context ;

[ 0x3c00 B-BRK jit-load-return-address jit-inline-cache-miss ]
[ 0x3c01 B-BRK RETURN BLR ]
[ 0x3c02 B-BRK RETURN BR ]
\ inline-cache-miss define-combinator-primitive

[ 0x3d00 B-BRK jit-inline-cache-miss ]
[ 0x3d01 B-BRK RETURN BLR ]
[ 0x3d02 B-BRK RETURN BR ]
\ inline-cache-miss-tail define-combinator-primitive

! Megamorphic caches

[
    0x3e B-BRK
    ! class = ...
    type obj tag-bits get dup UBFIZ
    type tuple type-number tag-fixnum CMP
    [ BNE ] [
        0xc1 B-BRK
        type obj tuple-class-offset [+] LDR
    ] jit-conditional*
    ! cache = ...
    cache LDR= rel-literal
    0xc5 B-BRK
    ! key = hashcode(class) & mask
    temp type mega-cache-size get 1 - bootstrap-cells AND
    ! cache += key
    cache dup temp ADD
    ! if(get(cache) == class)
    temp cache array-start-offset [+] LDR
    type temp CMP
    [ BNE ] [
        0xc6 B-BRK
        ! megamorphic_cache_hits++
        temp MEGA-HITS [] LDR
        temp dup 1 ADD
        temp MEGA-HITS [] STR
        ! goto get(cache + bootstrap-cell)
        temp cache array-start-offset bootstrap-cell + [+] LDR
        temp dup word-entry-point-offset [+] LDR
        temp BR
        ! fall-through on miss
    ] jit-conditional*
] MEGA-LOOKUP jit-define

! Contexts
: jit-switch-context ( -- )
    0xc3 B-BRK
    ! Push a bogus return address so the GC can track this frame back
    ! to the owner
    ! temp 0 ADR
    ! FP temp SP -16 [pre] STP

    ! Make the new context the current one
    CTX VM vm-context-offset [+] STR

    ! Load new stack pointer
    temp CTX context-callstack-top-offset [+] LDR
    SP temp MOV

    ! Load new ds, rs registers
    jit-restore-context

    jit-update-teb ;

: jit-set-context ( -- )
    0xc3 B-BRK
    ds-0 DS -8 [post] LDR
    ds-0 dup alien-offset [+] LDR
    ds-1 DS -8 [post] LDR
    jit-save-context
    0xc1 B-BRK
    CTX ds-0 MOV
    jit-switch-context
    ! SP dup 16 ADD
    0xc1 B-BRK
    ds-1 DS 8 [pre] STR ;

: jit-delete-current-context ( -- )
    0xc1 B-BRK
    arg1 VM MOV
    "delete_context" LDR=BLR rel-dlsym ;

: jit-start-context ( -- )
    ! Create the new context in RETURN. Have to save context
    ! twice, first before calling new_context() which may GC,
    ! and again after popping the two parameters from the stack.
    jit-save-context
    0xc1 B-BRK
    arg1 VM MOV
    "new_context" LDR=BLR rel-dlsym

    0xc2 B-BRK
    ds-1 DS -8 [post] LDR
    ds-0 DS -8 [post] LDR
    jit-save-context
    0xc1 B-BRK
    CTX RETURN MOV
    jit-switch-context
    0xc4 B-BRK
    ds-0 DS 8 [pre] STR
    ! arg1 is a surprise tool that will be important later
    arg1 ds-1 MOV
    temp arg1 quot-entry-point-offset [+] LDR
    temp BR ;

! Resets the active context and instead the passed in quotation
! becomes the new code that it executes.
: jit-start-context-and-delete ( -- )
    ! Updates the context to match the values in the data and retain
    ! stack registers. reset_context can GC.
    jit-save-context

    ! Resets the context. The top two ds items are preserved.
    0xc1 B-BRK
    arg1 VM MOV
    "reset_context" LDR=BLR rel-dlsym

    ! Switches to the same context I think.
    jit-switch-context

    0xc3 B-BRK
    ds-0 DS -8 [post] LDR
    temp ds-0 quot-entry-point-offset [+] LDR
    temp BR ;

: jit-compare ( cond -- )
    t temp1 (LDR=) rel-literal
    0xc5 B-BRK
    temp2 \ f type-number MOV
    ds-1 ds-0 DS -8 [pre] LDP
    ds-1 ds-0 CMP
    [ ds-0 temp1 temp2 ] dip CSEL
    ds-0 DS [] STR ;

{
    { (set-context) [ 0x100 B-BRK jit-set-context ] }
    { (set-context-and-delete) [
        0x101 B-BRK
        jit-delete-current-context
        jit-set-context
    ] }
    { (start-context) [ 0x102 B-BRK jit-start-context ] }
    { (start-context-and-delete) [ 0x103 B-BRK jit-start-context-and-delete ] }

    { fixnum+fast [
        0x200 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 ds-1 ds-0 ADD
        ds-0 DS [] STR
    ] }
    { fixnum-fast [
        0x201 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 ds-1 ds-0 SUB
        ds-0 DS [] STR
    ] }
    { fixnum*fast [
        0x202 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 dup tag-bits get ASR
        ds-0 dup ds-1 MUL
        ds-0 DS [] STR
    ] }

    { fixnum+ [
        0x210 B-BRK
        arg1 arg2 DS -8 [pre] LDP
        jit-save-context
        0xc3 B-BRK
        ds-0 arg1 arg2 ADDS
        ds-0 DS [] STR
        [ BVC ] [
            0xc1 B-BRK
            arg3 VM MOV
            "overflow_fixnum_add" LDR=BLR rel-dlsym
        ] jit-conditional*
    ] }
    { fixnum- [
        0x211 B-BRK
        arg1 arg2 DS -8 [pre] LDP
        jit-save-context
        ds-0 arg1 arg2 SUBS
        ds-0 DS [] STR
        0xc3 B-BRK
        [ BVC ] [
            0xc1 B-BRK
            arg3 VM MOV
            "overflow_fixnum_subtract" LDR=BLR rel-dlsym
        ] jit-conditional*
    ] }
    { fixnum* [
        0x212 B-BRK
        arg1 arg2 DS -8 [pre] LDP
        jit-save-context
        0xc7 B-BRK
        arg1 dup tag-bits get ASR
        ds-0 arg1 arg2 MUL
        ds-0 DS [] STR
        ds-0 dup 63 ASR
        temp arg1 arg2 SMULH
        ds-0 temp CMP
        [ BEQ ] [
            0xc1 B-BRK
            arg2 dup tag-bits get ASR
            arg3 VM MOV
            "overflow_fixnum_multiply" LDR=BLR rel-dlsym
        ] jit-conditional*
    ] }

    { fixnum/i-fast [
        0x220 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        quotient ds-1 ds-0 SDIV
        quotient dup tag-bits get LSL
        quotient DS [] STR
    ] }
    { fixnum-mod [
        0x221 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        quotient ds-1 ds-0 SDIV
        remainder ds-0 quotient ds-1 MSUB
        remainder DS [] STR
    ] }
    { fixnum/mod-fast [
        0x222 B-BRK
        ds-1 ds-0 DS -8 [+] LDP
        quotient ds-1 ds-0 SDIV
        remainder ds-0 quotient ds-1 MSUB
        quotient dup tag-bits get LSL
        quotient remainder DS -8 [+] STP
    ] }

    { both-fixnums? [
        0x230 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 dup ds-1 ORR
        ds-0 tag-mask get TST
        temp1 1 tag-fixnum MOV
        temp2 \ f type-number MOV
        ds-0 temp1 temp2 EQ CSEL
        ds-0 DS [] STR
    ] }

    { eq? [ 0x231 B-BRK EQ jit-compare ] }
    { fixnum> [ 0x232 B-BRK GT jit-compare ] }
    { fixnum>= [ 0x233 B-BRK GE jit-compare ] }
    { fixnum< [ 0x234 B-BRK LT jit-compare ] }
    { fixnum<= [ 0x235 B-BRK LE jit-compare ] }

    { fixnum-bitnot [
        0x240 B-BRK
        ds-0 DS [] LDR
        ds-0 dup tag-mask get bitnot EOR
        ds-0 DS [] STR
    ] }
    { fixnum-bitand [
        0x241 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 ds-1 ds-0 AND
        ds-0 DS [] STR
    ] }
    { fixnum-bitor [
        0x242 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 ds-1 ds-0 ORR
        ds-0 DS [] STR
    ] }
    { fixnum-bitxor [
        0x243 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 ds-1 ds-0 EOR
        ds-0 DS [] STR
    ] }
    { fixnum-shift-fast [
        0x244 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 dup tag-bits get ASR
        ! compute positive shift value in temp1
        temp1 ds-1 ds-0 LSL
        ! compute negative shift value in temp2
        ds-0 dup NEGS
        temp2 ds-1 ds-0 ASR
        temp2 dup tag-mask get bitnot AND
        ! if shift count was positive, choose temp1
        ds-0 temp1 temp2 MI CSEL
        ds-0 DS [] STR
    ] }

    { drop-locals [
        0x300 B-BRK
        ds-0 DS -8 [post] LDR
        RS dup ds-0 tag-bits get 3 - <ASR> SUB
    ] }
    { get-local [
        0x301 B-BRK
        ds-0 DS [] LDR
        ds-0 dup tag-bits get 3 - ASR
        ds-0 RS ds-0 [+] LDR
        ds-0 DS [] STR
    ] }
    { load-local [ 0x302 B-BRK >r ] }

    { slot [
        0x400 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 dup tag-bits get 3 - ASR
        ds-1 dup tag-mask get bitnot AND
        ds-0 dup ds-1 [+] LDR
        ds-0 DS [] STR
    ] }
    { string-nth-fast [
        0x401 B-BRK
        ds-1 ds-0 DS -8 [pre] LDP
        ds-0 dup ds-1 tag-bits get <ASR> ADD
        ds-0 dup string-offset [+] LDURB
        ds-0 dup tag-bits get LSL
        ds-0 DS [] STR
    ] }
    { tag [
        0x402 B-BRK
        ds-0 DS [] LDR
        ds-0 dup tag-bits get dup UBFIZ
        ds-0 DS [] STR
    ] }

    { drop [ 0x500 B-BRK DS dup 8 SUB ] }
    { 2drop [ 0x501 B-BRK DS dup 16 SUB ] }
    { 3drop [ 0x502 B-BRK DS dup 24 SUB ] }
    { 4drop [ 0x503 B-BRK DS dup 32 SUB ] }
    { dup [
        0x504 B-BRK
        ds-0 DS [] LDR
        ds-0 DS 8 [pre] STR
    ] }
    { 2dup [
        0x505 B-BRK
        ds-1 ds-0 DS -8 [+] LDP
        ds-1 DS 8 [pre] STR
        ds-0 DS 8 [pre] STR
    ] }
    { 3dup [
        0x506 B-BRK
        ds-2 DS -16 [+] LDR
        ds-1 ds-0 DS -8 [+] LDP
        ds-2 ds-1 DS 8 [pre] STP
        ds-0 DS 16 [pre] STR
    ] }
    { 4dup [
        0x507 B-BRK
        ds-3 ds-2 DS -24 [+] LDP
        ds-1 ds-0 DS -8 [+] LDP
        ds-3 ds-2 DS 8 [pre] STP
        ds-1 DS 16 [pre] STR
        ds-0 DS 8 [pre] STR
    ] }
    { dupd [
        0x508 B-BRK
        ds-1 ds-0 DS -8 [+] LDP
        ds-1 DS [] STR
        ds-0 DS 8 [pre] STR
    ] }
    { over [
        0x509 B-BRK
        ds-1 DS -8 [+] LDR
        ds-1 DS 8 [pre] STR
    ] }
    { pick [
        0x50a B-BRK
        ds-2 DS -16 [+] LDR
        ds-2 DS 8 [pre] STR
    ] }
    { nip [
        0x50b B-BRK
        ds-0 DS [] LDR
        ds-0 DS -8 [pre] STR
    ] }
    { 2nip [
        0x50c B-BRK
        ds-0 DS [] LDR
        ds-0 DS -16 [pre] STR
    ] }
    { -rot [
        0x50d B-BRK
        ds-0 DS -8 [post] LDR
        ds-2 ds-1 DS -8 [+] LDP
        ds-0 ds-2 DS -8 [+] STP
        ds-1 DS 8 [pre] STR
    ] }
    { rot [
        0x50e B-BRK
        ds-0 DS -8 [post] LDR
        ds-2 ds-1 DS -8 [+] LDP
        ds-1 ds-0 DS -8 [+] STP
        ds-2 DS 8 [pre] STR
    ] }
    { swap [
        0x50f B-BRK
        ds-1 ds-0 DS -8 [+] LDP
        ds-0 ds-1 DS -8 [+] STP
    ] }
    { swapd [
        0x510 B-BRK
        ds-2 ds-1 DS -16 [+] LDP
        ds-1 ds-2 DS -16 [+] STP
    ] }

    { set-callstack [
        0x600 B-BRK
        ds-0 DS -8 [post] LDR
        ! Get ctx->callstack_bottom
        arg1 CTX context-callstack-bottom-offset [+] LDR
        ! Get top of callstack object -- 'src' for memcpy
        arg2 ds-0 callstack-top-offset ADD
        ! Get callstack length, in bytes --- 'len' for memcpy
        arg3 ds-0 callstack-length-offset [+] LDR
        arg3 dup tag-bits get LSR
        ! Compute new stack pointer -- 'dst' for memcpy
        arg1 dup arg3 SUB
        ! Install new stack pointer
        SP arg1 MOV
        ! Call memcpy; arguments are now in the correct registers
        ! Create register shadow area for Win64
        SP dup 32 SUB
        "factor_memcpy" LDR=BLR rel-dlsym
        0xc3 B-BRK
        ! Tear down register shadow area
        SP dup 32 ADD
        ! Return with new callstack
        FP LR SP stack-frame-size [post] LDP
        RET
    ] }
    { brk [ 0x1234 BRK ] }
} define-sub-primitives

[ "bootstrap.assembler.arm" forget-vocab ] with-compilation-unit
