#include "stuff.h"
#include <progenv/gentimes.h>

volatile u8 callbackwait;

volatile u8 test;
volatile u8 testwait;

u8 trackwait;
u8 trackpos;
u8 songpos;

u8 playsong;
u8 playtrack;

volatile struct oscillator {
	u16	freq;
	u16	phase;
	u16	duty;
	u8	waveform;
	u8	volume;	// 0-255
} osc[NR_CHAN];

struct channel {
	u8	tnum;
	s8	transp;
	u8	tnote;
	u8	lastinstr;
	u8	inum;
	u8	iptr;
	u8	iwait;
	u8	inote;
	s8	bendd;
	s16	bend;
	s8	volumed;
	s16	dutyd;
	u8	vdepth;
	u8	vrate;
	u8	vpos;
	s16	inertia;
	u16	slur;
} channel[NR_CHAN];

void silence() {
	u8 i;

	for(i = 0; i < NR_CHAN; i++) {
		osc[i].volume = 0;
	}
	playsong = 0;
	playtrack = 0;
}

void runcmd(u8 ch, u8 cmd, u8 param) {
	switch(cmd) {
		case 0:
			channel[ch].inum = 0;
			break;
		case 'd':
			osc[ch].duty = param << 8;
			break;
		case 'f':
			channel[ch].volumed = param;
			break;
		case 'i':
			channel[ch].inertia = param << 1;
			break;
		case 'j':
			channel[ch].iptr = param;
			break;
		case 'l':
			channel[ch].bendd = param;
			break;
		case 'm':
			channel[ch].dutyd = param << 6;
			break;
		case 't':
			channel[ch].iwait = param;
			break;
		case 'v':
			osc[ch].volume = param;
			break;
		case 'w':
			osc[ch].waveform = param;
			break;
		case '+':
			channel[ch].inote = param + channel[ch].tnote - 12 * 4;
			break;
		case '=':
			channel[ch].inote = param;
			break;
		case '~':
			if(channel[ch].vdepth != (param >> 4)) {
				channel[ch].vpos = 0;
			}
			channel[ch].vdepth = param >> 4;
			channel[ch].vrate = param & 15;
			break;
		case 'S':
			osc[ch].phase += param;
			break;
	}
}

void iedplonk(int note, int instr) {
	channel[0].tnote = note;
	channel[0].inum = instr;
	channel[0].iptr = 0;
	channel[0].iwait = 0;
	channel[0].bend = 0;
	channel[0].bendd = 0;
	channel[0].volumed = 0;
	channel[0].dutyd = 0;
	channel[0].vdepth = 0;
}

void startplaytrack(int t) {
	channel[0].tnum = t;
	channel[1].tnum = 0;
	channel[2].tnum = 0;
	channel[3].tnum = 0;
	trackpos = 0;
	trackwait = 0;
	playtrack = 1;
	playsong = 0;
}

void startplaysong(int p) {
	songpos = p;
	trackpos = 0;
	trackwait = 0;
	playtrack = 0;
	playsong = 1;
}

void playroutine() {			// called at 50 Hz
	u8 ch;

	if(playtrack || playsong) {
		if(trackwait) {
			trackwait--;
		} else {
			trackwait = 4;

			if(!trackpos) {
				if(playsong) {
					if(songpos >= songlen) {
						playsong = 0;
					} else {
						for(ch = 0; ch < NR_CHAN; ch++) {
							u8 tmp[2];

							readsong(songpos, ch, tmp);
							channel[ch].tnum = tmp[0];
							channel[ch].transp = tmp[1];
						}
						songpos++;
					}
				}
			}

			if(playtrack || playsong) {
				for(ch = 0; ch < NR_CHAN; ch++) {
					if(channel[ch].tnum) {
						struct trackline tl;
						u8 instr = 0;

						readtrack(channel[ch].tnum, trackpos, &tl);
						if(tl.note) {
							channel[ch].tnote = tl.note + channel[ch].transp;
							instr = channel[ch].lastinstr;
						}
						if(tl.instr) {
							instr = tl.instr;
						}
						if(instr) {
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
						if(tl.cmd[0])
							runcmd(ch, tl.cmd[0], tl.param[0]);
						/*if(tl.cmd[1])
							runcmd(ch, tl.cmd[1], tl.param[1]);*/
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
}

void initchip() {
	trackwait = 0;
	trackpos = 0;
	playsong = 0;
	playtrack = 0;

	osc[0].volume = 0;
	channel[0].inum = 0;
	osc[1].volume = 0;
	channel[1].inum = 0;
	osc[2].volume = 0;
	channel[2].inum = 0;
	osc[3].volume = 0;
	channel[3].inum = 0;
}

u8 interrupthandler()
{
	u8 i;
	s16 acc;
	static u32 noiseseed = 1;
	u8 newbit;

	newbit = 0;
	if(noiseseed & 0x80000000L) newbit ^= 1;
	if(noiseseed & 0x01000000L) newbit ^= 1;
	if(noiseseed & 0x00000040L) newbit ^= 1;
	if(noiseseed & 0x00000200L) newbit ^= 1;
	noiseseed = (noiseseed << 1) | newbit;

	if(callbackwait) {
		callbackwait--;
	} else {
		playroutine();
		callbackwait = 180 - 1;
	}

	acc = 0;
	for(i = 0; i < NR_CHAN; i++) {
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
	return 128 + (acc >> 8);	// [1,251]
}
