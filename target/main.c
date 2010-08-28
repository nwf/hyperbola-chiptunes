#include <stddef.h>

#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <avr/wdt.h>

#include <progenv/types.h>
#include <progenv/gentimes.h>
#include <progenv/trackerfmt.h>
#include <target/config.h>

volatile u8 callbackwait;
volatile u8 lastsample;

volatile u8 timetoplay;

volatile u8 test;

u8 trackwait;
u8 trackpos;
u8 playsong;
u8 songpos;
u8 songlen;

u32 noiseseed = 1;

u8 light[2];


/* The layout of this structure is known to assembler */
volatile struct oscillator {
	u16	freq;
	u16	phase;
	u16	duty;
	u8	waveform;
	u8	volume;	// 0-255
} osc[NR_CHAN];

struct unpacker {
	u8*	nextbyte;
	u8	buffer;
	u8	bits;
		// XXX RAMPACKS
		// 0x80 : PGM(1) vs RAM(0)
		// 0x07 : bits remaining in buffer
};

enum {
		CF_TRACK_FINISHED   = 0x01,
		CF_OFFSONG_STOP  = 0x02,
				// if tnum = 0, song is also off-track
		CF_OFFSONG_LOOP  = 0x04,
	// 0x08
		// 0x10
		// 0x20
		// 0x40
		// 0x80
};

struct channel {
	struct unpacker		trackup;
	u8			flags;
	u8			tnum;
	s8			transp;
	u8			tnote;
	u8*			ilast;
	u8*			iptr;
	u8			ioff;
	u8			iwait;
	u8			inote;
	s8			bendd;
	s16			bend;
	s8			volumed;
	s16			dutyd;
	u8			vdepth;
	u8			vrate;
	u8			vpos;
	s16			inertia;
	u16			slur;
} channel[NR_CHAN];

struct unpacker songup;

extern u8* itab[] __ATTR_PROGMEM__;
extern u8* ttab[] __ATTR_PROGMEM__;
extern u8 songdata[] __ATTR_PROGMEM__;

/* This is the AVR-LIBC standard dance for disabling the WDT */
    static uint8_t mcusr_mirror __attribute__ ((section (".noinit")));

    void get_mcusr(void) \
      __attribute__((naked)) \
      __attribute__((section(".init3")));
    void get_mcusr(void)
    {
      mcusr_mirror = MCUSR;
      MCUSR = 0;
      wdt_disable();
    }

static void initup(struct unpacker *up, u8 *ptr) {
	up->nextbyte = ptr;
	up->bits = 0;
}

static u8 readbit(struct unpacker *up) {
	u8 val;

#if 0
	/* XXX RAMPACKS If we have RAM packs, use this instead */
	if(!(up->bits & 0x7)) {
		up->buffer =
			(up->bits & 0x80)
				? pgm_read_byte_near(up->nextbyte)
				: *up->nextbyte;
		up->nextbyte++;
		up->bits |= 7;
	} else {
		up->bits--;
	}
#endif
	if(!up->bits) {
		up->buffer = pgm_read_byte_near(up->nextbyte++);
		up->bits = 8;
	}

	up->bits--;
	val = up->buffer & 1;
	up->buffer >>= 1;

	return val;
}

static u16 readchunk(struct unpacker *up, u8 n) {
	u16 val = 0;
	u8 i;

	for(i = 0; i < n; i++) {
		if(readbit(up)) {
			val |= (1 << i);
		}
	}

	return val;
}

static void readinstr_pgm(u8* base, u8 pos, u8 *dest) {
	u8 s0 = pgm_read_byte_near(base + pos + pos/2 + 0);
	u8 s1 = pgm_read_byte_near(base + pos + pos/2 + 1);
	if(pos & 1) {
		dest[0] = s0 >> 4;
		dest[1] = s1;
	} else {
		dest[0] = s1 & 0xF;
		dest[1] = s0; 
	}
}

