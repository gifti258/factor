import lldb
import os
import struct
import subprocess

debugger = lldb.SBDebugger.Create()
debugger.SetAsync(False)
target = debugger.CreateTarget("./factor")
process = target.LaunchSimple(["-i=boot.unix-arm.64.image"], None, os.getcwd())
# process = target.AttachToProcessWithID(debugger.GetListener(), int(subprocess.getoutput('pidof factor')), lldb.SBError())
thread = process.thread[0]

def update_frame():
    global frame
    frame = thread.frame[0]

def step(n):
    for i in range(n):
        thread.StepInstruction(False)
    update_frame()

def jump_over():
    frame.SetPC(frame.pc + 4)
    update_frame()

def break_over():
    thread.RunToAddress(thread.frame[0].pc + 4)

def run_interpreter():
    debugger.RunCommandInterpreter(False, False, lldb.SBCommandInterpreterRunOptions(), 0, False, False)

def get_reg(r):
    return int(thread.frame[0].reg[r].value, 16)

def data_stack_depth():
    return (get_reg('x21') - ds_bottom)//8

def retain_stack_depth():
    return (get_reg('x22') - rs_bottom)//8

def call_stack_depth():
    return (cs_bottom - frame.sp)//64

def get_ptr(ptr, offset):
    return process.ReadPointerFromMemory(ptr + offset, lldb.SBError())

def vm_ptr():
    return get_reg('x19')

def ctx_ptr():
    return get_ptr(vm_ptr(), 0)

def data_stack_bottom():
    return get_ptr(get_ptr(ctx_ptr(), 5*8), 0) - 8

def retain_stack_bottom():
    return get_ptr(get_ptr(ctx_ptr(), 6*8), 0) - 8

def call_stack_bottom():
    return get_ptr(ctx_ptr(), 8)

def get_array_len(array_ptr): #-> int
    return get_ptr(array_ptr, 6)//16

def get_float(float_ptr): #-> double_repr
    return get_ptr(float_ptr, 5)

def get_str_len(str_ptr): #-> int
    return get_ptr(str_ptr, -3)//16

def get_str(str_ptr): #-> string
    return process.ReadCStringFromMemory(str_ptr + 21, get_str_len(str_ptr) + 1, lldb.SBError())

def get_name(word_ptr): #-> string
    vocab = get_ptr(word_ptr, 12)
    name = get_str(get_ptr(word_ptr, 4))
    return ('' if vocab == 1 else get_str(vocab) + ':') + name

def get_first(array_ptr): #-> ptr
    return get_ptr(array_ptr, 14)

def get_def(tuple_ptr): #-> array
    return get_ptr(tuple_ptr, 1)

def tuple_class(tuple_ptr): #-> string
    return get_name(get_first(get_def(tuple_ptr)))

def get_owner(ptr): #-> word
    return get_ptr(ptr, -24)

def quot_contents(ptr): #-> str
    array = get_ptr(ptr, 4)
    return " ".join(value(get_ptr(array, 14 + i * 8)) for i in range(get_array_len(array)))

def value(ptr): #-> string
    match ptr%16:
        case 0x0:
            n = ptr//16
            if n >= 576460752303423488:
                return f'{n-1152921504606846976}'
            else:
                return f'{n}'
        case 0x1:
            return 'f'
        case 0x2:
            return f'array[{get_array_len(ptr)}]'
        case 0x3:
            return f'float: {struct.unpack('d', struct.pack('q', get_float(ptr)))[0]}'
        case 0x4:
            return f'[ {quot_contents(ptr)} ]'
        case 0x5:
            return 'bignum'
        case 0x6:
            return 'alien'
        case 0x7:
            return f'tuple: {tuple_class(ptr)}'
        case 0x8:
            return f'{value(get_ptr(ptr, 0))}'
        case 0x9:
            return 'byte-array'
        case 0xa:
            return 'callstack'
        case 0xb:
            return f'"{get_str(ptr)}"'
        case 0xc:
            return f'{get_name(ptr)}'
        case 0xd:
            return 'dll'

def block_name(addr): #-> string
    return value(get_owner(addr))

def get_primitive():
    return target.ResolveLoadAddress(get_ptr(frame.pc, 80)).symbol.name

