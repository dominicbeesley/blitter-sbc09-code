		include "../includes/hardware.inc"
		include "../includes/mmu.inc"

		CODE
		setdp	$0

SRC_PAGE		RMB	2
DEST_PAGE	RMB	2


; DB: new fuzix boot ROM map:
; kernel will run in bottom of RAM at pages 80,81,82,83 (init common = 83) (ChipRAM 00 0000..00 FFFF)
; a compressed (Exomizer 2) image should be available at pages 84 to 87 (ChipRAM 01 0000..01 FFFF) i.e. 
;  *BLLOAD E.KERNEL 10000

; put the compressed image after the 1st 64K as the BLUTILS utility rom tramples on the 1st 64

KERNEL_IMAGE_JIM	equ	$0100	; the JIM page for the base of the kernel image (decb format)
KERNEL_IMAGE_MMU	equ	$84	; the starting MMU page for the kernel image (decb format)

KERNEL_RUN_JIM	equ	$0000	; the JIM page for the base of the kernel at run-time
KERNEL_RUN_MMU	equ	$80	; the starting MMU for the base of the kernel at run-time


MACH_BEEB	equ	1

;---------------------------------------------------------------------------------------------------
; MOS ROM
;---------------------------------------------------------------------------------------------------
		ORG	$C000

handle_res	clra
		tfr	a,dp
		lds	#$100

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

		; Set up serial on ACIA for 9600 8n1

		lda 	#%01100100			; MOTOR off, RS423, 9600/9600
		sta	sheila_SERIAL_ULA

		lda	#%00000011			; Master reset
		sta	sheila_ACIA_CTL

		lda	#%00010110			; RTS low, no IRQs, 8n1, DIV64
		sta	sheila_ACIA_CTL

		ldx	#str_init
		jsr	ser_send_strX


		; setup hardware

		; copy mode 7 screen
		ldx	#mode7_scr
		ldu	#$7C00 			; mode 7 screen offset in our mapping
		ldy 	#$400
1		lda	,X+
		sta	,U+
		leay	-1,Y
		bne	1B

		; unpack DECB binary to raw image

		lda	#JIM_DEVNO_BLITTER
		sta	fred_JIM_DEVNO		; enable page-wide memory access

		ldx	#str_unpack
		jsr	ser_send_strX

		ldd 	#KERNEL_IMAGE_JIM
		std	SRC_PAGE
		ldx 	#$FD00			; X is source byte

hdr_lp		; get a header from JIM
		jsr	JimGetB

		tstb
		beq	1F
		incb
		beq	decb_done

		ldx	#str_bad_chunk
		jsr	ser_send_strX
jmphere		jmp	jmphere


1		jsr	JimGetD
		tfr	D,Y			; Y is length
		jsr	JimGetB			; high byte of dest
		clra
		addd	#KERNEL_RUN_JIM
		std	DEST_PAGE
		jsr	JimGetB
		lda 	#JIM/256
		tfr	D,U			; U is destination 

2		jsr	JimGetB
		jsr	JimSetB
		leay	-1,Y
		bne	2B
		bra	hdr_lp

decb_done

		lda	#0
		sta	fred_JIM_DEVNO		; enable page-wide memory access


		; copy "bounce" code at chipram 100 onwards (we expect 0..200 to be free)

		ldx	#str_boot
		jsr	ser_send_strX


		; set up task 0 to have SYS at top (this code), ChipRAM at ram 0-BFFF and SYS screen memory C000-BFFF

		lda 	#0
		sta	MMU_ACC_KEY
		lda	#KERNEL_RUN_MMU
		sta	MMU_MAP+MMU_16_0
		lda	#KERNEL_RUN_MMU+1
		sta	MMU_MAP+MMU_16_4
		lda	#KERNEL_RUN_MMU+2
		sta	MMU_MAP+MMU_16_8
		lda	#$C3			; this ROM
		sta	MMU_MAP+MMU_16_C

		lda 	#MMU_CTL_ENMMU
		sta	MMU_CTL

		; we should now be in map 0 with mmu enabled in 16K mode with this ROM (EXT) mapped at top
		; copy the bounce code to low memory at 100

		; copy user task to bank 0
		ldu 	#ut0_r
		ldy	#$100
		ldx 	#ut0_end-ut0+1
