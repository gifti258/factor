! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: bootstrap.image.private compiler.codegen.relocation
compiler.constants compiler.units cpu.riscv.assembler
generic.single.private kernel kernel.private layouts
locals.backend make math math.private namespaces slots.private
strings.private threads.private vocabs ;
FROM: cpu.riscv.assembler => and or rem xor ;
FROM: math => neg ;
IN: bootstrap.assembler.riscv

[
    sp sp bootstrap-cell neg addi
    ra sp 0 sc
] JIT-PROLOG jit-define

: jit-save-context ( -- )
    sp ctx context-callstack-top-offset sc
    ds ctx context-datastack-offset sc
    rs ctx context-retainstack-offset sc ;

: jit-restore-context ( -- )
    ds ctx context-datastack-offset lc
    rs ctx context-retainstack-offset lc ;

[
    jit-save-context
    a0 vm mv
    f f jali rel-dlsym
    jit-restore-context
] JIT-PRIMITIVE jit-define

[
    f ji rel-word-pic-tail
] JIT-WORD-JUMP jit-define

[
    f jali rel-word-pic
] JIT-WORD-CALL jit-define

[
    t0 ds 0 lc
    ds ds bootstrap-cell neg addi
    t1 \ f type-number mvi
    t0 t1 12 bne
    f ji rel-word
    f ji rel-word
] JIT-IF jit-define

[
    safepoint dup 0 sc
] JIT-SAFEPOINT jit-define

[
    ra sp 0 lc
    sp sp bootstrap-cell neg addi
] JIT-EPILOG jit-define

[
    ret
] JIT-RETURN jit-define

[
    f t0 li rel-literal
    ds ds bootstrap-cell addi
    t0 ds 0 sc
] JIT-PUSH-LITERAL jit-define

[
    t0 ds 0 lc
    ds ds bootstrap-cell neg addi
    rs rs bootstrap-cell addi
    t0 rs 0 sc
    f jali rel-word
    t0 rs 0 lc
    rs rs bootstrap-cell neg addi
    ds ds bootstrap-cell addi
    t0 ds 0 sc
] JIT-DIP jit-define

[
    t1 ds bootstrap-cell neg lc
    t0 ds 0 lc
    ds ds 2 bootstrap-cells neg addi
    rs rs 2 bootstrap-cells addi
    t1 rs bootstrap-cell neg sc
    t0 rs 0 sc
    f jali rel-word
    t1 rs bootstrap-cell neg lc
    t0 rs 0 lc
    rs rs 2 bootstrap-cells neg addi
    ds ds 2 bootstrap-cells addi
    t1 ds bootstrap-cell neg sc
    t0 ds 0 sc
] JIT-2DIP jit-define

[
    t2 ds 2 bootstrap-cells neg lc
    t1 ds bootstrap-cell neg lc
    t0 ds 0 lc
    ds ds 3 bootstrap-cells neg addi
    rs rs 3 bootstrap-cells addi
    t2 rs 2 bootstrap-cells neg sc
    t1 rs bootstrap-cell neg sc
    t0 rs 0 sc
    f jali rel-word
    t2 rs 2 bootstrap-cells neg lc
    t1 rs bootstrap-cell neg lc
    t0 rs 0 lc
    rs rs 3 bootstrap-cells neg addi
    ds ds 3 bootstrap-cells addi
    t2 ds 2 bootstrap-cells neg sc
    t1 ds bootstrap-cell neg sc
    t0 ds 0 sc
] JIT-3DIP jit-define

[
    a0 ds 0 lc
    ds ds bootstrap-cell neg addi
    t0 a0 quot-entry-point-offset lc
]
[ t0 jalr ]
[ t0 jr ]
\ (call) define-combinator-primitive

[
    t0 ds 0 lc
    ds ds bootstrap-cell neg addi
    t0 t0 word-entry-point-offset lc
]
[ t0 jalr ]
[ t0 jr ]
\ (execute) define-combinator-primitive

[
    t0 ds 0 lc
    ds ds bootstrap-cell neg addi
    t0 t0 word-entry-point-offset lc
    t0 jr
] JIT-EXECUTE jit-define

