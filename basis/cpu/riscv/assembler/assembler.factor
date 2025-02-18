! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: arrays combinators compiler.constants endian kernel
layouts make math math.bitwise ;
IN: cpu.riscv.assembler

CONSTANT: x0  0
CONSTANT: x1  1
CONSTANT: x2  2
CONSTANT: x3  3
CONSTANT: x4  4
CONSTANT: x5  5
CONSTANT: x6  6
CONSTANT: x7  7
CONSTANT: x8  8
CONSTANT: x9  9
CONSTANT: x10 10
CONSTANT: x11 11
CONSTANT: x12 12
CONSTANT: x13 13
CONSTANT: x14 14
CONSTANT: x15 15
CONSTANT: x16 16
CONSTANT: x17 17
CONSTANT: x18 18
CONSTANT: x19 19
CONSTANT: x20 20
CONSTANT: x21 21
CONSTANT: x22 22
CONSTANT: x23 23
CONSTANT: x24 24
CONSTANT: x25 25
CONSTANT: x26 26
CONSTANT: x27 27
CONSTANT: x28 28
CONSTANT: x29 29
CONSTANT: x30 30
CONSTANT: x31 31

CONSTANT: zero 0
CONSTANT: ra 1
CONSTANT: sp 2
CONSTANT: gp 3
CONSTANT: tp 4
CONSTANT: t0 5
CONSTANT: t1 6
CONSTANT: t2 7
CONSTANT: s0 8
CONSTANT: s1 9
CONSTANT: a0 10
CONSTANT: a1 11
CONSTANT: a2 12
CONSTANT: a3 13
CONSTANT: a4 14
CONSTANT: a5 15
CONSTANT: a6 16
CONSTANT: a7 17
CONSTANT: s2 18
CONSTANT: s3 19
CONSTANT: s4 20
CONSTANT: s5 21
CONSTANT: s6 22
CONSTANT: s7 23
CONSTANT: s8 24
CONSTANT: s9 25
CONSTANT: s10 26
CONSTANT: s11 27
CONSTANT: t3 28
CONSTANT: t4 29
CONSTANT: t5 30
CONSTANT: t6 31

! t0-t6 s0-s11
CONSTANT: vm 18
CONSTANT: ctx 19
CONSTANT: ds 20
CONSTANT: rs 21
CONSTANT: pic-tail 22
CONSTANT: safepoint 23
CONSTANT: mega-hits 24
CONSTANT: cache-miss 25
CONSTANT: cards-offset 26
CONSTANT: decks-offset 27
CONSTANT: cache 30
CONSTANT: obj 30
CONSTANT: type 31

CONSTANT: f0  0
CONSTANT: f1  1
CONSTANT: f2  2
CONSTANT: f3  3
CONSTANT: f4  4
CONSTANT: f5  5
CONSTANT: f6  6
CONSTANT: f7  7
CONSTANT: f8  8
CONSTANT: f9  9
CONSTANT: f10 10
CONSTANT: f11 11
CONSTANT: f12 12
CONSTANT: f13 13
CONSTANT: f14 14
CONSTANT: f15 15
CONSTANT: f16 16
CONSTANT: f17 17
CONSTANT: f18 18
CONSTANT: f19 19
CONSTANT: f20 20
CONSTANT: f21 21
CONSTANT: f22 22
CONSTANT: f23 23
CONSTANT: f24 24
CONSTANT: f25 25
CONSTANT: f26 26
CONSTANT: f27 27
CONSTANT: f28 28
CONSTANT: f29 29
CONSTANT: f30 30
CONSTANT: f31 31

CONSTANT: ft0 0
CONSTANT: ft1 1
CONSTANT: ft2 2
CONSTANT: ft3 3
CONSTANT: ft4 4
CONSTANT: ft5 5
CONSTANT: ft6 6
CONSTANT: ft7 7
CONSTANT: fs0 8
CONSTANT: fs1 9
CONSTANT: fa0 10
CONSTANT: fa1 11
CONSTANT: fa2 12
CONSTANT: fa3 13
CONSTANT: fa4 14
CONSTANT: fa5 15
CONSTANT: fa6 16
CONSTANT: fa7 17
CONSTANT: fs2 18
CONSTANT: fs3 19
CONSTANT: fs4 20
CONSTANT: fs5 21
CONSTANT: fs6 22
CONSTANT: fs7 23
CONSTANT: fs8 24
CONSTANT: fs9 25
CONSTANT: fs10 26
CONSTANT: fs11 27
CONSTANT: ft8 28
CONSTANT: ft9 29
CONSTANT: ft10 30
CONSTANT: ft11 31

