namespace factor {

inline static cell callstack_object_size(cell size) {
  return sizeof(callstack) + size;
}

// This is a little tricky. The iterator may allocate memory, so we
// keep the callstack in a GC root and use relative offsets
// Allocates memory
template <typename Iterator, typename Fixup>
inline void factor_vm::iterate_callstack_object(callstack* stack_,
                                                Iterator& iterator,
                                                Fixup& fixup) {
  data_root<callstack> stack(stack_, this);
  fixnum stack_offset = 0;

#ifdef FACTOR_ARM64
  while (*reinterpret_cast<cell*>(stack->frame_top_at(stack_offset)) != 0) {
    cell frame_top = stack->frame_top_at(stack_offset);
    cell addr = *reinterpret_cast<cell*>(frame_top + FRAME_RETURN_ADDRESS);
    cell fixed_addr = Fixup::translated_code_block_map
                          ? reinterpret_cast<cell>(fixup.translate_code(reinterpret_cast<code_block*>(addr)))
                          : addr;
    code_block* owner = code->code_block_for_address(fixed_addr);

    cell frame_size = *reinterpret_cast<cell*>(frame_top);

    iterator(frame_top, frame_size, owner, fixed_addr);
    stack_offset += frame_size;
  }
#else
  fixnum stack_length = untag_fixnum(stack->length);
  while (stack_offset < stack_length) {
    cell frame_top = stack->frame_top_at(stack_offset);
    cell addr = *reinterpret_cast<cell*>(frame_top);
    cell fixed_addr = Fixup::translated_code_block_map
                          ? reinterpret_cast<cell>(fixup.translate_code(reinterpret_cast<code_block*>(addr)))
                          : addr;
    code_block* owner = code->code_block_for_address(fixed_addr);

    cell frame_size = owner->stack_frame_size_for_address(fixed_addr);

    iterator(frame_top, frame_size, owner, fixed_addr);
    stack_offset += frame_size;
  }
  FACTOR_ASSERT(stack_offset == stack_length);
#endif
}

// Allocates memory
template <typename Iterator>
inline void factor_vm::iterate_callstack_object(callstack* stack,
                                                Iterator& iterator) {
  no_fixup none;
  iterate_callstack_object(stack, iterator, none);
}

// Iterates the callstack from innermost to outermost
// callframe. Allocates memory
template <typename Iterator, typename Fixup>
void factor_vm::iterate_callstack(context* target_ctx, Iterator& iterator,
                                  Fixup& fixup) {

  cell top = target_ctx->callstack_top;
  cell bottom = target_ctx->callstack_bottom;
  // When we are translating the code block maps, all callstacks must
  // be empty.
  FACTOR_ASSERT(!Fixup::translated_code_block_map || top == bottom);

#ifdef FACTOR_ARM64
  (void)bottom;
  while (*reinterpret_cast<cell*>(top) != 0) {
    cell addr = *reinterpret_cast<cell*>(top + FRAME_RETURN_ADDRESS);
    FACTOR_ASSERT(addr != 0);

    // Only the address is valid, if the code heap has been compacted,
    // owner might not point to a real code block.
    code_block* owner = code->code_block_for_address(addr);
    fixup.translate_code(owner);
    cell size = *reinterpret_cast<cell*>(top) - top;

    iterator(top, size, owner, addr);
    top = *reinterpret_cast<cell*>(top);
  }
#else
  while (top < bottom) {
    cell addr = *reinterpret_cast<cell*>(top);
    FACTOR_ASSERT(addr != 0);

    // Only the address is valid, if the code heap has been compacted,
    // owner might not point to a real code block.
    code_block* owner = code->code_block_for_address(addr);
    code_block* fixed_owner = fixup.translate_code(owner);

    cell delta = addr - (cell)owner - sizeof(code_block);
    cell natural_frame_size = fixed_owner->stack_frame_size();
    cell size = LEAF_FRAME_SIZE;
    if (natural_frame_size > 0 && delta > 0)
      size = natural_frame_size;

    iterator(top, size, owner, addr);
    top += size;
  }
  FACTOR_ASSERT(top == bottom);
#endif
}

// Allocates memory
template <typename Iterator>
inline void factor_vm::iterate_callstack(context* target_ctx, Iterator& iterator) {
  no_fixup none;
  iterate_callstack(target_ctx, iterator, none);
}

}