[
    a1 a0 mv
    a0 vm mv
    "begin_callback" f jali rel-dlsym

    t0 a0 quot-entry-point-offset lc
    t0 jalr

    a0 vm mv
    "end_callback" f jali rel-dlsym
] \ c-to-factor define-sub-primitive

[
    jit-save-context
    a1 vm mv
    "lazy_jit_compile" f jali rel-dlsym
    t0 a0 quot-entry-point-offset lc
]
[ t0 jalr ]
[ t0 jr ]
\ lazy-jit-compile define-combinator-primitive

{
    { unwind-native-frames [
        sp a1 mv
        zero vm vm-fault-flag-offset sc
        t0 a0 quot-entry-point-offset lc
        t0 jr
    ] }
    { fpu-state [
        ! clear fcsr
    ] }
    { set-fpu-state [  ] }
} define-sub-primitives

{
    { signal-handler [
        ! todo
    ] }
    { leaf-signal-handler [
        ! todo
    ] }
} define-sub-primitives

[
    ! save non-volatile registers
    sp sp 13 bootstrap-cells neg addi
    s0 sp 0 sc
    s1 sp bootstrap-cell sc
    s2 sp 2 bootstrap-cells sc
    s3 sp 3 bootstrap-cells sc
    s4 sp 4 bootstrap-cells sc
    s5 sp 5 bootstrap-cells sc
    s6 sp 6 bootstrap-cells sc
    s7 sp 7 bootstrap-cells sc
    s8 sp 8 bootstrap-cells sc
    s9 sp 9 bootstrap-cells sc
    s10 sp 10 bootstrap-cells sc
    s11 sp 11 bootstrap-cells sc

    f vm li rel-vm
    safepoint li rel-safepoint
    mega-hits li rel-megamorphic-cache-hits
    cache-miss li rel-inline-cache-miss
    cards-offset li rel-cards-offset
    decks-offset li rel-decks-offset

    ! save old context
    ctx vm vm-context-offset lc
    ctx sp 12 bootstrap-cells sc

    ! switch over to the spare context
    ctx vm vm-spare-context-offset lc
    ctx vm vm-context-offset sc

    ! save c callstack pointer
    sp ctx context-callstack-save-offset sc

    ! load factor stack pointers
    sp ctx context-callstack-bottom-offset lc
    rs ctx context-retainstack-offset lc
    ds ctx context-datastack-offset lc

    ! call into factor code
    f jali rel-word

    ! load c callstack pointer
    ctx vm vm-context-offset lc
    sp ctx context-callstack-save-offset lc

    ! load old context
    ctx sp 12 bootstrap-cells lc
    ctx vm vm-context-offset sc

    ! restore non-volatile registers
    s0 sp 0 lc
    s1 sp bootstrap-cell lc
    s2 sp 2 bootstrap-cells lc
    s3 sp 3 bootstrap-cells lc
    s4 sp 4 bootstrap-cells lc
    s5 sp 5 bootstrap-cells lc
    s6 sp 6 bootstrap-cells lc
    s7 sp 7 bootstrap-cells lc
    s8 sp 8 bootstrap-cells lc
    s9 sp 9 bootstrap-cells lc
    s10 sp 10 bootstrap-cells lc
    s11 sp 11 bootstrap-cells lc
    sp sp 13 bootstrap-cells addi

    ret
] CALLBACK-STUB jit-define

[
    obj ds 0 lc f rc-absolute-riscv-i rel-untagged
] PIC-LOAD jit-define

[
    type obj tag-mask get andi
    t0 type mv
] PIC-TAG jit-define

[
    type obj tag-mask get andi
    t0 tuple type-number mvi
    type t0 8 bne
    type obj tuple-class-offset lc
] PIC-TUPLE jit-define

[
    t0 0 mvi f rc-absolute-riscv-i rel-untagged
] PIC-CHECK-TAG jit-define

[
    f t0 li rel-literal
] PIC-CHECK-TUPLE jit-define

[
    type t0 12 bne
    f ji rel-word
] PIC-HIT jit-define