MACRO: encode ( bitspec -- quot ) '[ _ bitfield* 4 >le % ] ;

: r-encode ( rd rs1 rs2 opcode funct3 funct7 -- )
    {
        7
        15
        20
        0
        12
        25
    } encode ;

: r4-encode ( rd rs1 rs2 rs3 opcode funct3 funct2 -- )
    {
        7
        15
        20
        27
        0
        12
        25
    } encode ;

: i-encode ( rd rs1 imm[11:0] opcode funct3 -- )
    {
        7
        15
        20
        0
        12
    } encode ;

: s-encode ( rs1 rs2 imm12 opcode funct3 -- )
    [ [ 5 bits ] [ -5 shift 7 bits ] bi ] 2dip {
        15
        20
        7
        25
        0
        12
    } encode ;

: b-encode ( rs1 rs2 imm[12:0] opcode funct3 -- )
    [ {
        [ -1 shift 4 bits ]
        [ -5 shift 6 bits ]
        [ -11 shift 1 bits ]
        [ -12 shift 1 bits ]
    } cleave ] 2dip {
        15
        20
        8
        25
        7
        31
        0
        12
    } encode ;

: u-encode ( rd imm[31:12] opcode -- )
    {
        7
        12
        0
    } encode ;

: j-encode ( rd imm[20:0] opcode -- )
    [ {
        [ -1 shift 10 bits ]
        [ -11 shift 1 bits ]
        [ -12 shift 8 bits ]
        [ -20 shift 1 bits ]
    } cleave ] dip {
        7
        21
        20
        12
        31
        0
    } encode ;

! I base integer instructions

: lui       ( rd         imm -- ) 0b0110111                 u-encode ;
: auipc     ( rd         imm -- ) 0b0010111                 u-encode ;

: (jal)     ( rd         imm -- ) 0b1101111                 j-encode ;
: (jalr)    ( rd  rs1    imm -- ) 0b1100111 0b000           i-encode ;

: j         (            imm -- ) zero swap (jal) ;
: jal       (            imm -- ) ra swap (jal) ;
: jr        (    rs1         -- ) zero swap 0 (jalr) ;
: jalr      (    rs1         -- ) ra swap 0 (jalr) ;
: ret       (                -- ) zero ra 0 (jalr) ;

: ji        (          -- class )
    t0 0 lui
    t0 jr rc-absolute-riscv-u-i ;

: jali      (          -- class )
    t0 0 lui
    t0 jalr rc-absolute-riscv-u-i ;

: beq       (    rs1 rs2 imm -- ) 0b1100011 0b000           b-encode ;
: bne       (    rs1 rs2 imm -- ) 0b1100011 0b001           b-encode ;
: blt       (    rs1 rs2 imm -- ) 0b1100011 0b100           b-encode ;
: bge       (    rs1 rs2 imm -- ) 0b1100011 0b101           b-encode ;
: bltu      (    rs1 rs2 imm -- ) 0b1100011 0b110           b-encode ;
: bgeu      (    rs1 rs2 imm -- ) 0b1100011 0b111           b-encode ;

: beqz      (    rs1     imm -- ) zero swap beq ;
: bnez      (    rs1     imm -- ) zero swap bne ;
: blez      (        rs2 imm -- ) zero -rot bge ;
: bgez      (    rs1     imm -- ) zero swap bge ;
: bltz      (    rs1     imm -- ) zero swap blt ;
: bgtz      (        rs2 imm -- ) zero -rot blt ;
: bgt       (    rs1 rs2 imm -- ) swapd blt ;
: ble       (    rs1 rs2 imm -- ) swapd bge ;
: bgtu      (    rs1 rs2 imm -- ) swapd bltu ;
: bleu      (    rs1 rs2 imm -- ) swapd bgeu ;

: lb        ( rd rs1     imm -- ) 0b0000011 0b000           i-encode ;
: lh        ( rd rs1     imm -- ) 0b0000011 0b001           i-encode ;
: lw        ( rd rs1     imm -- ) 0b0000011 0b010           i-encode ;
: ld        ( rd rs1     imm -- ) 0b0000011 0b011           i-encode ;

: lc        ( rd rs1     imm -- )
    bootstrap-cell {
        { 4 [ lw ] }
        { 8 [ ld ] }
    } case ;

