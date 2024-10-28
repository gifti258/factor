#include "master.hpp"

namespace factor {

instruction_operand::instruction_operand(relocation_entry rel,
                                         code_block* compiled, cell index)
    : rel(rel),
      compiled(compiled),
      index(index),
      pointer(compiled->entry_point() + rel.offset()) {}

// Load a value from a bitfield of a PowerPC instruction
fixnum instruction_operand::load_value_masked(cell mask, cell preshift,
                                              cell bits, cell postshift) {
  int32_t* ptr = (int32_t*)(pointer - sizeof(uint32_t));

  return ((((*ptr & (int32_t)mask) >> preshift ) << bits) >> bits) << postshift;
}

fixnum instruction_operand::load_value(cell relative_to) {
  switch (rel.klass()) {
    case RC_ABSOLUTE_CELL:
      return *(cell*)(pointer - sizeof(cell));
    case RC_ABSOLUTE:
      return *(uint32_t*)(pointer - sizeof(uint32_t));
    case RC_ABSOLUTE_2:
      return *(uint16_t*)(pointer - sizeof(uint16_t));
    case RC_ABSOLUTE_1:
      return *(uint8_t*)(pointer - sizeof(uint8_t));
    case RC_RELATIVE:
      return *(int32_t*)(pointer - sizeof(uint32_t)) + relative_to;
    case RC_RELATIVE_ARM_B:
      return load_value_masked(rel_arm_b_mask, 0, 4, 2) + relative_to - 4;
    case RC_RELATIVE_ARM_B_COND:
      return load_value_masked(rel_arm_b_mask, 3, 11, 0) + relative_to - 4;
    case RC_RELATIVE_ARM_LDR:
      return load_value_masked(rel_arm_ldr_cmp_mask, 7, 17, 0) + relative_to - 4;
    case RC_ABSOLUTE_ARM_LDR:
      return load_value_masked(rel_arm_ldr_cmp_mask, 7, 17, 0);
    case RC_ABSOLUTE_ARM_CMP:
      return load_value_masked(rel_arm_ldr_cmp_mask, 10, 20, 0);
    default:
      critical_error("Bad rel class", rel.klass());
      return 0;
  }
}

code_block* instruction_operand::load_code_block() {
  return ((code_block*)load_value(pointer) - 1);
}

// Store a value into a bitfield of a PowerPC or ARM instruction
void instruction_operand::store_value_masked(fixnum value, cell mask,
                                             cell shift1, cell shift2) {
  uint32_t* ptr = (uint32_t*)(pointer - sizeof(uint32_t));
  *ptr = (uint32_t)((*ptr & ~mask) | ((value >> shift1 << shift2) & mask));
}

void instruction_operand::store_value(fixnum absolute_value) {
  fixnum relative_value = absolute_value - pointer;

  switch (rel.klass()) {
    case RC_ABSOLUTE_CELL:
      *(cell*)(pointer - sizeof(cell)) = absolute_value;
      break;
    case RC_ABSOLUTE:
      *(uint32_t*)(pointer - sizeof(uint32_t)) = (uint32_t)absolute_value;
      break;
    case RC_ABSOLUTE_2:
      *(uint16_t*)(pointer - sizeof(uint16_t)) = (uint16_t)absolute_value;
      break;
    case RC_ABSOLUTE_1:
      *(uint8_t*)(pointer - sizeof(uint8_t)) = (uint8_t)absolute_value;
      break;
    case RC_RELATIVE:
      *(int32_t*)(pointer - sizeof(int32_t)) = (int32_t)relative_value;
      break;
    case RC_RELATIVE_ARM_B:
      store_value_masked(relative_value + 4, rel_arm_b_mask, 2, 0);
      break;
    case RC_RELATIVE_ARM_B_COND:
      store_value_masked(relative_value + 4, rel_arm_b_cond_mask, 2, 5);
      break;
    case RC_RELATIVE_ARM_LDR:
      store_value_masked(relative_value + 4, rel_arm_ldr_cmp_mask, 3, 10);
      break;
    case RC_ABSOLUTE_ARM_LDR:
      store_value_masked(absolute_value, rel_arm_ldr_cmp_mask, 3, 10);
      break;
    case RC_ABSOLUTE_ARM_CMP:
      store_value_masked(absolute_value, rel_arm_ldr_cmp_mask, 0, 10);
      break;
    default:
      critical_error("Bad rel class", rel.klass());
      break;
  }
}

}
