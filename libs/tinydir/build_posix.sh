#!/bin/bash
gcc -O3 -c tinydir.c -o tinydir.o
ar rcs libtinydir.a tinydir.o