:: li       ( rd       -- class )
    rd 12 auipc
    rd rd 0 lc
    12 j
    bootstrap-cell 0 <array> % rc-absolute-cell ;

: lbu       ( rd rs1     imm -- ) 0b0000011 0b100           i-encode ;
: lhu       ( rd rs1     imm -- ) 0b0000011 0b101           i-encode ;
: lwu       ( rd rs1     imm -- ) 0b0000011 0b110           i-encode ;

: sb     ( rs2 rs1 imm -- ) swapd 0b0100011 0b000           s-encode ;
: sh     ( rs2 rs1 imm -- ) swapd 0b0100011 0b001           s-encode ;
: sw     ( rs2 rs1 imm -- ) swapd 0b0100011 0b010           s-encode ;
: sd     ( rs2 rs1 imm -- ) swapd 0b0100011 0b011           s-encode ;

: sc       ( rs2 rs1     imm -- )
    bootstrap-cell {
        { 4 [ sw ] }
        { 8 [ sd ] }
    } case ;

: addi      ( rd rs1     imm -- ) 0b0010011 0b000           i-encode ;
: slti      ( rd rs1     imm -- ) 0b0010011 0b010           i-encode ;
: sltiu     ( rd rs1     imm -- ) 0b0010011 0b011           i-encode ;
: xori      ( rd rs1     imm -- ) 0b0010011 0b100           i-encode ;
: ori       ( rd rs1     imm -- ) 0b0010011 0b110           i-encode ;
: andi      ( rd rs1     imm -- ) 0b0010011 0b111           i-encode ;
: addiw     ( rd rs1     imm -- ) 0b0011011 0b000           i-encode ;

: nop       (                -- ) zero zero 0 addi ;
: mv        ( rd rs1         -- ) 0 addi ;
: not       ( rd rs1         -- ) -1 xori ;
: seqz      ( rd rs1         -- ) 1 sltiu ;
: mvi       ( rd         imm -- ) zero swap addi ;

: slli      ( rd rs1     imm -- ) 0b0010011 0b001 0b0000000 r-encode ;
: srli      ( rd rs1     imm -- ) 0b0010011 0b101 0b0000000 r-encode ;
: srai      ( rd rs1     imm -- ) 0b0010011 0b101 0b0100000 r-encode ;
: slliw     ( rd rs1     imm -- ) 0b0011011 0b001 0b0000000 r-encode ;
: srliw     ( rd rs1     imm -- ) 0b0011011 0b000 0b0000000 r-encode ;
: sraiw     ( rd rs1     imm -- ) 0b0011011 0b000 0b0100000 r-encode ;

: add       ( rd rs1 rs2     -- ) 0b0110011 0b000 0b0000000 r-encode ;
: sub       ( rd rs1 rs2     -- ) 0b0110011 0b000 0b0100000 r-encode ;
: sll       ( rd rs1 rs2     -- ) 0b0110011 0b001 0b0000000 r-encode ;
: slt       ( rd rs1 rs2     -- ) 0b0110011 0b010 0b0000000 r-encode ;
: sltu      ( rd rs1 rs2     -- ) 0b0110011 0b011 0b0000000 r-encode ;
: xor       ( rd rs1 rs2     -- ) 0b0110011 0b100 0b0000000 r-encode ;
: srl       ( rd rs1 rs2     -- ) 0b0110011 0b101 0b0000000 r-encode ;
: sra       ( rd rs1 rs2     -- ) 0b0110011 0b101 0b0100000 r-encode ;
: or        ( rd rs1 rs2     -- ) 0b0110011 0b110 0b0000000 r-encode ;
: and       ( rd rs1 rs2     -- ) 0b0110011 0b111 0b0000000 r-encode ;
: addw      ( rd rs1 rs2     -- ) 0b0111011 0b000 0b0000000 r-encode ;
: subw      ( rd rs1 rs2     -- ) 0b0111011 0b000 0b0100000 r-encode ;
: sllw      ( rd rs1 rs2     -- ) 0b0111011 0b001 0b0000000 r-encode ;
: srlw      ( rd rs1 rs2     -- ) 0b0111011 0b001 0b0000000 r-encode ;
: sraw      ( rd rs1 rs2     -- ) 0b0111011 0b001 0b0100000 r-encode ;

