#!/bin/bash
gcc -O3 -c coro.c -o coro.o 
ar rcs libcoro.a coro.o
