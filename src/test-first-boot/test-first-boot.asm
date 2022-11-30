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



;---------------------------------------------------------------------------------------------------
; MOS ROM
;---------------------------------------------------------------------------------------------------
		ORG	$C000

handle_res	clra
		tfr	a,dp
		lds	#$8000

		; memory map at this point should be MOS i.e. System RAM 0-7FFF, SW ROM, This boot ROM

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



; user task 0
ut0_r
		ORG	$1000
		PUT	ut0_r
ut0
		ldx 	#3
1		inc 	DP_USER_TEST_CTR
		leax 	-1,X
		bne	1B
		swi3

		; poke at random hardware location to test hardware protection
		sta	$FE60

		jmp 	ut0

ut0_end

		ORG	ut0_r + ut0_end - ut0
		PUT	ut0_r + ut0_end - ut0


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
		rti
handle_swi
		rti
handle_irq
		rti
handle_nmi
		rti