1		lda 	,u+
		sta	,y+
		leax	-1,x
		bne 	1B

		; jump to user task in bank 0
		jmp $100


ut0_r
		ORG	$100
		PUT	ut0_r
ut0		; this is the "bounce" task that is copied to 

		; map in top page of RAM in supervisor task 
		lda	#KERNEL_RUN_MMU+3
		sta	MMU_MAP+MMU_16_C

		; call the kernel
		jmp	$200
ut0_end
		ORG	ut0_r + ut0_end - ut0
		PUT	ut0_r + ut0_end - ut0






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

ser_send_strX	pshs	A
1		lda	,X+
		beq	2F
		bsr	ser_send_A
		bra	1B
2		puls	A,PC


HEX4		pshs	A
		bsr	HEX2
		tfr	B,A
		bsr	HEX2
		puls	A,PC

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

ser_send_A	stb	,-S
		ldb 	#ACIA_TDRE
1		bitb	sheila_ACIA_CTL
		beq	1B
		sta	sheila_ACIA_DATA
		puls	B,PC


JimGetD		bsr	JimGetB
		tfr	B,A
		; fall through
JimGetB		sta	,-S
		ldd	SRC_PAGE
		std	fred_JIM_PAGE_HI
		ldb	,X+
		cmpx	#JIM+$100
		blo	1F
		ldx 	#JIM
		; gone over page boundary
		lda	#'.'
		jsr	ser_send_A		; tell the world
		inc	SRC_PAGE+1
		bne	1F
		inc	SRC_PAGE
1		puls	A,PC

JimSetB		std	,--S
		ldd	DEST_PAGE
		std	fred_JIM_PAGE_HI
		ldb	1,S
		stb	,U+
		cmpu	#JIM+$100
		blo	1F
		ldu	#JIM
		; gone over page boundary
		inc	DEST_PAGE+1
		bne	1F
		inc	DEST_PAGE
1		puls	D,PC


str_init		FCB	"Fuzix Boot Rom for Blitter+SBC09",13,10,13,10,0
str_unpack	FCB	"Unpacking image at 01 0000 to 00 0000",13,10,0
str_boot		FCB	13,10,13,10,"Starting image at 00 0200",13,10,13,10,0
str_bad_chunk	FCB	"Bad Chunk header found", 13,10,0

mode_7_setup  	FCB	$3F, $28, $33, $24, $1E, $02, $19, $1C
		FCB	$93, $12, $72, $13, $28, $00, $00, $00
		FCB	$28, $00 
		FCB	$4B


mode7_scr	includebin	"screen.mo7"



		ORG	REMAPPED_HW_VECTORS
XRESV		FDB	handle_div0	; $FFF0   ; Hardware vectors, paged in to $F7Fx from $FFFx
XSWI3V		FDB	handle_swi3	; $FFF2		; on 6809 we use this instead of 6502 BRK
XSWI2V		FDB	handle_swi2	; $FFF4
XFIRQV		FDB	handle_firq	; $FFF6
XIRQV		FDB	handle_irq	; $FFF8
XSWIV		FDB	handle_swi	; $FFFA
XNMIV		FDB	handle_nmi	; $FFFC
XRESETV		FDB	handle_res	; $FFFE

handle_div0
		jmp	handle_div0
handle_swi3
		jmp	handle_swi3
handle_swi2
		jmp	handle_swi2
handle_swi
		jmp	handle_swi
handle_firq	
		jmp	handle_firq
handle_irq	
		jmp	handle_irq
handle_nmi
		jmp	handle_nmi


