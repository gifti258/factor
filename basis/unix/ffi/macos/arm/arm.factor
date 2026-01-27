! Copyright (C) 2026 Giftpflanze.
! See https://factorcode.org/license.txt for BSD license.
USING: alien.c-types classes.struct unix.types ;
IN: unix.ffi

STRUCT: dirent
    { d_ino __uint64_t }
    { d_seekoff __uint64_t }
    { d_reclen __uint16_t }
    { d_namlen __uint16_t }
    { d_type __uint8_t }
    { d_name { char __DARWIN_MAXPATHLEN } } ;
