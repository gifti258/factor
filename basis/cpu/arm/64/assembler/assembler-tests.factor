! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: arrays cpu.arm.64.assembler cpu.arm.64.assembler.private
endian kernel make math.bitwise tools.test ;
IN: cpu.arm.64.assembler.tests

{ t } [  SP SP? ] unit-test
{ t } [ WSP SP? ] unit-test

{ t } [ XZR ZR? ] unit-test
{ t } [ WZR ZR? ] unit-test

{ SP } [ SP ?SP ] unit-test
{ WSP } [ WSP ?SP ] unit-test
{ X0 } [ X0 ?SP ] unit-test
[ XZR ?SP ] [ incompatible-register? ] must-fail-with

{ XZR } [ XZR !SP ] unit-test
{ WZR } [ WZR !SP ] unit-test
{ X0 } [ X0 !SP ] unit-test
[ SP !SP ] [ incompatible-register? ] must-fail-with

{ t } [ X0 64-bit? ] unit-test
{ t } [ XZR 64-bit? ] unit-test
{ t } [ SP 64-bit? ] unit-test
{ f } [ W0 64-bit? ] unit-test
{ f } [ WZR 64-bit? ] unit-test
{ f } [ WSP 64-bit? ] unit-test

{ X0 } [ X0 ?64-bit ] unit-test
{ W0 } [ W0 ?32-bit ] unit-test
[ X0 ?32-bit ] [ incompatible-register? ] must-fail-with
[ W0 ?64-bit ] [ incompatible-register? ] must-fail-with

{ XZR } [ X0 >ZR ] unit-test

{ W9 } [ X9 >32-bit ] unit-test

{ 1 } [ X0 >bw ] unit-test
{ 1 X0 } [ X0 bw ] unit-test
{ 1 X0 X1 } [ X0 X1 2bw ] unit-test

{ 0 } [ W0 >bw ] unit-test
{ 0 W0 } [ W0 bw ] unit-test
{ 0 W0 W1 } [ W0 W1 2bw ] unit-test

[ X0 W1 2bw ] [ register-mismatch? ] must-fail-with

{ 1 } [ D0 >var ] unit-test

[ -1 1 ?uimm ] [ immediate-width? ] must-fail-with
{ 0 } [ 0 1 ?uimm ] unit-test
{ 1 } [ 1 1 ?uimm ] unit-test
[ 2 1 ?uimm ] [ immediate-width? ] must-fail-with

[ -2 1 ?simm ] [ immediate-width? ] must-fail-with
{ 1 } [ -1 1 ?simm ] unit-test
{ 0 } [ 0 1 ?simm ] unit-test
[ 1 1 ?simm ] [ immediate-width? ] must-fail-with

{ 1 } [ 2 1 ?>> ] unit-test
[ 3 1 ?>> ] [ scaling? ] must-fail-with

{ 3 t } [ 3 2 uimm? ] unit-test
{ 3 f } [ 3 1 uimm? ] unit-test

{ 1 f } [ 1 1 simm? ] unit-test
{ 0 t } [ 0 1 simm? ] unit-test
{ 1 t } [ -1 1 simm? ] unit-test
! { -2 f } [ -2 1 simm? ] unit-test ! result: 0 f

{ 1 t } [ 2 1 1 >>uimm? ] unit-test
{ 3 f } [ 3 1 1 >>uimm? ] unit-test
{ 2 f } [ 2 1 0 >>uimm? ] unit-test

{ f } [ -1 12 imm-lower? ] unit-test
{ t } [ 0 12 imm-lower? ] unit-test
{ t } [ 0xfff 12 imm-lower? ] unit-test
{ f } [ 0x1000 12 imm-lower? ] unit-test

{ f } [ -1 12 imm-upper? ] unit-test
{ t } [ 0 12 imm-upper? ] unit-test
{ f } [ 0xfff 12 imm-upper? ] unit-test
{ t } [ 0x1000 12 imm-upper? ] unit-test
{ t } [ 0xfff000 12 imm-upper? ] unit-test
{ f } [ 0xfff001 12 imm-upper? ] unit-test
{ f } [ 0x1000000 12 imm-upper? ] unit-test