static void runcmd(u8 ch, u8 cmd, u8 param) {
	switch(cmd) {
		case CMD_ISTOP:
			channel[ch].iptr = NULL;
			break;
		case CMD_DUTY:
			osc[ch].duty = param << 8;
			break;
		case CMD_VOLUMED:
			channel[ch].volumed = param;
			break;
		case CMD_INERTIA:
			channel[ch].inertia = param << 1;
			break;
		case CMD_IJUMP:
			channel[ch].ioff = param;
			break;
		case CMD_BENDD:
			channel[ch].bendd = param;
			break;
		case CMD_DUTYD:
			channel[ch].dutyd = param << 6;
			break;
		case CMD_IWAIT:
			channel[ch].iwait = param;
			break;
		case CMD_VOLUME:
			osc[ch].volume = param;
			break;
		case CMD_WAVEFORM:
			osc[ch].waveform = param;
			break;
		case CMD_INOTETRANS:
			channel[ch].inote = param + channel[ch].tnote - 12 * 4;
			break;
		case CMD_INOTE:
			channel[ch].inote = param;
			break;
		case CMD_VIBRATO:
			if(channel[ch].vdepth != (param >> 4)) {
				channel[ch].vpos = 0;
			}
			channel[ch].vdepth = param >> 4;
			channel[ch].vrate = param & 15;
			break;
	}
}

static void playtrack() {
	u8 ch;

	if(playsong) {
		if(trackwait) {
			trackwait--;
		} else {
			trackwait = 4;

			if(!trackpos) {
				if(playsong) {
					if(songpos >= songlen) {
						playsong = 0;
						light[1] = 0xFF;
					} else {
						for(ch = 0; ch < NR_CHAN; ch++) {
							u8 gottransp;
							u8 transp;
							u8 ntnum;

							gottransp = readchunk(&songup, 1);
							ntnum = readchunk(&songup, PACKSIZE_SONGTRACK);
							if(gottransp) {
								transp = readchunk(&songup, PACKSIZE_SONGTRANS);
								if(transp & 0x8) transp |= 0xf0;
							} else {
								transp = 0;
							}
							channel[ch].tnum = ntnum;
							channel[ch].transp = (s8) transp;

							if(channel[ch].tnum) {
								initup(&channel[ch].trackup,
									(u8*) pgm_read_word_near(
										&ttab[channel[ch].tnum-1]));
								// XXX TINDR
							}
						}
						songpos++;
					}
				}
			}

			if(playsong) {
				for(ch = 0; ch < NR_CHAN; ch++) {
					if(channel[ch].tnum
					&& !(channel[ch].flags & CF_TRACK_FINISHED)) {
						u8 note, instr;
						u8 fields;

						fields = readchunk(&channel[ch].trackup, 3);
						note = 0;
						instr = 0;
						if((fields & 4) && readchunk(&channel[ch].trackup, 1)) {
							fields |= 8;
						}
						if(fields & 1) note = readchunk(&channel[ch].trackup, PACKSIZE_TRACKNOTE);
						if(fields & 2) instr = readchunk(&channel[ch].trackup, PACKSIZE_TRACKINST);
						if(note) {
							channel[ch].tnote = note + channel[ch].transp;
							if(!instr) {
								channel[ch].iptr = channel[ch].ilast;
								goto instr_common;
							}
						}
						if(instr) {
							if(instr == 2) light[1] = 5;
							if(instr == 1) {
								light[0] = 5;
								if(channel[ch].tnum == 4) {
									light[0] = light[1] = 3;
								}
							}
							if(instr == 7) {
								light[0] = light[1] = 30;
							}
							channel[ch].ilast
								= channel[ch].iptr
								= (u8*) pgm_read_word_near(&itab[instr-1]);
								// XXX IINDR
instr_common:
							channel[ch].ioff = 0;
							channel[ch].iwait = 0;
							channel[ch].bend = 0;
							channel[ch].bendd = 0;
							channel[ch].volumed = 0;
							channel[ch].dutyd = 0;
							channel[ch].vdepth = 0;
						}
						if(fields & 4) {
							u8 cmd = readchunk(&channel[ch].trackup, PACKSIZE_TRACKCMD);
							u8 param = readchunk(&channel[ch].trackup, PACKSIZE_TRACKPAR);
							if(cmd == CMD_ISTOP)
								channel[ch].flags |= CF_TRACK_FINISHED;
							else
								runcmd(ch, cmd, param);
						}
						if(fields & 8) {
							u8 cmd = readchunk(&channel[ch].trackup, PACKSIZE_TRACKCMD);
							u8 param = readchunk(&channel[ch].trackup, PACKSIZE_TRACKPAR);
							if(cmd == CMD_ISTOP)
								channel[ch].flags |= CF_TRACK_FINISHED;
							else
								runcmd(ch, cmd, param);
						}

					}
				}

				trackpos++;
				trackpos &= (TRACKLEN-1);
			}
		}
	}
}

