CPU_CPP_NAME=__AVR_ATmega88__
CPU_CC_NAME=avr4
CPU_LD_NAME=avr4
CPU_FREQUENCY=20000000
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

all:	tracker/tracker target/test2.hex

progenv/gentimes.c: progenv/gentimes.pl
	perl $^ --mode=C --fcpu=${CPU_FREQUENCY} --samprate=${SAMPLE_RATE} > $@

progenv/gentimes.h: progenv/gentimes.pl
	perl $^ --mode=H --fcpu=${CPU_FREQUENCY} --samprate=${SAMPLE_RATE} > $@

progenv/gentimes.o: progenv/gentimes.h

.INTERMEDIATE: songs/%.h
songs/%.s songs/%.h : songs/%.song | tracker/tracker
	tracker/tracker --export $^ songs/$*

tracker/chip.o: progenv/gentimes.h

tracker/tracker: tracker/main.o tracker/chip.o tracker/gui.o progenv/gentimes.o
	${CC} ${CPPFLAGS} ${CFLAGS} ${LDFLAGS} -o $@ $^ 

target/%.o: target/main.c target/asm.S songs/%.s progenv/gentimes.c | progenv/gentimes.h songs/%.h 
	${CC} ${CPPFLAGS} ${CFLAGS} --include="songs/$*.h" -o $@ $^

target/%.hex: target/%.o
	${LD} ${LDFLAGS} --oformat ihex -o $@ $^ > target/mapfile

target/%.da: target/%.o
	avr-objdump -S $^ > $@

clean:
	rm -f songs/*.s songs/*.h
	rm -f tracker/*.o tracker/tracker
	rm -f target/*.o target/mapfile target/*.hex
	rm -f progenv/gentimes.[ch]
