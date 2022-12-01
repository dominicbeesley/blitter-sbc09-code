		include "../includes/hardware.inc"
		include "../includes/mmu.inc"

		CODE
		setdp	$0

; "Supervisor DP"

		ORG	0
DP_SAVE_SYS_STACK		RMB	2
DP_SAVE_USER_STACK	RMB	2
DP_TEST_SVC_CTR		RMB 	4

; "User DP"

		ORG	0
DP_USER_TEST_CTR		RMB	4


MACH_BEEB	equ	1

;---------------------------------------------------------------------------------------------------
; MOS ROM
;---------------------------------------------------------------------------------------------------
		ORG	$C000

handle_res	clra
		tfr	a,dp
		lds	#$8000

		; memory map at this point should be MOS i.e. System RAM 0-7FFF, SW ROM, This boot ROM

		; Reset hardware (taken from Tricky's test ROM)

		; disable and clear all interrupts
		lda	#$7F
		sta	sheila_SYSVIA_ier
		sta	sheila_SYSVIA_ifr 
	         sta	sheila_USRVIA_ier
	         sta	sheila_USRVIA_ifr

		lda	#$FF
		sta	sheila_SYSVIA_ddra
		sta	sheila_SYSVIA_ddrb
		sta	sheila_USRVIA_ddra
		sta	sheila_USRVIA_ddrb

	         sta	sheila_SERIAL_ULA  ; cassette LED/motor ON
	
		lda	#4
		sta	sheila_SYSVIA_pcr  ; vsync \\ CA1 negative-active-edge CA2 input-positive-active-edge CB1 negative-active-edge CB2 input-nagative-active-edge
		clr	sheila_SYSVIA_acr  ; none  \\ PA latch-disable PB latch-disable SRC disabled T2 timed-interrupt T1 interrupt-t1-loaded PB7 disabled


		;	disable all SysViaRegB B bits

		ldb	#$0F
		stb	sheila_SYSVIA_ddrb
1
		stb	sheila_SYSVIA_orb
		decb
		cmpb 	#9
		bhs 	1B

		; silence all channels

	; SN76489 data byte format
	; %1110-wnn latch noise (channel 3) w=white noise (otherwise periodic), nn: 0=hi, 1=med, 2=lo, 3=freq from channel %10
	; %1cc0pppp latch channel (%00-%10) period (low bits)
	; %1cc1aaaa latch channel (0-3) atenuation (%0000=loudest..%1111=silent)
	; if latched 1110---- %0----nnn noise (channel 3)
	; else                %0-pppppp period (high bits)
	; See SMS Power! for details http://www.smspower.org/Development/SN76489?sid=ae16503f2fb18070f3f40f2af56807f1
	; int volume_table[16]={32767, 26028, 20675, 16422, 13045, 10362, 8231, 6568, 5193, 4125, 3277, 2603, 2067, 1642, 1304, 0};

		lda	#$FF
		sta	sheila_SYSVIA_ddra

		lda 	#%10011111      			; silence channel 0
1		sta	sheila_SYSVIA_ora_nh            	; sample says SysViaRegH but OS uses no handshake \\ handshake regA
		clr 	sheila_SYSVIA_orb 		; enable sound for 8us
		jsr	WAIT8				; not actually exactly 8!
		ldb	#0+8
		stb	sheila_SYSVIA_orb 		; disable sound
		adda 	#$20 
		bcc	1B

		lda	#%10000000      			; silence channel 0
1		sta 	sheila_SYSVIA_ora_nh		; latch channel and set low bits of frequency
		clr	sheila_SYSVIA_orb			; enable sound for 8us
		jsr	WAIT8
		ldb	#0+8
		stb 	sheila_SYSVIA_orb			; disable sound

		clr 	sheila_SYSVIA_ora_nh		; zero high bits of freq
		clr 	sheila_SYSVIA_orb			; enable sound for 8us
		jsr	WAIT8
		ldb 	#0+8
		stb	sheila_SYSVIA_orb			; disable sound
		adda	#$20
		bcc 	1B

		ldx	#mode_7_setup
		jsr	vid_modeX


		; set up task 0 to have SYS at top (this code), ChipRAM at ram 0-7FFF and SYS screen memory 8000-BFFF

		lda 	#0
		sta	MMU_ACC_KEY
		lda	#$80
		sta	MMU_MAP+MMU_16_0
		lda	#$81
		sta	MMU_MAP+MMU_16_4
		lda	#$C1
		sta	MMU_MAP+MMU_16_8
		lda	#$C3
		sta	MMU_MAP+MMU_16_C

		lda 	#MMU_CTL_ENMMU
		sta	MMU_CTL

		; we should now be in map 0 with mmu enabled in 16K mode

		; setup hardware

		; copy mode 7 screen
		ldx	#mode7_scr
		ldu	#$BC00 			; mode 7 screen offset in our mapping
		ldy 	#$400
1		lda	,X+
		sta	,U+
		leay	-1,Y
		bne	1B



		; set up task 2 to contain a user task which is all RAM 

		lda 	#2
		sta	MMU_ACC_KEY
		lda	#$83
		sta	MMU_MAP+MMU_16_0
		lda	#$84
		sta	MMU_MAP+MMU_16_4
		lda	#$85
		sta	MMU_MAP+MMU_16_8
		lda	#$86
		sta	MMU_MAP+MMU_16_C

		; page in task 2's bottom page at 4000-7FFF
		lda 	#0
		sta	MMU_ACC_KEY
		lda	#$83
		sta	MMU_MAP+MMU_16_4

		; copy user task to 1000 (our 5000)
		ldu 	#ut0_r
		ldy	#$5000
		ldx 	#ut0_end-ut0+1
1		lda 	,u+
		sta	,y+
		leax	-1,x
		bne 	1B

		; setup a phoney user stack
		lda	#0		; phoney CCR
		sta	$7ffd
		ldd 	#$1000
		std	$7ffe

		; restore mapping
		lda	#$81
		sta	MMU_MAP+MMU_16_4

		lda	#2
		sta	MMU_TASK_KEY	; set task 2 as task to swap to

		; poke at hardware location
		sta	$FE60


		orcc 	#$50		; disable interrupts as we will mess with stack		
		sts	DP_SAVE_SYS_STACK
		lds 	#$3ffd		; User stack!
		jmp	MMU_RTI


here		inc 	$0
		inc	$3FFF
		inc	$4000
		inc	$BC30

		jmp	here


WAIT8		pshs	A,B,X,Y
		puls	A,B,X,Y,PC

		; change mode by sending bytes at X to vid ula and crtc
vid_modeX	
		lda 	#17
1		ldb 	A,X
		std	sheila_CRTC_reg
		deca
		bpl	1B

		ldb 	18,x
		stb	sheila_VIDULA_ctl

		rts

HEX2		sta	,-S
		lsra
		lsra
		lsra
		lsra
		bsr	HEX1
		lda	,S
		bsr	HEX1
		puls	A,PC


HEX1		anda	#$0F
		adda	#'0'
		cmpa	#'9'
		bls	1F
		adda	#'A'-'9'-1
1		; drop thru to print		

		; print A to SCREEN+X
SCREEN	EQU $BC00 ; screen in our mmu map
PRINTA		pshs	U
		leau	SCREEN,X
		sta	,U
		leax	1,X
		puls	U,PC


; user task 0
ut0_r
		ORG	$1000
		PUT	ut0_r
ut0
		clr	DP_USER_TEST_CTR
		clr	DP_USER_TEST_CTR+1
		clr	DP_USER_TEST_CTR+2
		clr	DP_USER_TEST_CTR+3

1		
		inc	DP_USER_TEST_CTR+3
		bne	2F
		inc	DP_USER_TEST_CTR+2
		bne	2F
		inc	DP_USER_TEST_CTR+1
		bne	2F
		inc	DP_USER_TEST_CTR+0
2
		ldx 	#40*20
		ldd	DP_USER_TEST_CTR+0
		swi3
		leax	4,X
		ldd	DP_USER_TEST_CTR+2
		swi3
		bra	1B

		; poke at random hardware location to test hardware protection
		sta	$FE60

		bra 	ut0

ut0_end

		ORG	ut0_r + ut0_end - ut0
		PUT	ut0_r + ut0_end - ut0


mode_7_setup  	FCB	$3F, $28, $33, $24, $1E, $02, $19, $1C
		FCB	$93, $12, $72, $13, $28, $00, $00, $00
		FCB	$28, $00 
		FCB	$4B


mode7_scr	includebin	"screen.mo7"



		ORG	REMAPPED_HW_VECTORS
XRESV		FDB	handle_div0	; $FFF0   ; Hardware vectors, paged in to $F7Fx from $FFFx
XSWI3V		FDB	handle_swi3	; $FFF2		; on 6809 we use this instead of 6502 BRK
XSWI2V		FDB	handle_irq	; $FFF4
XFIRQV		FDB	handle_irq	; $FFF6
XIRQV		FDB	handle_irq	; $FFF8
XSWIV		FDB	handle_swi	; $FFFA
XNMIV		FDB	handle_nmi	; $FFFC
XRESETV		FDB	handle_res	; $FFFE

handle_div0
		jmp	handle_div0
handle_swi3
		; swi entry
		orcc	#$50
		sts	<DP_SAVE_USER_STACK
		lds	<DP_SAVE_SYS_STACK
		andcc	#$AF

		sta	,-S

		clra
		tfr	A,DP

		lda	,S+


		; print a hex string at X

		jsr	HEX2
		tfr	B,A
		jsr	HEX2

		orcc	#$50
		sts	<DP_SAVE_SYS_STACK
		lds	<DP_SAVE_USER_STACK
		jmp	MMU_RTI

handle_swi
		rti
handle_irq
		rti
handle_nmi
		rti