static void updateinstruments() {
	u8 ch;

	for(ch = 0; ch < NR_CHAN; ch++) {
		s16 vol;
		u16 duty;
		u16 slur;

		while(channel[ch].iptr && !channel[ch].iwait) {
			u8 il[2];

			// XXX RAMPACKS
			readinstr_pgm(channel[ch].iptr, channel[ch].ioff, il);
			channel[ch].ioff++;

			runcmd(ch, il[0], il[1]);
		}
		if(channel[ch].iwait) channel[ch].iwait--;

		if(channel[ch].inertia) {
			s16 diff;

			slur = channel[ch].slur;
			diff = freqtable[channel[ch].inote] - slur;
			//diff >>= channel[ch].inertia;
			if(diff > 0) {
				if(diff > channel[ch].inertia) diff = channel[ch].inertia;
			} else if(diff < 0) {
				if(diff < -channel[ch].inertia) diff = -channel[ch].inertia;
			}
			slur += diff;
			channel[ch].slur = slur;
		} else {
			slur = freqtable[channel[ch].inote];
		}
		osc[ch].freq =
			slur +
			channel[ch].bend +
			((channel[ch].vdepth * sinetable[channel[ch].vpos & 63]) >> 2);
		channel[ch].bend += channel[ch].bendd;
		vol = osc[ch].volume + channel[ch].volumed;
		if(vol < 0) vol = 0;
		if(vol > 255) vol = 255;
		osc[ch].volume = vol;

		duty = osc[ch].duty + channel[ch].dutyd;
		if(duty > 0xe000) duty = 0x2000;
		if(duty < 0x2000) duty = 0xe000;
		osc[ch].duty = duty;

		channel[ch].vpos += channel[ch].vrate;
	}

#ifdef TARGET_LIGHT_PORT
	if(light[0]) {
		light[0]--;
		TARGET_LIGHT_PORT |= TARGET_LIGHT_ZERO;
	} else {
		TARGET_LIGHT_PORT &= ~TARGET_LIGHT_ZERO;
    }
	if(light[1]) {
		light[1]--;
		TARGET_LIGHT_PORT |= TARGET_LIGHT_ONE;
	} else {
		TARGET_LIGHT_PORT &= ~TARGET_LIGHT_ONE;
	}
#endif
}

void initresources() {
	songlen = pgm_read_byte_near(&songdata[0]);
	initup(&songup, &songdata[1]);
}

#if 0
XXX MULTISONG TINDR IINDR
void initsongtabs(u8 idx) {
	int i;
	u16 songbase = pgm_read_byte_near(&songaddrs[idx]);
	u8 ni = pgm_read_byte_near(songbase++) & 0xF;
	for (i = 0; i < ni; i++) {
		iindr[i] = pgm_read_byte_near(songbase++);
	}
	u8 nt = pgm_read_byte_near(songbase++) & 0x3F;
	for (i = 0; i < nt; i++) {
		tindr[i] = pgm_read_byte_near(songbase++);
	}
	initup(&songup, songbase);
}
#endif

