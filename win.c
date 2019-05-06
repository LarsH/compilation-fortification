#include <string.h>
#include <stdlib.h>

void win(void) {
	system("/bin/bash");
}

int main(int argc, char**argv) {
	char buf[16];
	strcpy(buf, argv[1]);
	return 0;
}
