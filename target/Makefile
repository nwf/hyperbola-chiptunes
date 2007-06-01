all:		flash.hex

flash.o:	main.c asm.s ../tracker/exported.s
		avr-gcc -Xlinker -Tdata -Xlinker 0x800160 -Xlinker -M -O2 -B/usr/avr/lib -I/usr/local/avr/include -Wall -mmcu=avr4 -D__AVR_ATmega88__ -o $@ $^ >mapfile

flash.hex:	flash.o
		avr-ld --oformat ihex -o $@ $^
