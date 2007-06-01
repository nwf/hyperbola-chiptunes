		.global	readsongbyte
		.global	watchdogoff
		.global	__vector_14

		.extern	lastsample
		.extern	noiseseed
		.extern	osc
		.extern	songdata

readsongbyte:
                ldi     r30, lo8(songdata)
                add     r30, r24
                ldi     r31, hi8(songdata)
                adc     r31, r25
                lpm
                mov     r24, r0
                mov     r25, r1
                ret

watchdogoff:
		wdr
		in	r24, 0x34		; mcusr
		andi	r24, 0xf7
		out	0x34, r24
		lds	r24, 0x60		; wdtcsr
		ori	r24, 0x18
		sts	0x60, r24
		ldi	r24, 0x00
		sts	0x60, r24
		ret

__vector_14:
		; Entire interrupt routine, worst case: 308 clocks.

		; ---------------------------------------------
		; Save processor state.
		; 27 clocks.

		push	r1			;				2
		push	r0			;				2
		in	r0, 0x3f		;				1
		push	r0			;				2
		push	r18			;				2
		push	r19			;				2
		push	r20			;				2
		push	r21			;				2
		push	r22			;				2
		push	r23			;				2
		push	r24			;				2
		push	r25			;				2
		push	r30			;				2
		push	r31			;				2

		; ---------------------------------------------
		; Write previously generated sample to PORTD.
		; 3 clocks.

		lds	r24, lastsample		;				2
		out	0x0b, r24		;				1

		; ---------------------------------------------
		; Run the noise shift register.
		; 31 clocks.

		eor	r22, r22		;				1
		ldi	r24, 1			;				1
		lds	r18, noiseseed+0	;				2
		lds	r19, noiseseed+1	;				2
		lds	r20, noiseseed+2	;				2
		lds	r21, noiseseed+3	;				2
		sbrc	r21, 7			; 0x80000000			1/2 \__ 2
		eor	r22, r24		;				1   /
		sbrc	r21, 0			; 0x01000000			1/2 \__ 2
		eor	r22, r24		;				1   /
		sbrc	r19, 1			; 0x00000200			1/2 \__ 2
		eor	r22, r24		;				1   /
		sbrc	r18, 6			; 0x00000040			1/2 \__ 2
		eor	r22, r24		;				1   /
		add	r18, r18		;				1
		adc	r19, r19		;				1
		adc	r20, r20		;				1
		adc	r21, r21		;				1
		or	r18, r22		;				1
		sts	noiseseed+0, r18	;				2
		sts	noiseseed+1, r19	;				2
		sts	noiseseed+2, r20	;				2
		sts	noiseseed+3, r21	;				2

		; ---------------------------------------------
		; Request calls to playroutine() at the
		; appropriate rate.
		; 13 or 8 clocks.

		lds	r24, callbackwait	;				2
		and	r24, r24		;				1
		brne	nocallb			;				1/2

		lds	r24, timetoplay		;				2
		subi	r24, 0xff		;				1
		sts	timetoplay, r24		;				2
		ldi	r24, 180		;				1

nocallb:	subi	r24, 0x01		;				1
		sts	callbackwait, r24	;				2

		; ---------------------------------------------
		; Loop through the channels
		; Worst case for entire loop: 5+(4+18+27)*4-1 = 200 clocks.

		; Setup: 5 clocks.

		eor	r22, r22		; acc = 0			1
		eor	r23, r23		;				1

		ldi	r30, lo8(osc)		; Z = &osc[0]			1
		ldi	r31, hi8(osc)		;				1

		ldi	r21, 3			; i = 3				1

chloop:
		; Loop prologue: 4 clocks.

		ldd	r24, Z+2		; phase				2
		ldd	r25, Z+3		;				2
		ldd	r18, Z+6		; waveform			2

		; WF_TRI: 12 or 10 clocks.
		; WF_SAW: 11 clocks.
		; WF_PUL: 16 or 18 clocks.
		; WF_NOI: 12 clocks.

		cpi	r18, 0x00		; WF_TRI			1
		breq	wftri			;				1/2
		cpi	r18, 0x01		; WF_SAW			1
		breq	wfsaw			;				1/2
		cpi	r18, 0x02		; WF_PUL			1
		breq	wfpul			;				1/2

wfnoi:
		lds	r20, noiseseed		;				2
		andi	r20, 63			;				1
		subi	r20, 32			;				1
		rjmp	chcont			;				2

wfpul:
		ldi	r20, -32		;				1
		ldd	r18, Z+4		; duty				2
		ldd	r19, Z+5		;				2
		cp	r18, r24		;				1
		cpc	r19, r25		;				1
		brcc	chcont			;				1/2 \
		ldi	r20, 31			;				1   |-- 4/2
		rjmp	chcont			;				2   /

wfsaw:
		mov	r20, r25		; high byte of phase		1
		lsr	r20			;				1
		lsr	r20			;				1
		subi	r20, 32			;				1
		rjmp	chcont			;				2

wftri:
		mov	r20, r25		; high byte of phase		1
		sbrc	r20, 7			; check high bit		1/2 \__ 3/2
		rjmp	tri_down		;				2   /

		lsr	r20			;				1
		subi	r20, 32			;				1
		rjmp	chcont			;				2
tri_down:
		andi	r20, 0x7f		;				1
		lsr	r20			;				1
		ldi	r18, 31			;				1
		sub	r18, r20		;				1
		mov	r20, r18		;				1

chcont:
		; Loop epilogue: 26 or 27 clocks (26 last time)

		; value is in r20

		ldd	r18, Z+7		; volume			2
		lsr	r18			;				1
		andi	r18, 0x7f		;				1
		muls	r18, r20		; r1:r0 = value * volume	2
		add	r22, r0			; add to acc			1
		adc	r23, r1			;				1
		add	r22, r0			; add to acc			1
		adc	r23, r1			;				1

		ld	r18, Z			; freq				2
		ldd	r19, Z+1		;				2
		add	r24, r18		; phase += freq			1
		adc	r25, r19		;				1

		std	Z+2, r24		; write new phase		2
		std	Z+3, r25		;				2

		subi	r21, 0x01		; i--				1
		adiw	r30, 0x08		; Z++				2
		sbrs	r21, 7			; skip if i < 0			1/2
		rjmp	chloop			;				2

		; ---------------------------------------------
		; Adjust acc and write to lastsample
		; 3 clocks.

		; r23 is acc >> 8
		subi	r23, 0x80		; add 128			1
		sts	lastsample, r23		;				2

		; ---------------------------------------------
		; Restore processor state.
		; 31 clocks.

		pop	r31			;				2
		pop	r30			;				2
		pop	r25			;				2
		pop	r24			;				2
		pop	r23			;				2
		pop	r22			;				2
		pop	r21			;				2
		pop	r20			;				2
		pop	r19			;				2
		pop	r18			;				2
		pop	r0			;				2
		out	0x3f, r0		;				1
		pop	r0			;				2
		pop	r1			;				2
		reti				;				4