: jit-load-return-address ( -- )
    pic-tail sp 0 lc ;

: jit-inline-cache-miss ( -- )
    jit-save-context
    a0 pic-tail mv
    a1 vm mv
    cache-miss jalr
    jit-restore-context ;

[ jit-load-return-address jit-inline-cache-miss ]
[ a0 jalr ]
[ a0 jr ]
\ inline-cache-miss define-combinator-primitive

[ jit-inline-cache-miss ]
[ a0 jalr ]
[ a0 jr ]
\ inline-cache-miss-tail define-combinator-primitive

[
    type obj tag-mask get andi
    type type tag-bits get slli
    t0 tuple type-number tag-fixnum mvi
    type t0 8 bne
    type obj tuple-class-offset lc
    f cache li rel-literal
    t0 type mega-cache-size get 1 - bootstrap-cells andi
    cache dup t0 add
    t0 cache array-start-offset lc
    type t0 28 bne
    t0 mega-hits 0 lc
    t0 t0 1 addi
    t0 mega-hits 0 sc
    t0 cache array-start-offset bootstrap-cell + lc
    t0 t0 word-entry-point-offset lc
    t0 jr
] MEGA-LOOKUP jit-define

: jit-switch-context ( -- )
    ctx vm vm-context-offset sc
    sp ctx context-callstack-top-offset lc
    jit-restore-context ;

: jit-set-context ( -- )
    t0 ds 0 lc
    t0 t0 alien-offset lc
    t1 ds bootstrap-cell lc
    ds ds 2 bootstrap-cells neg addi
    jit-save-context
    ctx t0 mv
    jit-switch-context
    ds ds bootstrap-cell addi
    t1 ds 0 sc ;

: jit-delete-current-context ( -- )
    a0 vm mv
    "delete_context" f jali rel-dlsym ;

: jit-start-context ( -- )
    jit-save-context
    a0 vm mv
    "new_context" f jali rel-dlsym
    t1 ds bootstrap-cell lc
    a0 ds 0 lc
    ds ds 2 bootstrap-cells neg addi
    jit-save-context
    ctx a0 mv
    jit-switch-context
    ds ds bootstrap-cell addi
    t1 ds 0 sc
    a0 t0 mv
    t0 a0 quot-entry-point-offset lc
    t0 jr ;

: jit-start-context-and-delete ( -- )
    jit-save-context
    a0 vm mv
    "reset_context" f jali rel-dlsym
    jit-switch-context
    t0 ds 0 lc
    ds ds bootstrap-cell neg addi
    t0 t0 quot-entry-point-offset lc
    t0 jr ;