void initsong() {
	timetoplay = 0;
	trackwait = 0;
	trackpos = 0;
	playsong = 1;
	songpos = 0;

	osc[0].volume = 0;
	channel[0].iptr = NULL;
	osc[1].volume = 0;
	channel[1].iptr = NULL;
	osc[2].volume = 0;
	channel[2].iptr = NULL;
	osc[3].volume = 0;
	channel[3].iptr = NULL;
}

static void soundirqon() {
	TCCR0A = 0x02;
	TCCR0B = T0DIV & 0x7;
	OCR0A = T0MAX;
	TIMSK0 |= (1 << OCIE0A);
}

static void soundirqoff() {
	TIMSK0 &= ~(1 << OCIE0A);
}

static void hwouton() {
#ifdef TARGET_AUDIO_PORT
	TARGET_AUDIO_DDR = 0xff;
	TARGET_AUDIO_PORT = 0;
#endif

#ifdef TARGET_AUDIO_PWM_OC2B
		TCCR2A = (1 << COM2B1) | (1 << WGM21) | (1 << WGM20);
		TCCR2B = (1 << CS20);
		OCR2B = 0;
		TARGET_AUDIO_PWM_OC2B_DDR |= (1 << TARGET_AUDIO_PWM_OC2B_PIN);
#endif
}

static void hwoutoff() {
#ifdef TARGET_AUDIO_PORT
	TARGET_AUDIO_DDR = 0x00;
#endif

#ifdef TARGET_AUDIO_PWM_OC2B
		TARGET_AUDIO_PWM_OC2B_DDR &= ~(1 << TARGET_AUDIO_PWM_OC2B_PIN);
#endif
}

int main() __attribute__((naked,noreturn));
int main() {
	asm("cli");
	CLKPR = 0x80;
	CLKPR = 0x80;

#ifdef TARGET_LIGHT_PORT
	TARGET_LIGHT_DDR = TARGET_LIGHT_ZERO | TARGET_LIGHT_ONE;
#endif

	initsong();
	initresources();

	TCCR0A = 0x02;
	TCCR0B = T0DIV & 0x7;
	OCR0A = T0MAX;

	TIMSK0 = 0x02;

	soundirqon();
	hwouton();

	asm("sei");
	for(;;) {
		while(!timetoplay);

		timetoplay--;
		playtrack();
		updateinstruments();
	}
}

/*
INTERRUPT(_VECTOR(14))		// called at 8 KHz
{
	u8 i;
	s16 acc;
	u8 newbit;

	PORTD = lastsample;

	newbit = 0;
	if(noiseseed & 0x80000000L) newbit ^= 1;
	if(noiseseed & 0x01000000L) newbit ^= 1;
	if(noiseseed & 0x00000040L) newbit ^= 1;
	if(noiseseed & 0x00000200L) newbit ^= 1;
	noiseseed = (noiseseed << 1) | newbit;

	if(callbackwait) {
		callbackwait--;
	} else {
		timetoplay++;
		callbackwait = 90 - 1;
	}

	acc = 0;
	for(i = 0; i < 4; i++) {
		s8 value; // [-32,31]

		switch(osc[i].waveform) {
			case WF_TRI:
				if(osc[i].phase < 0x8000) {
					value = -32 + (osc[i].phase >> 9);
				} else {
					value = 31 - ((osc[i].phase - 0x8000) >> 9);
				}
				break;
			case WF_SAW:
				value = -32 + (osc[i].phase >> 10);
				break;
			case WF_PUL:
				value = (osc[i].phase > osc[i].duty)? -32 : 31;
				break;
			case WF_NOI:
				value = (noiseseed & 63) - 32;
				break;
			default:
				value = 0;
				break;
		}
		osc[i].phase += osc[i].freq;

		acc += value * osc[i].volume; // rhs = [-8160,7905]
	}
	// acc [-32640,31620]
	lastsample = 128 + (acc >> 8);	// [1,251]
}
*/