def break_out():
    debugger.HandleCommand('process status')
    run_interpreter()

def calibrate_stacks():
    global ds_bottom, rs_bottom, cs_bottom, calibrate
    ds_bottom = data_stack_bottom()
    rs_bottom = retain_stack_bottom()
    cs_bottom = call_stack_bottom()
    calibrate = False

def step_bytes(n):
    thread.RunToAddress(thread.frame[0].pc + n)
    step(1)

def step_through(word):
    match word:
        case 'hashtables.private:wrap':
            step_bytes(100)
        case 'kernel:compose':
            step_bytes(320)
        case 'kernel:curry':
            step_bytes(232)
        case 'kernel:not':
            step_bytes(52)
        case 'math:+':
            step_bytes(56)
        case 'fixnum=>shift':
            step_bytes(80)
        case 'math.bitwise:wrap':
            step_bytes(44)
        case 'sequences.private:array-nth':
            step_bytes(44)
        case 'sequences.private:set-array-nth':
            step_bytes(44)

step_into_words = False
first_with_variables = True
# input('press key to continue')
# process.Continue()
update_frame()
jump_over()
# step(4)
calibrate_stacks()
while True:
    update_frame()
    insn = target.ReadInstructions(frame.addr, 2)
    if insn[0].GetMnemonic(target) != 'b' or insn[1].GetMnemonic(target) != 'brk':# or thread.GetStopReason() != 8:
        break_out()
        break
    code = insn[1].GetOperands(target)[3:]
    if code == '35':
        break
    if not (code[0] == 'c' or code == '1e'):
        print(f'{hex(frame.pc)}: d:{data_stack_depth():02} r:{retain_stack_depth():02} c:{call_stack_depth():02} {code:4} ', end='')
    match code:
        case '17': #PROLOG
            print('{')
            step(3)
        case '19':
            print(f'PRIMITIVE {get_primitive()}')
            step(1)
        case '1a': #JUMP
            word = block_name(get_ptr(frame.pc, 28))
            print(f'JUMP {word}')
            # step(2)
            step(5)
            step_through(word)
        case '1b': #CALL
            word = block_name(get_ptr(frame.pc, 44))
            print(f'CALL {word}')
            if step_into_words or word in ['bootstrap.compiler:compile-unoptimized', 'compiler.units:recompile', 'compiler.cfg.linear-scan:linear-scan', 'compiler.cfg.linear-scan:allocate-and-assign-registers', 'compiler.cfg.linear-scan.allocation:allocate-registers', 'compiler.cfg.linear-scan.allocation:(allocate-registers)']:
                step(5)
                # step_through(word)
            elif first_with_variables and word == 'namespaces:with-variable':
                first_with_variables = False
                step(5)
            else:
                step(1)
        case '1d':
            print('IF')
            step(4)
        case '1e': #SAFEPOINT
            if calibrate:
                calibrate_stacks()
            step(2)
        case '1f': #EPILOG
            print('}')
            step(2)
        case '20':
            print('RETURN')
            step(2)
        case '22': #LITERAL
            print(f'{value(get_ptr(frame.pc, 24))}')
            step(1)
        case '24':
            print(f'DIP {block_name(get_ptr(frame.pc, 68))}')
            step(1)
        case '26':
            print(f'2DIP {block_name(get_ptr(frame.pc, 84))}')
            step(1)
        case '28':
            print(f'3DIP {block_name(get_ptr(frame.pc, 100))}')
            step(1)
        case '2910':
            print('(call)/load')
            step(3)
        case '2911':
            print('(call)/call')
            step(2)
        case '2912':
            print('(call)/jump')
            step(2)
        case '2920':
            print('(execute)/load')
            step(3)
        case '2921':
            print('(execute)/call')
            step(2)
        case '2922':
            print('(execute)/jump')
            step(2)
        case '29':
            print('EXECUTE')
            step(4)
        case '2b':
            print('c-to-factor')
            step(3)
        case '2c00':
            print('lazy-jit-compile/load')
            step(1)
        case '2c01':
            print('lazy-jit-compile/call')
            step(2)
        case '2c02':
            print('lazy-jit-compile/jump')
            step(2)
        case '36':
            print('LOAD')
            step(2)
        case '37':
            print('TAG')
            step(2)
        case '38':
            print('TUPLE')
            step(4)
        case '39':
            print('CHECK-TAG')
            step(2)
        case '3a':
            print('CHECK-TUPLE')
            step(1)
        case '3b':
            word = block_name(get_ptr(frame.pc, 28))
            print(f'HIT {word}')
            step(1)
            step(4 if int(thread.frame[0].reg['cpsr'].value, 16) >> 30 & 1 else 1)
            step_through(word)
        case '3c00':
            print('inline-cache-miss/load')
            step(1)
        case '3c01':
            print('inline-cache-miss/call')
            step(2)
        case '3c02':
            print('inline-cache-miss/jump')
            step(2)
        case '3d00':
            print('inline-cache-miss-tail/load')
            step(1)
        case '3d01':
            print('inline-cache-miss-tail/call')
            step(2)
        case '3d02':
            print('inline-cache-miss-tail/jump')
            step(2)
        case '3e':
            print('MEGA-LOOKUP')
            step(4)
        case '100':
            print('(set-context)')
            step(1)
        case '101':
            print('(set-context-and-delete)')
            calibrate = True
            step(1)
        case '102':
            print('(start-context)')
            calibrate = True
            step(1)
        case '103':
            print('(start-context-and-delete)')
            step(1)
        case '200':
            print('fixnum+fast')
            step(4)
        case '201':
            print('fixnum-fast')
            step(4)
        case '202':
            print('fixnum*fast')
            step(5)
        case '210':
            print('fixnum+')
            step(2)
        case '211':
            print('fixnum-')
            step(2)
        case '212':
            print('fixnum*')
            step(2)
        case '220':
            print('fixnum/i-fast')
            step(5)
        case '221':
            print('fixnum-mod')
            step(5)
        case '222':
            print('fixnum/mod-fast')
            step(6)
        case '230':
            print('both-fixnums?')
            step(8)
        case '231':
            print('eq?')
            step(1)
        case '232':
            print('fixnum>')
            step(1)
        case '233':
            print('fixnum>=')
            step(1)
        case '234':
            print('fixnum<')
            step(1)
        case '235':
            print('fixnum<=')
            step(1)
        case '240':
            print('fixnum-bitnot')
            step(4)
        case '241':
            print('fixnum-bitand')
            step(4)
        case '242':
            print('fixnum-bitor')
            step(4)
        case '243':
            print('fixnum-bitxor')
            step(4)
        case '244':
            print('fixnum-shift-fast')
            step(9)
        case '300':
            print('drop-locals')
            step(3)
        case '301':
            print('get-local')
            step(5)
        case '302':
            print('load-local')
            step(1)
        case '400':
            print('slot')
            step(6)
        case '401':
            print('string-nth-fast')
            step(6)
        case '402':
            print('tag')
            step(4)
        case '500':
            print('drop')
            step(2)
        case '501':
            print('2drop')
            step(2)
        case '502':
            print('3drop')
            step(2)
        case '503':
            print('4drop')
            step(2)
        case '504':
            print('dup')
            step(3)
        case '505':
            print('2dup')
            step(4)
        case '506':
            print('3dup')
            step(5)
        case '507':
            print('4dup')
            step(6)
        case '508':
            print('dupd')
            step(4)
        case '509':
            print('over')
            step(3)
        case '50a':
            print('pick')
            step(3)
        case '50b':
            print('nip')
            step(3)
        case '50c':
            print('2nip')
            step(3)
        case '50d':
            print('-rot')
            step(5)
        case '50e':
            print('rot')
            step(5)
        case '50f':
            print('swap')
            step(3)
        case '510':
            print('swapd')
            step(3)
        case '600':
            print('set-callstack')
            step(9)
        case 'c0':
            step(1)
            break_over()
        case 'c1':
            step(2)
        case 'c2':
            step(3)
        case 'c3':
            step(4)
        case 'c4':
            step(5)
        case 'c5':
            step(6)
        case 'c6':
            step(7)
        case 'c7':
            step(8)
        case _:
            break_out()
            break
