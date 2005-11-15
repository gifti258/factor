! Copyright (C) 2005 Slava Pestov.
! See http://factor.sf.net/license.txt for BSD license.
IN: gadgets
USING: arrays alien gadgets-layouts generic kernel lists math
namespaces sdl sequences strings freetype opengl ;

M: object handle-event ( event -- )
    drop ;

M: button-down-event handle-event ( event -- )
    update-clicked
    button-event-button dup
    hand get hand-buttons push
    [ button-down ] button-gesture ;

M: button-up-event handle-event ( event -- )
    button-event-button dup
    hand get hand-buttons delete
    [ button-up ] button-gesture ;

: motion-event-loc ( event -- loc )
    dup motion-event-x swap motion-event-y 0 3array ;

M: motion-event handle-event ( event -- )
    motion-event-loc move-hand ;

M: key-down-event handle-event ( event -- )
    dup keyboard-event>binding
    hand get hand-focus handle-gesture [
        keyboard-event-unicode dup control? [
            drop
        ] [
            hand get hand-focus user-input drop
        ] if
    ] [
        drop
    ] if ;

M: quit-event handle-event ( event -- )
    drop stop-world ;

M: resize-event handle-event ( event -- )
    flush-fonts
    gl-resize
    width get height get 0 3array world get set-gadget-dim ;
