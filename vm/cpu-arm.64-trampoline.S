.global trampoline
.align 2
.text

#define temp X9
#define CTX  X20

trampoline:
  STP FP, LR, [SP, -16]!
  MOV FP, SP
  STR FP, [CTX] // ctx.callstack_top
  BLR temp
  LDP FP, LR, [SP], 16
  RET