{
    { (set-context) [ jit-set-context ] }
    { (set-context-and-delete) [ jit-delete-current-context jit-set-context ] }
    { (start-context) [ jit-start-context ] }
    { (start-context-and-delete) [ jit-start-context-and-delete ] }
    { fixnum+fast [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 add
        t0 ds 0 sc
    ] }
    { fixnum-fast [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 sub
        t0 ds 0 sc
    ] }
    { fixnum*fast [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 mul
        t0 ds 0 sc
    ] }
    { fixnum+ [

    ] }
    { fixnum- [

    ] }
    { fixnum* [

    ] }
    { fixnum/i-fast [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 div
        t0 ds 0 sc
    ] }
    { fixnum-mod [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 rem
        t0 ds 0 sc
    ] }
    { fixnum/mod-fast [
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        t2 t1 t0 div
        t2 ds bootstrap-cell neg sc
        t0 t1 t0 rem
        t0 ds 0 sc
    ] }
    { both-fixnums? [

    ] }
    { eq? [

    ] }
    { fixnum> [

    ] }
    { fixnum>= [

    ] }
    { fixnum< [

    ] }
    { fixnum<= [

    ] }
    { fixnum-bitnot [
        t0 ds 0 lc
        t0 t0 tag-bits get bitnot xori
        t0 ds 0 sc
    ] }
    { fixnum-bitand [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 and
        t0 ds 0 sc
    ] }
    { fixnum-bitor [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 or
        t0 ds 0 sc
    ] }
    { fixnum-bitxor [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t1 t0 xor
        t0 ds 0 sc
    ] }
    { fixnum-shift-fast [

    ] }
    { drop-locals [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t0 t0 tag-bits get cell-shift-bits - srli
        rs rs t0 sub
    ] }
    { get-local [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t0 t0 4 slli
    ] }
    { load-local [
        t0 rs 0 lc
        rs rs bootstrap-cell neg addi
        ds ds 8 addi
        t0 ds 0 sc
    ] }
    { slot [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t0 t0 tag-bits get cell-shift-bits - srli
        t1 t1 tag-mask get bitnot andi
        t0 t0 t1 lc
        t0 ds 0 sc
    ] }
    { string-nth-fast [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t1 ds 0 lc
        t1 t1 tag-bits get srai
        t0 t0 t1 add
        t0 t0 string-offset lb
        t0 t0 tag-bits get slli
        t0 ds 0 sc
    ] }
    { tag [
        t0 ds 0 lc
        t0 t0 tag-mask get andi
        t0 t0 tag-bits get slli
        t0 ds 0 sc
    ] }
    { drop [ ds ds bootstrap-cell neg addi ] }
    { 2drop [ ds ds 2 bootstrap-cells neg addi ] }
    { 3drop [ ds ds 3 bootstrap-cells neg addi ] }
    { 4drop [ ds ds 4 bootstrap-cells neg addi ] }
    { dup [
        t0 ds 0 lc
        ds ds bootstrap-cell addi
        t0 ds 0 sc
    ] }
    { 2dup [
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        ds ds 2 bootstrap-cells addi
        t1 ds bootstrap-cell neg sc
        t0 ds 0 sc
    ] }
    { 3dup [
        t2 ds 2 bootstrap-cells neg lc
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        ds ds 3 bootstrap-cells addi
        t2 ds 2 bootstrap-cells neg sc
        t1 ds bootstrap-cell neg sc
        t0 ds 0 sc
    ] }
    { 4dup [
        t3 ds 3 bootstrap-cells neg lc
        t2 ds 2 bootstrap-cells neg lc
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        ds ds 4 bootstrap-cells addi
        t3 ds 3 bootstrap-cells neg sc
        t2 ds 2 bootstrap-cells neg sc
        t1 ds bootstrap-cell neg sc
        t0 ds 0 sc
    ] }
    { dupd [
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        ds ds bootstrap-cell addi
        t1 ds bootstrap-cell neg sc
        t0 ds 0 sc
    ] }
    { over [
        t1 ds bootstrap-cell neg lc
        ds ds bootstrap-cell addi
        t1 ds 0 sc
    ] }
    { pick [
        t2 ds 2 bootstrap-cells neg lc
        ds ds bootstrap-cell addi
        t2 ds 0 sc
    ] }
    { nip [
        t0 ds 0 lc
        ds ds bootstrap-cell neg addi
        t0 ds 0 sc
    ] }
    { 2nip [
        t0 ds 0 lc
        ds ds 2 bootstrap-cells neg addi
        t0 ds 0 sc
    ] }
    { -rot [
        t2 ds 2 bootstrap-cells neg lc
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        t0 ds 2 bootstrap-cells neg sc
        t2 ds bootstrap-cell neg sc
        t1 ds 0 sc
    ] }
    { rot [
        t2 ds 2 bootstrap-cells neg lc
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        t1 ds 2 bootstrap-cells neg sc
        t0 ds bootstrap-cell neg sc
        t2 ds 0 sc
    ] }
    { swap [
        t1 ds bootstrap-cell neg lc
        t0 ds 0 lc
        t0 ds bootstrap-cell neg lc
        t1 ds 0 lc
    ] }
    { swapd [
        t2 ds 2 bootstrap-cells neg lc
        t1 ds bootstrap-cell neg lc
        t1 ds 2 bootstrap-cells neg lc
        t2 ds bootstrap-cell neg lc
    ] }
    { set-callstack [

    ] }
} define-sub-primitives

[ "bootstrap.assembler.riscv" forget-vocab ] with-compilation-unit