: neg       ( rd rs1         -- ) zero swap sub ;
: negw      ( rd rs1         -- ) zero swap subw ;
: snez      ( rd rs1         -- ) zero swap sltu ;
: sltz      ( rd rs1         -- ) zero slt ;
: sgtz      ( rd rs1         -- ) zero swap slt ;

! M multiplication and division

: mul       ( rd rs1 rs2     -- ) 0b0110011 0b000 0b0000001 r-encode ;
: mulh      ( rd rs1 rs2     -- ) 0b0110011 0b001 0b0000001 r-encode ;
: mulhsu    ( rd rs1 rs2     -- ) 0b0110011 0b010 0b0000001 r-encode ;
: mulhu     ( rd rs1 rs2     -- ) 0b0110011 0b011 0b0000001 r-encode ;

: div       ( rd rs1 rs2     -- ) 0b0110011 0b100 0b0000001 r-encode ;
: divu      ( rd rs1 rs2     -- ) 0b0110011 0b101 0b0000001 r-encode ;
: rem       ( rd rs1 rs2     -- ) 0b0110011 0b110 0b0000001 r-encode ;
: remu      ( rd rs1 rs2     -- ) 0b0110011 0b111 0b0000001 r-encode ;

: mulw      ( rd rs1 rs2     -- ) 0b0111011 0b000 0b0000001 r-encode ;
: divw      ( rd rs1 rs2     -- ) 0b0111011 0b100 0b0000001 r-encode ;
: divuw     ( rd rs1 rs2     -- ) 0b0111011 0b101 0b0000001 r-encode ;
: remw      ( rd rs1 rs2     -- ) 0b0111011 0b110 0b0000001 r-encode ;
: remuw     ( rd rs1 rs2     -- ) 0b0111011 0b111 0b0000001 r-encode ;

! F single-precision floating-point

: flw       ( rd rs1     imm -- ) 0b0000111 0b010           i-encode ;
: fsw       (    rs1 rs2 imm -- ) 0b0100111 0b010           s-encode ;

: fmadd.s   ( rd rs1 rs2 rs3 -- ) 0b1000011 0b000 0b00     r4-encode ;
: fmsub.s   ( rd rs1 rs2 rs3 -- ) 0b1000111 0b000 0b00     r4-encode ;
: fnmadd.s  ( rd rs1 rs2 rs3 -- ) 0b1001011 0b000 0b00     r4-encode ;
: fnmsub.s  ( rd rs1 rs2 rs3 -- ) 0b1001111 0b000 0b00     r4-encode ;
: fadd.s    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0000000 r-encode ;
: fsub.s    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0000100 r-encode ;
: fmul.s    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0001000 r-encode ;
: fdiv.s    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0001100 r-encode ;
: fsqrt.s   ( rd rs1       -- ) 0 0b1010011 0b000 0b0101100 r-encode ;
: fsgnj.s   ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0010000 r-encode ;
: fsgnjn.s  ( rd rs1 rs2     -- ) 0b1010011 0b001 0b0010000 r-encode ;
: fsgnjx.s  ( rd rs1 rs2     -- ) 0b1010011 0b010 0b0010000 r-encode ;
: fmin.s    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0010100 r-encode ;
: fmax.s    ( rd rs1 rs2     -- ) 0b1010011 0b001 0b0010100 r-encode ;
: fcvt.w.s  ( rd rs1       -- ) 0 0b1010011 0b000 0b1100000 r-encode ;
: fcvt.wu.s ( rd rs1       -- ) 1 0b1010011 0b000 0b1100000 r-encode ;
: fmv.x.w   ( rd rs1       -- ) 0 0b1010011 0b000 0b1110000 r-encode ;
: feq.s     ( rd rs1 rs2     -- ) 0b1010011 0b010 0b1010000 r-encode ;
: flt.s     ( rd rs1 rs2     -- ) 0b1010011 0b001 0b1010000 r-encode ;
: fle.s     ( rd rs1 rs2     -- ) 0b1010011 0b000 0b1010000 r-encode ;
: fclass.s  ( rd rs1 rs2     -- ) 0b1010011 0b001 0b1110000 r-encode ;
: fcvt.s.w  ( rd rs1       -- ) 0 0b1010011 0b000 0b1101000 r-encode ;
: fcvt.s.wu ( rd rs1       -- ) 1 0b1010011 0b000 0b1101000 r-encode ;
: fmv.w.x   ( rd rs1       -- ) 0 0b1010011 0b000 0b1111000 r-encode ;
: fcvt.l.s  ( rd rs1       -- ) 2 0b1010011 0b000 0b1100000 r-encode ;
: fcvt.lu.s ( rd rs1       -- ) 3 0b1010011 0b000 0b1100000 r-encode ;
: fcvt.s.l  ( rd rs1       -- ) 2 0b1010011 0b000 0b1101000 r-encode ;
: fcvt.s.lu ( rd rs1       -- ) 3 0b1010011 0b000 0b1101000 r-encode ;

