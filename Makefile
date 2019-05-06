all : 0_no_protection 1_nx_stack 2_stack_canaries 1_nx_stack_win

0_no_protection: bof.c Makefile
	gcc -m32 -fno-stack-protector -z execstack -no-pie -z norelro -mpreferred-stack-boundary=2 -o $@ $<

1_nx_stack : bof.c Makefile
	gcc -m32 -fno-stack-protector -no-pie -z norelro -mpreferred-stack-boundary=2 -o $@ $<

1_nx_stack_win : win.c Makefile
	gcc -m32 -fno-stack-protector -no-pie -z norelro -mpreferred-stack-boundary=2 -o $@ $<

2_stack_canaries : bof.c Makefile
	gcc -m32 -no-pie -z norelro -mpreferred-stack-boundary=2 -o $@ $<
