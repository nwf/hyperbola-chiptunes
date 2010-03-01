#include <avr/io.h>
#include <avr/interrupt.h>

#define TRACKLEN 32

#include <progenv/types.h>
#include <progenv/gentimes.h>
#include <progenv/trackerfmt.h>
#include <target/config.h>

volatile u8 callbackwait;
volatile u8 lastsample;

volatile u8 timetoplay;

volatile u8 test;
volatile u8 testwait;

u8 trackwait;
u8 trackpos;
u8 playsong;
u8 songpos;

u32 noiseseed = 1;

u8 light[2];

volatile struct oscillator {
	u16	freq;
	u16	phase;
	u16	duty;
	u8	waveform;
	u8	volume;	// 0-255
} osc[NR_CHAN];

struct trackline {
	u8	note;
	u8	instr;
	u8	cmd[2];
	u8	param[2];
	};

struct track {
	struct trackline	line[TRACKLEN];
};

struct unpacker {
	u16	nextbyte;
	u8	buffer;
	u8	bits;
};

struct channel {
	struct unpacker		trackup;
	u8			tnum;
	s8			transp;
	u8			tnote;
	u8			lastinstr;
	u8			inum;
	u16			iptr;
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

u16 resources[16 + MAXTRACK];

struct unpacker songup;

u8 readsongbyte(u16 offset);
void watchdogoff();

static void initup(struct unpacker *up, u16 offset) {
	up->nextbyte = offset;
	up->bits = 0;
}

static u8 readbit(struct unpacker *up) {
	u8 val;

	if(!up->bits) {
		up->buffer = readsongbyte(up->nextbyte++);
		up->bits = 8;
	}

	up->bits--;
	val = up->buffer & 1;
	up->buffer >>= 1;

	return val;
}

u16 readchunk(struct unpacker *up, u8 n) {
	u16 val = 0;
	u8 i;

	for(i = 0; i < n; i++) {
		if(readbit(up)) {
			val |= (1 << i);
		}
	}

	return val;
}

static void readinstr(u8 num, u8 pos, u8 *dest) {
	dest[0] = readsongbyte(resources[num] + 2 * pos + 0);
	dest[1] = readsongbyte(resources[num] + 2 * pos + 1);
}

static void runcmd(u8 ch, u8 cmd, u8 param) {
	switch(cmd) {
		case CMD_ISTOP:
			channel[ch].inum = 0;
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
			channel[ch].iptr = param;
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

static void playroutine() {
	u8 ch;

	if(playsong) {
		if(trackwait) {
			trackwait--;
		} else {
			trackwait = 4;

			if(!trackpos) {
				if(playsong) {
					if(songpos >= SONGLEN) {
						playsong = 0;
					} else {
						for(ch = 0; ch < NR_CHAN; ch++) {
							u8 gottransp;
							u8 transp;

							gottransp = readchunk(&songup, 1);
							channel[ch].tnum = readchunk(&songup, 6);
							if(gottransp) {
								transp = readchunk(&songup, 4);
								if(transp & 0x8) transp |= 0xf0;
							} else {
								transp = 0;
							}
							channel[ch].transp = (s8) transp;
							if(channel[ch].tnum) {
								initup(&channel[ch].trackup, resources[16 + channel[ch].tnum - 1]);
							}
						}
						songpos++;
					}
				}
			}

			if(playsong) {
				for(ch = 0; ch < NR_CHAN; ch++) {
					if(channel[ch].tnum) {
						u8 note, instr, cmd, param;
						u8 fields;

						fields = readchunk(&channel[ch].trackup, 3);
						note = 0;
						instr = 0;
						cmd = 0;
						param = 0;
						if(fields & 1) note = readchunk(&channel[ch].trackup, 7);
						if(fields & 2) instr = readchunk(&channel[ch].trackup, 4);
						if(fields & 4) {
							cmd = readchunk(&channel[ch].trackup, 4);
							param = readchunk(&channel[ch].trackup, 8);
						}
						if(note) {
							channel[ch].tnote = note + channel[ch].transp;
							if(!instr) instr = channel[ch].lastinstr;
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
							channel[ch].lastinstr = instr;
							channel[ch].inum = instr;
							channel[ch].iptr = 0;
							channel[ch].iwait = 0;
							channel[ch].bend = 0;
							channel[ch].bendd = 0;
							channel[ch].volumed = 0;
							channel[ch].dutyd = 0;
							channel[ch].vdepth = 0;
						}
						if(cmd) runcmd(ch, cmd, param);
					}
				}

				trackpos++;
				trackpos &= 31;
			}
		}
	}

	for(ch = 0; ch < NR_CHAN; ch++) {
		s16 vol;
		u16 duty;
		u16 slur;

		while(channel[ch].inum && !channel[ch].iwait) {
			u8 il[2];

			readinstr(channel[ch].inum, channel[ch].iptr, il);
			channel[ch].iptr++;

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
}

void initresources() {
	u8 i;
	struct unpacker up;

	initup(&up, 0);
	for(i = 0; i < 16 + MAXTRACK; i++) {
		resources[i] = readchunk(&up, 13);
	}

	initup(&songup, resources[0]);
}

int main() {
	asm("cli");
	watchdogoff();
	CLKPR = 0x80;
	CLKPR = 0x80;

	TARGET_LIGHT_DDR = TARGET_LIGHT_ZERO | TARGET_LIGHT_ONE;
	TARGET_AUDIO_DDR = 0xff;

	TARGET_AUDIO_PORT = 0;

	timetoplay = 0;
	trackwait = 0;
	trackpos = 0;
	playsong = 1;
	songpos = 0;

	osc[0].volume = 0;
	channel[0].inum = 0;
	osc[1].volume = 0;
	channel[1].inum = 0;
	osc[2].volume = 0;
	channel[2].inum = 0;
	osc[3].volume = 0;
	channel[3].inum = 0;

	initresources();

	TCCR0A = 0x02;
	TCCR0B = T0DIV & 0x7;
	OCR0A = T0MAX;

	TIMSK0 = 0x02;

	asm("sei");
	for(;;) {
		while(!timetoplay);

		timetoplay--;
		playroutine();
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