: fmv.s     ( rd rs1       -- ) dup fsgnj.s ;
: fabs.s    ( rd rs1       -- ) dup fsgnjx.s ;
: fneg.s    ( rd rs1       -- ) dup fsgnjn.s ;

! D double-precision floating-point

: fld       ( rd rs1     imm -- ) 0b0000111 0b011           i-encode ;
: fsd       (    rs1 rs2 imm -- ) 0b0100111 0b011           s-encode ;

: fmadd.d   ( rd rs1 rs2 rs3 -- ) 0b1000011 0b000 0b01     r4-encode ;
: fmsub.d   ( rd rs1 rs2 rs3 -- ) 0b1000111 0b000 0b01     r4-encode ;
: fnmadd.d  ( rd rs1 rs2 rs3 -- ) 0b1001011 0b000 0b01     r4-encode ;
: fnmsub.d  ( rd rs1 rs2 rs3 -- ) 0b1001111 0b000 0b01     r4-encode ;
: fadd.d    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0000001 r-encode ;
: fsub.d    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0000101 r-encode ;
: fmul.d    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0001001 r-encode ;
: fdiv.d    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0001101 r-encode ;
: fsqrt.d   ( rd rs1       -- ) 0 0b1010011 0b000 0b0101101 r-encode ;
: fsgnj.d   ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0010001 r-encode ;
: fsgnjn.d  ( rd rs1 rs2     -- ) 0b1010011 0b001 0b0010001 r-encode ;
: fsgnjx.d  ( rd rs1 rs2     -- ) 0b1010011 0b010 0b0010001 r-encode ;
: fmin.d    ( rd rs1 rs2     -- ) 0b1010011 0b000 0b0010101 r-encode ;
: fmax.d    ( rd rs1 rs2     -- ) 0b1010011 0b001 0b0010101 r-encode ;
: fcvt.s.d  ( rd rs1       -- ) 1 0b1010011 0b000 0b0100000 r-encode ;
: fcvt.d.s  ( rd rs1       -- ) 0 0b1010011 0b000 0b0100001 r-encode ;
: feq.d     ( rd rs1 rs2     -- ) 0b1010011 0b010 0b1010001 r-encode ;
: flt.d     ( rd rs1 rs2     -- ) 0b1010011 0b001 0b1010001 r-encode ;
: fle.d     ( rd rs1 rs2     -- ) 0b1010011 0b000 0b1010001 r-encode ;
: fclass.d  ( rd rs1       -- ) 0 0b1010011 0b001 0b1110001 r-encode ;
: fcvt.w.d  ( rd rs1       -- ) 0 0b1010011 0b000 0b1100001 r-encode ;
: fcvt.wu.d ( rd rs1       -- ) 1 0b1010011 0b000 0b1100001 r-encode ;
: fcvt.d.w  ( rd rs1       -- ) 0 0b1010011 0b000 0b1101001 r-encode ;
: fcvt.d.wu ( rd rs1       -- ) 1 0b1010011 0b000 0b1101001 r-encode ;
: fcvt.l.d  ( rd rs1       -- ) 2 0b1010011 0b000 0b1100001 r-encode ;
: fcvt.lu.d ( rd rs1       -- ) 3 0b1010011 0b000 0b1100001 r-encode ;
: fmv.x.d   ( rd rs1       -- ) 0 0b1010011 0b000 0b1110001 r-encode ;
: fcvt.d.l  ( rd rs1       -- ) 2 0b1010011 0b000 0b1101001 r-encode ;
: fcvt.d.lu ( rd rs1       -- ) 3 0b1010011 0b000 0b1101001 r-encode ;
: fmv.d.x   ( rd rs1       -- ) 0 0b1010011 0b000 0b1111001 r-encode ;

: fmv.d     ( rd rs1       -- ) dup fsgnj.d ;
: fabs.d    ( rd rs1       -- ) dup fsgnjx.d ;
: fneg.d    ( rd rs1       -- ) dup fsgnjn.d ;
