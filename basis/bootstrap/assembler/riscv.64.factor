! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: cpu.riscv.assembler layouts namespaces ;
IN: bootstrap.assembler.riscv

8 \ cell set

CONSTANT: cell-shift-bits 3

: sc ( rs1 rs2 imm -- ) sd ;