[ -1 split-imm ] [ immediate-range? ] must-fail-with
{ 0 0 } [ 0 split-imm ] unit-test
{ 0 0xfff } [ 0xfff split-imm ] unit-test
{ 1 1 } [ 0x1000 split-imm ] unit-test
{ 1 0xfff } [ 0xfff000 split-imm ] unit-test
[ 0xfff001 split-imm ] [ immediate-range? ] must-fail-with
[ 0xffffff split-imm ] [ immediate-range? ] must-fail-with
[ 0x1000000 split-imm ] [ immediate-range? ] must-fail-with

{ t } [ 0 arithmetic-immediate? ] unit-test
{ t } [ 0xfff arithmetic-immediate? ] unit-test
{ t } [ 0x1000 arithmetic-immediate? ] unit-test
{ t } [ 0xfff000 arithmetic-immediate? ] unit-test
{ f } [ 0xfff001 arithmetic-immediate? ] unit-test
{ f } [ 0x1000000 arithmetic-immediate? ] unit-test

[ 0 64 (encode-bitmask) ] [ bitmask-immediate? ] must-fail-with
[ 0 32 (encode-bitmask) ] [ bitmask-immediate? ] must-fail-with
[ -1 32 (encode-bitmask) ] [ bitmask-immediate? ] must-fail-with
[ -1 64 (encode-bitmask) ] [ bitmask-immediate? ] must-fail-with
[ 5 64 (encode-bitmask) ] [ bitmask-element? ] must-fail-with
{ 0 } [ 1 32 (encode-bitmask) ] unit-test
{ 0x1000 } [ 1 64 (encode-bitmask) ] unit-test

{ f } [ 0 logical-immediate? ] unit-test
{ f } [ 5 logical-immediate? ] unit-test
{ f } [ 64 on-bits logical-immediate? ] unit-test
{ t } [ 1 logical-immediate? ] unit-test

[ X0 X0 -257 [+] 0 [ ] [ ] LDRoff ] [ offset? ] must-fail-with

{ 2 } [ 2 ?extend-type ] unit-test
[ 0 ?extend-type ] [ extend-type? ] must-fail-with

{ 0 } [ 0 0 ?extend-amount ] unit-test
{ 0 } [ 0 1 ?extend-amount ] unit-test
[ 1 0 ?extend-amount ] [ extend-amount? ] must-fail-with
{ 1 } [ 1 1 ?extend-amount ] unit-test

: test-insn ( n quot -- ) [ 1array ] dip '[ _ { } make be> ] unit-test ;

! LD/STR pre/post: W/Xt Xn/SP simm9

0x657c40f8 [ X5 X3 7 [pre] LDR ] test-insn

0xfe0741f8 [ LR SP 16 [post] LDR ] test-insn

0xfe0f1ff8 [ LR SP -16 [pre] STR ] test-insn

0x6a8700f8 [ X10 X27 8 [post] STR ] test-insn

! LD/STR uoff: W/Xt Xn/SP uimm12/2+bw

0x880040b9 [ W8 X4 [] LDR ] test-insn
0x3ac340f8 [ X26 X25 12 [+] LDR ] test-insn

0x290300f9 [ X9 X25 [] STR ] test-insn
0x3b0b00f9 [ X27 X25 16 [+] STR ] test-insn

! LD/STR roff: W/Xt Xn/SP W/Xm 0/2+bw <EXT:x1x>

0x204862b8 [ W0 X1 W2 [+] LDR ] test-insn
0x207862f8 [ X0 X1 X2 3 <UXTX> [+] LDR ] test-insn

! LDR lit: W/Xt simm19/4

0x49000058 [ X9 2 LDR ] test-insn

! LD/STRB pre/post: Wt Xn/SP simm9

! LD/STRB uoff: Wt Xn/SP uimm12

0x4c000039 [ W12 X2 [] STRB ] test-insn

! LD/STRB roff: Wt Xn/SP W/Xm 0/1 <EXT:x1x>
0x29696a38 [ W9 X9 X10 [+] LDRB ] test-insn

! LD/STRH pre/post: Wt Xn/SP simm9

0xc9740078 [ W9 X6 7 [post] STRH ] test-insn

! LD/STRH uoff: Wt Xn/SP uimm12/2

! LD/STRH roff: Wt Xn/SP W/Xm 0/1 <EXT:x1x>

! LDRSB pre/post: W/Xt Xn/SP simm9

! LDRSB uoff: W/Xt Xn/SP uimm12

! LDRSB roff: W/Xt Xn/SP W/Xm 0/1 <EXT:x1x>

