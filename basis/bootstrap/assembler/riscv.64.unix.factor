! Copyright (C) 2024 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: kernel parser sequences ;
IN: bootstrap.assembler.riscv

<< "resource:basis/bootstrap/assembler/riscv.unix.factor" parse-file suffix! >> call
<< "resource:basis/bootstrap/assembler/riscv.64.factor" parse-file suffix! >> call
<< "resource:basis/bootstrap/assembler/riscv.factor" parse-file suffix! >> call
