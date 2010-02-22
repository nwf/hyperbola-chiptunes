CPU_CPP_NAME=__AVR_ATmega88__
CPU_CC_NAME=avr4
CPU_LD_NAME=avr4
CPU_FREQUENCY=2000000
SAMPLE_RATE=16000

tracker/%: CPPFLAGS=-I.
tracker/%: LDFLAGS=-lSDL -lncurses
tracker/%: CFLAGS=-Wall
tracker/%: CC=gcc

target/%: CPPFLAGS=-I. -D${CPU_CPP_NAME}
target/%: CFLAGS=-O2 -g -B/usr/avr/lib -Wall -mmcu=${CPU_CC_NAME}
target/%: ASFLAGS=-mmcu=${CPU_CC_NAME}
target/%: LDFLAGS=-Tdata 0x800160 -M -m ${CPU_LD_NAME}
target/%: CC=avr-gcc
target/%: LD=avr-ld
target/%: AS=avr-as

all:	tracker/tracker target/flash.hex

progenv/gentimes.c: progenv/gentimes.pl
	perl $^ --mode=C --fcpu=${CPU_FREQUENCY} --samprate=${SAMPLE_RATE} > $@

progenv/gentimes.h: progenv/gentimes.pl
	perl $^ --mode=H --fcpu=${CPU_FREQUENCY} --samprate=${SAMPLE_RATE} > $@

tracker/chip.o: progenv/gentimes.h
target/flash.o: progenv/gentimes.h
progenv/gentimes.o: progenv/gentimes.h

tracker/tracker: tracker/main.o tracker/chip.o tracker/gui.o progenv/gentimes.o
	${CC} ${CPPFLAGS} ${CFLAGS} ${LDFLAGS} -o $@ $^ 

target/flash.o: target/main.c target/asm.S tracker/exported.s progenv/gentimes.c
	${CC} ${CPPFLAGS} ${CFLAGS} -o $@ $^

target/flash.hex: target/flash.o
	${LD} ${LDFLAGS} --oformat ihex -o $@ $^ > target/mapfile

target/flash.da: target/flash.o
	avr-objdump -S target/flash.o > target/flash.da

clean:
	rm -f tracker/*.o tracker/tracker
	rm -f target/*.o target/mapfile target/flash.*
	rm -f progenv/gentimes.[ch]
