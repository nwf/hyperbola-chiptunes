CPU_CPP_NAME=__AVR_ATmega168__
CPU_CC_NAME=atmega168
CPU_LD_NAME=avr4
	# Be sure to also adjust the values in target/script.ld
	
CPU_FREQUENCY=20000000
SAMPLE_RATE=16000

tracker/%: CPPFLAGS=-I.
tracker/%: LDFLAGS=-lSDL -lncurses
tracker/%: CFLAGS=-Wall -Wextra -Werror
tracker/%: CC=gcc

target/%: CPPFLAGS=-I. -D${CPU_CPP_NAME}
target/%: CFLAGS=-O2 -g -B/usr/avr/lib -Wall -Wextra -Werror -mmcu=${CPU_CC_NAME} \
			-Wl,-T -Wl,target/script.ld
target/%: ASFLAGS=-mmcu=${CPU_CC_NAME}
target/%: LDFLAGS=-M -T target/script.ld -m ${CPU_LD_NAME} 
target/%: CC=avr-gcc
target/%: LD=avr-ld
target/%: AS=avr-as

all:	tracker/tracker target/test2.hex

progenv/gentimes.c: progenv/gentimes.pl
	perl $^ --mode=C --fcpu=${CPU_FREQUENCY} --samprate=${SAMPLE_RATE} > $@

progenv/gentimes.h: progenv/gentimes.pl
	perl $^ --mode=H --fcpu=${CPU_FREQUENCY} --samprate=${SAMPLE_RATE} > $@

#progenv/trackerfmt.ph: progenv/trackerfmt.h
#	h2ph -d . $^

progenv/gentimes.o: progenv/gentimes.h

songs/%.s : songs/%.song | progenv/tracker_optimize.pl
	perl progenv/tracker_optimize.pl --optimize --packout=songs/$*.s --packver=1 < $^

    # For use with e.g. "play --rate 16000 -b8 -L -c1 -e un -t raw"
songs/%.raw : songs/%.song | tracker/tracker
	tracker/tracker --audio $^ $@

tracker/chip.o: progenv/gentimes.h

tracker/tracker: tracker/main.o tracker/chip.o tracker/gui.o progenv/gentimes.o
	${CC} ${CPPFLAGS} ${CFLAGS} ${LDFLAGS} -o $@ $^ 

target/%.o: target/main.c target/hyperbola.c target/asm.S songs/%.s progenv/gentimes.c target/config.h | progenv/gentimes.h
	${CC} ${CPPFLAGS} ${CFLAGS} -funit-at-a-time --combine -o $@ $^

target/%.hex: target/%.o
	${LD} ${LDFLAGS} --oformat ihex -o $@ $^ > target/mapfile

target/%.da: target/%.o
	avr-objdump -S $^ > $@

clean:
	rm -f songs/*.s songs/*.raw
	rm -f tracker/*.o tracker/tracker
	rm -f target/*.o target/mapfile target/*.hex
	rm -f progenv/gentimes.[ch]
