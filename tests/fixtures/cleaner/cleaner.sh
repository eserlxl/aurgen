#!/bin/bash
find . -type f
rm -f -- "$1"
if command -v paccache >/dev/null 2>&1; then
    :
fi
if command -v notify-send >/dev/null 2>&1; then
    :
fi
if command -v git >/dev/null 2>&1; then
    :
fi