! LDRSH pre/post: W/Xt Xn/SP simm9

! LDRSH uoff: Wt Xn/SP uimm12/2

0x05108079 [ X5 X0 8 [+] LDRSH ] test-insn

! LDRSH roff: W/Xt Xn/SP W/Xm 0/1 <EXT:x1x>

! LDRSW pre/post: Xt Xn/SP simm9

! LDRSW uoff: Xt Xn/SP uimm12/4

! LDRSW roff: Xt Xn/SP W/Xm 0/2 <EXT:x1x>

! LDRSW lit: Xt simm19/4

! LDP pre/post

0xfd7bbfa9 [ X29 X30 SP -16 [pre] STP ] test-insn
0xfd7bc1a8 [ X29 X30 SP 16 [post] LDP ] test-insn

0x692340a9 [ X9 X8 X27 [] LDP ] test-insn
0x6aa77fa9 [ X10 X9 X27 -8 [+] LDP ] test-insn
0x4aa7ffa9 [ X10 X9 X26 -8 [pre] LDP ] test-insn
0x6183ffa8 [ X1 X0 X27 -8 [post] LDP ] test-insn

0x6a2700a9 [ X10 X9 X27 [] STP ] test-insn
0x692f3fa9 [ X9 X11 X27 -16 [+] STP ] test-insn
0x4aa780a9 [ X10 X9 X26 8 [pre] STP ] test-insn
0x6183bfa8 [ X1 X0 X27 -8 [post] STP ] test-insn

! Branch instructions

0x03000014 [ 3 Br ] test-insn
0xa0000054 [ 5 BEQ ] test-insn
0xa1000054 [ 5 BNE ] test-insn
0x67000054 [ 3 BVC ] test-insn
0x20011fd6 [ X9 BR ] test-insn
0xc0035fd6 [ RET ] test-insn
0x00000094 [ 0 BL ] test-insn
0x20013fd6 [ X9 BLR ] test-insn

0x490000b4 [ X9 2 CBZ ] test-insn
0x6a0000b5 [ X10 3 CBNZ ] test-insn
0x60ff3f36 [ W0 7 -5 TBZ ] test-insn
0x1f006837 [ WZR 13 0 TBNZ ] test-insn

0x00000010 [ X0 0 ADR ] test-insn
0x00000030 [ X0 1 ADR ] test-insn
0x902000b0 [ X16 0x411000 ADRP ] test-insn

0x10220091 [ X16 X16 8 ADD ] test-insn
0x2000028b [ X0 X1 X2 ADD ] test-insn
! 0x [ ADDS ]
0x5a0789cb [ X26 X26 X9 1 <ASR> SUB ] test-insn
0x630400f1 [ X3 X3 1 SUBS ] test-insn

[ X0 X0 X0 1 <ROR> ADD ] [ ROR-in-arithmetic-instruction? ] must-fail-with

! 0x [ ADC ]
! 0x [ ADCS ]
! 0x [ SBC ]
! 0x [ SBCS ]

0xe41305cb [ X4 X5 4 <LSL> NEG ] test-insn
! 0x [ NEGS ]
! 0x [ NGC ]
! 0x [ NGCS ]


! 0x [ AND ]
0x200840f2 [ X0 X1 7 ANDS ] test-insn
0xa43c72d2 [ X4 X5 0x3fffc000 EOR ] test-insn
! 0x [ ORR ] test-insn
0x6314248a [ X3 X3 X4 5 <LSL> BIC ] test-insn
! 0x [ BICS ]
! 0x [ EON ]
! 0x [ ORN ]
! 0x [ MVN ]

0xe00301aa [ X0 X1 MOV ] test-insn
0x7f000091 [ SP X3 MOV ] test-insn
0xe07f40b2 [ X0 0xffffffff MOV ] test-insn
0x80dbffd2 [ X0 0xfedc 48 MOVZ ] test-insn
0x2041d7f2 [ X0 0xba09 32 MOVK ] test-insn
0xa0ecb0f2 [ X0 0x8765 16 MOVK ] test-insn
0x206488f2 [ X0 0x4321 0 MOVK ] test-insn

0x2020c29a [ X0 X1 X2 LSL ] test-insn
0x6328c09a [ X3 X3 X0 ASR ] test-insn
0xa424c59a [ X4 X5 X5 LSR ] test-insn
0x002cc19a [ X0 X0 X1 ROR ] test-insn
0x290d7cd3 [ X9 X9 4 4 UBFIZ ] test-insn

