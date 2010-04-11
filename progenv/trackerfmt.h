#ifndef _TRACKERFMT_H_
#define _TRACKERFMT_H_

#ifndef ASSEMBLER
#endif

	/* Packed format sizes */
#define PACKSIZE_RESOURCE	13
#define PACKSIZE_SONGTRACK	6
#define PACKSIZE_SONGTRANS	4
#define PACKSIZE_INSTRCMD	4
#define PACKSIZE_INSTRPAR	8
#define PACKSIZE_TRACKNOTE	7
#define PACKSIZE_TRACKINST	4
#define PACKSIZE_TRACKCMD	4
#define PACKSIZE_TRACKPAR	8

#define NR_CHAN         4   /**< Number of channels active in the system */
#define TRACKLEN        32  /**< Rows in a track */

/* Waveform values.  8 bits. */
#define WF_TRI          0x00    /**< Triangle wave */
#define WF_SAW          0x01    /**< Rising sawtooth wave */
#define WF_PUL          0x02    /**< Variable width pulse */
#define WF_NOI          0x03    /**< Uniform noise */

/* Commands.  4 bits. */
    /** End of instrument; not valid in track ctx. */
#define CMD_ISTOP       0x0
    /* RESERVED 0x00 (in track context) */
    /** Set oscillator duty top 8 bits; zero bottom bits */
#define CMD_DUTY        0x1
    /** Set channel volume derivative */
#define CMD_VOLUMED     0x2
    /** Set channel inertia (param << 1) */
#define CMD_INERTIA     0x3
    /** Set channel instrument offset */
#define CMD_IJUMP       0x4
    /** Set channel bend derivative */
#define CMD_BENDD       0x5
    /** Set channel duty derivative (param << 6) */
#define CMD_DUTYD       0x6
    /** Set channel instrument wait */
#define CMD_IWAIT       0x7
    /** Set oscillator volume */
#define CMD_VOLUME      0x8
    /** Set oscillator waveform */
#define CMD_WAVEFORM    0x9
    /** Set channel instrument note (transposed) */
#define CMD_INOTETRANS  0xB
    /** Set channel instrument note (absolute) */
#define CMD_INOTE       0xC
    /** Set channel vibrato depth and rate */
#define CMD_VIBRATO     0xA

    /* RESERVED 0x0D */
    /* RESERVED 0x0E */
    /* RESERVED 0x0F */
#endif