0x207c029b [ X0 X1 X2 MUL ] test-insn
0x20fc029b [ X0 X1 X2 MNEG ] test-insn
0x200c029b [ X0 X1 X2 X3 MADD ] test-insn
0x208c029b [ X0 X1 X2 X3 MSUB ] test-insn

0x200cc29a [ X0 X1 X2 SDIV ] test-insn
0x2008c29a [ X0 X1 X2 UDIV ] test-insn

! 0x [ W0 W1 W3 SMULL ] test-insn
! 0x [ X0 W20 W21 X9 UMSUBL ] test-insn

! 0x [ X1 X1 X2 SMULH ] test-insn

0x5fc023ab [ X2 W3 0 <SXTW> CMN ] test-insn
0x1f8c0071 [ W0 35 CMP ] test-insn
0x3ff00172 [ W1 0xaaaaaaaa TST ] test-insn

0x20a0829a [ X0 X1 X2 GE CSEL ] test-insn
! 0x [ CSINC ]
! 0x [ CSINV ]
0x621484da [ X2 X3 X4 NE CSNEG ] test-insn
! 0x [ CINC ]
0xe980879a [ X9 X7 HI CINV ] test-insn
! 0x [ CNEG ]
0xe1179f9a [ X1 EQ CSET ] test-insn
! 0x [ CSETM ]

0x84485ffa [ X4 31 0b0100 MI CCMP ] test-insn
! 0x [ CCMN ]

0x0810c0da [ X8 X0 CLZ ] test-insn
0x8916c05a [ W9 W20 CLS ] test-insn

0x00423bd5 [ X0 NZCV MRS ] test-insn
0x00421bd5 [ NZCV X0 MSR ] test-insn
0x00443bd5 [ X0 FPCR MRS ] test-insn
0x3f441bd5 [ FPSR XZR MSR ] test-insn

0x010000d4 [ 0 SVC ] test-insn

0x1f2003d5 [ NOP ] test-insn

0xa07935d4 [ 0xabcd BRK ] test-insn
0x201cc0da [ X0 X1 CNT ] test-insn
0x804642d4 [ 0x1234 HLT ] test-insn

! FP

USE: multiline
/*
0x [ FMOVgen ]
0x [ FCVT ]
0x [ FCVTZSsi ]
0x [ SCVTFsi ]
0x [ FSQRTs ]
0x [ FADDs ]
0x [ FSUBs ]
0x [ FMULs ]
0x [ FDIVs ]
0x [ FMAXs ]
0x [ FMINs ]

0x [ S5 X0 [] LDR ] test-insn
0x [ D4 X3 8 [post] STR ] test-insn
0x [ S0 X1 4 [pre] STR ] test-insn

0x [ D3 D4 FMOV ] test-insn
0x [ S5 S12 FMOV ] test-insn

0x [ D3 5.0 FMOV ] test-insn
0x [ S5 7.0 FMOV ] test-insn

0x [ S0 D0 FCVT ] test-insn
0x [ D1 S1 FCVT ] test-insn

0x [ D5 X7 FCVTAS ] test-insn
0x [ D0 W4 FCVTPU ] test-insn
0x [ S0 X7 FCVTAS ] test-insn
0x [ X3 D0 UCVTF ] test-insn

0x [ S0 W4 4 FCVTZU ] test-insn
0x [ W3 S1 8 SCVTF ] test-insn

0x [ D3 D5 FRINTA ] test-insn
0x [ S15 S15 FRINTM ] test-insn

0x [ D3 D5 FABS ] test-insn
0x [ S15 S15 FNEG ] test-insn
0x [ X0 X0 FSQRT ]

0x [ D0 D1 D2 FADD ] test-insn
0x [ S0 S1 S2 FADD ] test-insn
0x [ S10 S10 S14 FNMUL ] test-insn
0x [ D0 D7 D8 FDIV ] test-insn

0x [ S1 S6 S8 S1 FMADD ] test-insn
0x [ D0 D4 D5 D0 FMADD ] test-insn

0x [ D0 D1 D2 FMIN ] test-insn
0x [ S0 S1 S2 FMAXNM ] test-insn

0x [ S0 S1 FCMP ] test-insn

0x [ S0 S1 S2 GE FCSEL ] test-insn
*/
