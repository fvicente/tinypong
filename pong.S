;********************************************************************
;* Tiny Pong
;*
;* Copyright 2011 AlferSoft
;*
;* www.alfersoft.com.ar
;*
;* VGA Pong with ATtiny45
;*
;* Version       : 1.0
;* Date          :
;* Author        :
;* Target MCU    : attiny45@20MHz
;********************************************************************

; To run at 20MHz we need an external oscillator, that will take PB2 and PB3.
; TODO: Using an external clock (a crystal that generates TTL) we can save PB2!
; We still have 4 pins available, PB0 and PB1 will be used for the VGA HSYNC and
; VSYNC respectively, PB2 to generate the RGB (only black and white!).
; PB5 to get the input information that we want to display, hopefully this will
; come from a bluetooth module specially tuned for this, or from another ATtiny
; in the worst case.

;
;                      ATtiny45
;                  +-----------------+
;                  |                 |
;           IN ----| 1 (PB5) (VCC) 8 |---- +5V
;    22pf          |                 |
;  +--||----+------| 2 (PB3) (PB2) 7 |---- HSYNC
;  |       [ ] XTAL|                 |
;  +--||----+------| 3 (PB4) (PB1) 6 |---- VSYNC
;  | 22pf          |                 |
;  +---------------| 4 (GND) (PB0) 5 |---- RGB
;  |               |                 |
; GND              +-----------------+
;

#define __SFR_OFFSET 0 /* needed to subtract 0x20 from I/O addresses */

#define HSYNC		2
#define VSYNC		1
#define RGB			0
#define INPUT		5
#define PORT		_SFR_IO_ADDR(PORTB)

#include <avr/io.h>

	.global main
	.global maplines
	.global numtable

; VGA timing from http://en.wikipedia.org/wiki/Video_Graphics_Array
;
; The horizontal timings are:
; +--------------------------+----------+------+
; | Parameter                | Value    | Unit |
; +--------------------------+----------+------+
; | Pixel clock frequency    | 25.175   | MHz  |
; | Horizontal frequency     | 31.4686  | kHz  |
; | Horizontal pixels        | 640      |      |
; | Horizontal sync polarity | Negative |      |
; | Total time for each line | 31.77    | µs   |
; | Front porch (A)          | 0.94     | µs   |
; | Sync pulse length (B)    | 3.77     | µs   |
; | Back porch (C)           | 1.89     | µs   |
; | Active video (D)         | 25.17    | µs   |
; +--------------------------+----------+------+

; (Total horizontal sync time 6.60 µs)
; |__|______|___|_____________________________________________________________________|
;  A    B     C                                   D
;

; The vertical timings are:
; +--------------------------+----------+------+
; | Parameter                | Value    | Unit |
; +--------------------------+----------+------+
; | Vertical lines           | 480      |      |
; | Vertical sync polarity   | Negative |      |
; | Vertical frequency       | 59.94    | Hz   |
; | Front porch (E)          | 0.35     | ms   |
; | Sync pulse length (F)    | 0.06     | ms   |
; | Back porch (G)           | 1.02     | ms   |
; | Active video (H)         | 15.25    | ms   |
; +--------------------------+----------+------+

; More VGA timing info:
; http://courses.engr.illinois.edu/ece412/MP_files/mp3/vga_timing.pdf

;
; MISC NOTES:
;
; - At 20Mhz, 1 cycle = 0.05μs
; - Total of vertical lines: 525 (480 lines + 45 lines of vertical blanking)
; - VSYNC timing in lines:
;   -> Front porch = 10 lines (8 lines of bottom border + 2 lines of front porch)
;   -> Sync pulse length = 2 lines
;   -> Back porch = 33 lines (25 lines of back porch + 8 lines of top border)
; - Does not works with .org 0x00
;

;
; GAME NOTES:
;
; I've created this set of rules to emulate Atari's Pong Arcade, using following video as reference:
; http://www.youtube.com/watch?v=pDrRnJOCKZc
; Paddle height 5
; When the ball hits the paddle invert horizontal direction
; When the ball hits each different section of the paddle, being [1] the top and [5] the bottom:
; if paddle direction == "fixed":
;	keep current angle and vertical direction - this means that if current angle is 0 and both paddles
;	are aligned to hit in the middle, the ball will keep going back and forth forever (it seems to be
;	the original behavior)
; else:
;  [1] - set random angle to 45 or 67.5
;		 set ball's vertical direction to "up"
;  [2] - if current angle == 67.5:
;			set random angle to 45 or 67.5
;		 else:
;			set random angle to 22.5 or 45
;		 if paddle direction == "up":
;			set ball's vertical direction to "up"
;	 	 else:
;			keep current ball's vertical direction
;  [3] - if current angle == 67.5:
;			set random angle to 45 or 67.5
;		 else if current angle == 45:
;			set random angle to 22.5 or 45
;		 else:
;			set random angle to 0 or 22.5
;		 if paddle direction == "up":
;			set ball's vertical direction to "up"
;		 else:
;			set ball's vertical direction to "down"
;  [4] - if current angle == 67.5:
;			set random angle to 45 or 67.5
;		 else:
;			set random angle to 22.5 or 45
;		 if paddle direction == "down":
;			set ball's vertical direction to "down"
;	 	 else:
;			keep current ball's vertical direction
;  [5] - set random angle to 45 or 67.5
;		 set ball's vertical direction to "down"
;
; How to determine paddle direction (applies to human and microcontroller's paddle)
;
;	X = a maximum (to be defined) to keep the last paddle direction. Since the paddle direction
;       is determined once per frame, and we have 60 frames per second, each unit of X will
;		be equivalent to 16.66 ms.
;   1 - if new position == last position:
;		- increment paddle direction counter
;		- if paddle direction counter >= X then set paddle direction to "fixed" and reset
;		  paddle direction counter
;   2 - if new position > last position:
;		- set paddle direction to "down"
;		- reset paddle direction counter
;   3 - if new position < last position:
;		- set paddle direction to "up"
;		- reset paddle direction counter

;
; MEMORY USAGE:
;
; 0x0061 = pseudo-random number generated with lfsr
; 0x0062 = ball flags:
;		   bit 0 (horizontal direction): 0 = right, 1 = left
;		   bit 1 (vertical direction): 0 = down, 1 = up
;		   bit 2 (speed): 0 = normal, 1 = fast
; 0x0063 = ball current angle:
;		   0 = 0 (horizontal)
;		   1 = 22.5
;		   2 = 45
;		   3 = 67.5
; 0x0064 = left paddle direction
;		   0 = fixed
;		   1 = going down
;		   2 = going up
; 0x0065 = right paddle direction
;		   0 = fixed
;		   1 = going down
;		   2 = going up
; 0x0066 = left paddle direction counter
; 0x0067 = right paddle direction counter
; 0x0068 = game state
;		   0 = playing
;		   1 = goal
;		   2 = ended
; 0x0069 = game pause counter
; 0x006A = random offset for left paddle
; 0x006B = random offset for right paddle

main:
	; Initialize stack

	ldi r16, hi8(RAMEND)
	out _SFR_IO_ADDR(SPH), r16
	ldi r16, lo8(RAMEND)
	out _SFR_IO_ADDR(SPL), r16

	; Disable interruptions

	cli

	; Initialize ports

	sbi DDRB, 0x00	; output
	sbi DDRB, 0x01	; output
	sbi DDRB, 0x02	; output

	; RGB off
	cbi PORT, RGB		; cbi = 2 clocks

	; Initialize used registers

	ldi r16, 0x00		; aux
	ldi r17, 0x00		; aux
	ldi r18, 0x00		; aux
	ldi r19, 0x00		; aux

	ldi r20, 0x00		; line counter - 0x00 = first half of the 480 visible lines
						;                0x01 = second half of the 480 visible lines
						;                0x02 = 45 non-visible lines

	ldi r21, 0xFF		; line counter - from 0x00 to 0xF0 if r20 in (0x00, 0x01)
						;                from 0x00 to 0x2D if r20 == 0x02

	ldi r22, 0x00		; ZERO

	ldi r23, 0x2c		; left paddle position (0, 96 - paddle size)
	ldi r24, 0x2c		; right paddle position (0, 96 - paddle size)

	ldi r25, 0x3c		; ball X position (0, 120)
	ldi r26, 0x30		; ball Y position (0, 96)

	ldi r27, 0x00		; current line Y

	ldi r28, 0x00		; left score
	ldi r29, 0x00		; right score

	mov r1, r22			; line data
	mov r2, r22			; line data
	mov r3, r22			; line data
	mov r4, r22			; line data
	mov r5, r22			; line data
	mov r6, r22			; line data
	mov r7, r22			; line data
	mov r8, r22			; line data
	mov r9, r22			; line data
	mov r10, r22		; line data
	mov r11, r22		; line data
	mov r12, r22		; line data
	mov r13, r22		; line data
	mov r14, r22		; line data
	mov r15, r22		; line data

	; Starting values

	ldi r16, 0x88
	sts 0x0061, r16		; random
	sts 0x0062, r22		; set default ball flags direction right, down, speed normal
	; TODO: TESTS going left
	ldi r16, 0x00
	sts 0x0062, r16		; set default ball flags direction right, down, speed normal
	ldi r16, 0x02
	sts 0x0063, r16		; starting angle 2 = 45 degrees
	sts 0x0064, r22		; left paddle direction fixed
	sts 0x0065, r22		; right paddle direction fixed
	sts 0x0066, r22		; reset left paddle direction counter
	sts 0x0067, r22		; reset right paddle direction counter
	sts 0x0068, r22		; reset game state
	sts 0x0069, r22		; reset game pause counter
	sts 0x006A, r22		; reset game pause counter
	sts 0x006B, r22		; reset game pause counter

loop:
	;
	; Horizontal blanking total: 6.60 µs * 20 = 132 cycles
	;

	; Front porch 0.94 µs = 18.8 cycles

	; check line counters

	; first check vertical blanking zone
	cpi r20, 0x02
	breq vzone

	; increment counter
	inc r21
	; determine current line
	ldi ZL, lo8(maplines)
	ldi ZH, hi8(maplines)
	add ZL, r21
	adc ZH, r22
	lpm				; lpm = 3 cycles
	mov r27, r0
	; increment r20 if necessary
	cpi r21, 0xF0
	brne checkline
	; we're starting the lower half part of the screen
	inc r20
	ldi r21, 0x00
	sbrc r20, 1
	ldi r27, 0x60
	rjmp hsyncstart

vzone:
	inc r21
	cpi r21, 0x2D
	breq cntreset

	cpi r21, 0x09
	breq vpulseon		; line 10 of the blanking zone

	cpi r21, 0x0B
	breq vpulseoff		; line 12 of the blanking zone

	nop
	rjmp fp6togo

vpulseon:
	sbi PORT, VSYNC		; sbi = 2 clocks
	rjmp moveball

vpulseoff:
	cbi PORT, VSYNC		; turn VSYNC pulse off; cbi = 2 clocks
	nop
	nop
	nop
	nop
	rjmp hsyncstart

cntreset:
	ldi r20, 0x00
	ldi r21, 0x00
	rjmp fp8togo

fp8togo:
	nop
	nop

fp6togo:
	nop
	nop
	nop
	nop
	rjmp hsyncstart

checkline:
	; check if we're on the lower half of the screen
	cpi r20, 0x01
	breq addandgo
	nop
	rjmp hsyncstart

addandgo:
	; add offset to r27 - only 2 cycles left
	ldi r16, 0x30
	add r27, r16
	; fall thru

hsyncstart:
	; Sync pulse length 3.77 µs = 75.4 cycles
	; HSYNC pulse on
	sbi PORT, HSYNC		; sbi = 2 clocks

	; reset registers
	mov r1, r22
	mov r2, r22
	mov r3, r22
	mov r4, r22
	mov r5, r22
	mov r6, r22
	mov r7, r22
	mov r8, r22
	mov r9, r22
	mov r10, r22
	mov r11, r22
	mov r12, r22
	mov r13, r22
	mov r14, r22
	mov r15, r22
dashedline:
	; dashed line
	mov r16, r27
	ldi r17, 0x03
	and r16, r17
	cpi r16, 0x03
	breq dashoff	; space
dashon:
	ldi r16, 0x20
	or r8, r16
	rjmp dashend
dashoff:
	ldi r16, 0xDF
	and r8, r16
	nop

dashend:
	; 25 cycles used
	; r16 = r25 / 8
	mov r16, r25
	lsr r16
	lsr r16
	lsr r16
	; r18 = int(r25 / 8) * 8 ; to achieve this we clear bits 0, 1 and 2
	mov r17, r25
	cbr r17, 0xF8
	nop
	nop
	nop
	; get the mask according to r17
	ldi ZL, lo8(pm(masktable))
	ldi ZH, hi8(pm(masktable))
	; 2 instructions for each case in masktable, multiply r17 * 2
	lsl r17
	add ZL, r17
	adc ZH, r22
	ijmp

masktable:
	ldi r17, 0x80
	rjmp paintx
	ldi r17, 0x40
	rjmp paintx
	ldi r17, 0x20
	rjmp paintx
	ldi r17, 0x10
	rjmp paintx
	ldi r17, 0x08
	rjmp paintx
	ldi r17, 0x04
	rjmp paintx
	ldi r17, 0x02
	rjmp paintx
	ldi r17, 0x01
	rjmp paintx

paintx:
	; check if we are in the ball line
	cp r26, r27
	brne paintpads

	; 45 cycles used
	ldi ZL, lo8(pm(regtable))
	ldi ZH, hi8(pm(regtable))
	; 2 instructions for each case in regtable, multiply r16 * 2
	lsl r16
	add ZL, r16
	adc ZH, r22
	ijmp

regtable:
	or r1, r17
	rjmp endpaint
	or r2, r17
	rjmp endpaint
	or r3, r17
	rjmp endpaint
	or r4, r17
	rjmp endpaint
	or r5, r17
	rjmp endpaint
	or r6, r17
	rjmp endpaint
	or r7, r17
	rjmp endpaint
	or r8, r17
	rjmp endpaint
	or r9, r17
	rjmp endpaint
	or r10, r17
	rjmp endpaint
	or r11, r17
	rjmp endpaint
	or r12, r17
	rjmp endpaint
	or r13, r17
	rjmp endpaint
	or r14, r17
	rjmp endpaint
	or r15, r17
	rjmp endpaint

paintpads:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

endpaint:
	; 57 cycles used
	ldi r17, 0x05 ; paddle size
lpad:
	; left paddle
	mov r16, r27
	sub r16, r23
	brsh chklpad
	nop
	nop
	nop
	rjmp rpad
chklpad:
	ldi r18, 0x30
	cp r17, r16
	brlo rpad
	or r1, r18
rpad:
	; right paddle
	mov r16, r27
	sub r16, r24
	brsh chkrpad
	nop
	nop
	nop
	rjmp hsyncoff
chkrpad:
	ldi r18, 0x0C
	cp r17, r16
	brlo hsyncoff
	or r15, r18

hsyncoff:
	; 74 cycles used - we will need to get the last line during the back porch

	; HSYNC pulse off
	cbi PORT, HSYNC		; cbi = 2 clocks

	; Back porch 1.89 µs = 37.8 cycles
	; We use the back porch cycles to determine if we need to draw a blank line or a number line

	; draw scores
	cpi r27, 0x08
	brsh noscore

	; left score
	mov r16, r28
	lsl r16
	lsl r16
	lsl r16
	lsl r16
	add r16, r27
	ldi ZL, lo8(numtable)
	ldi ZH, hi8(numtable)
	add ZL, r16
	adc ZH, r22
	lpm
	or r6, r0
	ldi r16, 0x08
	add ZL, r16
	adc ZH, r22
	lpm
	or r7, r0

	; right score
	mov r16, r29
	lsl r16
	lsl r16
	lsl r16
	lsl r16
	add r16, r27
	ldi ZL, lo8(numtable)
	ldi ZH, hi8(numtable)
	add ZL, r16
	adc ZH, r22
	lpm
	; 38 cycles already! lets use some cycles from the line itself
	or r9, r0
	ldi r16, 0x08
	add ZL, r16
	adc ZH, r22
	lpm
	or r10, r0
	rjmp linestart

noscore:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

line:
	;
	; Draw a line of pixels total: 25.17 µs * 20 = 503.4 cycles
	;

	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

linestart:
	in r16, PORT

	; r1 bit 0
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 1
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 2
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 3
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 4
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 5
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 6
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r1 bit 7
	cbr r16, 1
	lsl r1
	adc r16, r22
	out PORT, r16
	; r2 bit 0
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 1
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 2
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 3
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 4
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 5
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 6
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r2 bit 7
	cbr r16, 1
	lsl r2
	adc r16, r22
	out PORT, r16
	; r3 bit 0
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 1
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 2
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 3
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 4
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 5
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 6
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r3 bit 7
	cbr r16, 1
	lsl r3
	adc r16, r22
	out PORT, r16
	; r4 bit 0
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 1
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 2
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 3
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 4
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 5
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 6
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r4 bit 7
	cbr r16, 1
	lsl r4
	adc r16, r22
	out PORT, r16
	; r5 bit 0
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 1
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 2
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 3
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 4
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 5
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 6
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r5 bit 7
	cbr r16, 1
	lsl r5
	adc r16, r22
	out PORT, r16
	; r6 bit 0
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 1
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 2
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 3
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 4
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 5
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 6
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r6 bit 7
	cbr r16, 1
	lsl r6
	adc r16, r22
	out PORT, r16
	; r7 bit 0
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 1
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 2
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 3
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 4
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 5
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 6
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r7 bit 7
	cbr r16, 1
	lsl r7
	adc r16, r22
	out PORT, r16
	; r8 bit 0
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 1
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 2
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 3
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 4
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 5
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 6
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r8 bit 7
	cbr r16, 1
	lsl r8
	adc r16, r22
	out PORT, r16
	; r9 bit 0
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 1
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 2
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 3
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 4
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 5
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 6
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r9 bit 7
	cbr r16, 1
	lsl r9
	adc r16, r22
	out PORT, r16
	; r10 bit 0
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 1
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 2
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 3
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 4
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 5
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 6
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r10 bit 7
	cbr r16, 1
	lsl r10
	adc r16, r22
	out PORT, r16
	; r11 bit 0
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 1
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 2
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 3
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 4
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 5
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 6
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r11 bit 7
	cbr r16, 1
	lsl r11
	adc r16, r22
	out PORT, r16
	; r12 bit 0
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 1
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 2
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 3
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 4
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 5
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 6
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r12 bit 7
	cbr r16, 1
	lsl r12
	adc r16, r22
	out PORT, r16
	; r13 bit 0
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 1
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 2
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 3
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 4
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 5
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 6
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r13 bit 7
	cbr r16, 1
	lsl r13
	adc r16, r22
	out PORT, r16
	; r14 bit 0
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 1
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 2
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 3
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 4
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 5
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 6
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r14 bit 7
	cbr r16, 1
	lsl r14
	adc r16, r22
	out PORT, r16
	; r15 bit 0
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 1
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 2
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 3
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 4
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 5
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 6
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16
	; r15 bit 7
	cbr r16, 1
	lsl r15
	adc r16, r22
	out PORT, r16

	; ending line
	cbr r16, 1
	; two nops before clear
	nop
	nop
	out PORT, r16
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp loop

moveball:
	nop
	nop
	nop
	nop
	nop
	nop
	; Sync pulse length 3.77 µs = 75.4 cycles
	; HSYNC pulse on
	sbi PORT, HSYNC		; sbi = 2 clocks
	ldi r16, 0x18
loopmb:
	dec r16
	brne loopmb
	; HSYNC pulse off
	cbi PORT, HSYNC		; cbi = 2 clocks
	; Back porch 37.8 cycles + draw line 503.4 cycles
	; So we have a total of 541.2 cycles to calculate the ball location

	; First check the game state to see if we're paused (goal or ended)
	lds r16, 0x0068	; game state
	cpi r16, 0x00
	breq playthegame
	; we are in pause
	lds r17, 0x0069	; game pause counter
	inc r17
	cpi r17, 0x78	; 120 (2 seconds)
	brsh timeout
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp saveandcontinue
timeout:
	ldi r17, 0x00
	sts 0x0068, r17	; set game state to playing
	cpi r16, 0x01
	breq goal
	nop
	rjmp checkgameend
goal:
	; we have a goal, reset ball position
	ldi r25, 0x3c	; X
	ldi r26, 0x30	; Y
checkgameend:
	cpi r16, 0x02
	breq gameended
	nop
	nop
	nop
	rjmp saveandcontinue
gameended:
	; we have a winner, reset scores
	ldi r28, 0x00
	ldi r29, 0x00
	ldi r25, 0x3c	; X
	ldi r26, 0x30	; Y
saveandcontinue:
	sts 0x0069, r17	; store counter

	; spend remaining time
	ldi r16, 0xA9
looppause:
	dec r16
	brne looppause
	rjmp loop

playthegame:
	; Calculate ball's new location. Bresenham's algorithm is used to determine the next
	; position of the ball in the screen
	lds r16, 0x0063	; current angle
	; Calculate ending coordinates (x1, y1) according to the angle
	ldi ZL, lo8(pm(incy1))
	ldi ZH, hi8(pm(incy1))
	lsl r16 ; multiply by 2
	add ZL, r16
	adc ZH, r22
	ijmp
incy1:
	ldi r17, 0x0
	rjmp incx1
	ldi r17, 0x19
	rjmp incx1
	ldi r17, 0x32
	rjmp incx1
	ldi r17, 0x4B
	rjmp incx1
incx1:
	ldi r16, 0x01
	; r17: dy = y1 - y0
	mov r18, r17
	nop
	nop
	; we will use r17 to keep the increment step over the Y axis
	ldi r17, 0x00
	; r18: (2 * dy)
	lsl r18
	; r19: dx = x1 - x0, which will be always 0x32
	ldi r19, 0x32
	; r19: d = dx - (2 * dy)
	sub r19, r18
	; if d < 0
	cpi r19, 0x40 ; check if result is negative
	brsh negdif
	; d = d - (2 * dy)
	sub r19, r18
	nop
	nop
	nop
	rjmp checkspeed
negdif:
	ldi r17, 0x01
	; d = d + (2 * dx) - (2 * dy);
	; note that dx will always be 0x32, so 2 * 0x32 = 0x64
	ldi r16, 0x64
	add r19, r16
	sub r19, r18
	ldi r16, 0x01
checkspeed:
	; if speed is fast, repeat Bresenham's algorithm one more time
	lds r19, 0x0062	; ball flags
	andi r19, 0x04
	cpi r19, 0x04
	breq fastpos
	; slow speed
	nop
	nop
	nop
	rjmp vmove
fastpos:
	inc r16
	; if d < 0
	cpi r19, 0x40	; check if result is negative
	brsh fastincpos
	rjmp vmove
fastincpos:
	; y = y + 1
	inc r17
vmove:
	; r16 = the quantity to increment (or decrement) the ball position in the X axis
	; r17 = the quantity to increment (or decrement) the ball position in the Y axis
	lds r18, 0x0062	; ball flags
	; vertical orientation
	sbrc r18, 1
	rjmp goingup
	nop
goingdown:
	add r26, r17
	cpi r26, 0x5F
	brsh changetoup
	nop
	nop
	nop
	rjmp endvmove
goingup:
	sub r26, r17
	cpi r26, 0x64
	brsh changetodown
	nop
	nop
	nop
	rjmp endvmove
changetoup:
	sbr r18, 2
	ldi r26, 0x5F
	rjmp endvmove
changetodown:
	cbr r18, 2
	ldi r26, 0x00
	rjmp endvmove
endvmove:
	sts 0x0062, r18	; save ball flags

	ldi r17, 0x05 ; paddle size
hmove:
	; use r19 to save the hit point on the paddle (0x00-0x04 left a and 0x05-0x09 right), 0xFF if
	; no hit at all
	; from hmove to endhmove = 23 cycles
	ldi r19, 0xFF
	; horizontal orientation
	sbrc r18, 0
	rjmp goingleft
	nop
goingright:
	add r25, r16
	cpi r25, 0x77
	brlo chkrpos
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endhmove
chkrpos:
	cpi r25, 0x74
	brsh checkrpad
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endhmove
goingleft:
	sub r25, r16
	cpi r25, 0x02
	brsh chklpos
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endhmove
chklpos:
	cpi r25, 0x05
	brlo checklpad
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endhmove
checkrpad:
	mov r16, r26
	sub r16, r24
	brsh chkrpadpos
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endhmove
chkrpadpos:
	cp r17, r16
	brsh rpadhit
	nop
	nop
	nop
	nop
	rjmp endhmove
rpadhit:
	; right paddle was hit
	mov r19, r16
	ldi r16, 0x05
	add r19, r16
	rjmp endhmove

checklpad:
	mov r16, r26
	sub r16, r23
	brsh chklpadpos
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endhmove
chklpadpos:
	cp r17, r16
	brsh lpadhit
	nop
	nop
	nop
	nop
	rjmp endhmove
lpadhit:
	; left paddle was hit
	mov r19, r16
	nop
	nop
	rjmp endhmove

endhmove:
	; check for goals
	cpi r25, 0x02
	brlo leftgoal
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp chkrightgoal
leftgoal:
	ldi r16, 0x01
	sts 0x0068, r16
	;
	inc r29
	cpi r29, 0x0b
	brne chkrightgoal5togo
	; we have a winner
	ldi r16, 0x02
	sts 0x0068, r16
	rjmp chkrightgoal
chkrightgoal5togo:
	nop
	nop
	nop
	nop
	nop
chkrightgoal:
	cpi r25, 0x77
	brsh rightgoal
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp random
rightgoal:
	ldi r16, 0x01
	sts 0x0068, r16
	;
	inc r28
	cpi r28, 0x0b
	brne random5togo
	; we have a winner
	ldi r16, 0x02
	sts 0x0068, r16
	rjmp random
random5togo:
	nop
	nop
	nop
	nop
	nop
random:
	; lfsr - Linear feedback shift register
	lds r18, 0x0061
	ldi r16, 0xb4
	clc			; clear carry flag
	ror r18
	brcs lfsr
	eor r18, r16
lfsr:
	sts 0x0061, r18

	; if a pad was hit, change random offsets
	cpi r19, 0x0A
	brlo randomoffset
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp endrandomoffset
randomoffset:
	clc			; clear carry flag
	ror r18
	brcs lfsr2
	eor r18, r16
lfsr2:
	sts 0x0061, r18
	ldi r16, 0x07
	and r18, r16
	cpi r18, 0x06
	brlo saveoffset
	ldi r18, 0x03	; default middle of paddle
saveoffset:
	cpi r19, 0x05
	brlo randomoffsetleft
	sts 0x006B, r18
	rjmp endrandomoffset
randomoffsetleft:
	nop
	sts 0x006A, r18
endrandomoffset:

	; check if the ball hit the paddle
	cpi r19, 0xFF
	brne hit
	rjmp nohit
hit:
	; if hit, always invert horizontal ball direction
	lds r16, 0x0062	; load ball flags
	ldi r17, 0x01
	eor r16, r17
	sts 0x0062, r16	; save ball flags
	; check which pad was hit, and load the pad direction in r17
	cpi r19, 0x05
	brlo lefthit
	lds r17, 0x0064
	mov r16, 0x05
	sub r19, r16
	rjmp checkhit
lefthit:
	lds r17, 0x0065
	nop
	nop
	nop
checkhit:
	; r17 = paddle direction
	; r18 = random number
	; r19 = hit position
	cpi r17, 0x00
	brne hitjmp
	rjmp paddlefixed	; keep vertical direction and angle
hitjmp:
	ldi ZL, lo8(pm(hitjmptable))
	ldi ZH, hi8(pm(hitjmptable))
	add ZL, r19
	adc ZH, r22
	ijmp

hitjmptable:
	rjmp hit1
	rjmp hit2
	rjmp hit3
	rjmp hit4
	rjmp hit5
	; from hitX to movepads = 28 cycles

hit1:
	; set random angle to 45 or 67.5
	ldi r16, 0x03
	sbrs r18, 0
	ldi r16, 0x02
	nop
	sts 0x0063, r16	; save angle
	; set ball's vertical direction to "up"
	lds r16, 0x0062	; load ball flags
	sbr r16, 0x02
	sts 0x0062, r16	; save ball flags
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp movepads

hit2:
	lds r16, 0x0063	; load angle
	cpi r16, 0x03
	brne hit2angle
	; set random angle to 45 or 67.5
	ldi r16, 0x03
	sbrs r18, 0
	ldi r16, 0x02
	nop
	rjmp hit2saveangle
hit2angle:
	; set random angle to 22.5 or 45
	ldi r16, 0x01
	sbrs r18, 0
	ldi r16, 0x02
	nop
	nop
hit2saveangle:
	sts 0x0063, r16	; save angle
	; check vertical direction
	lds r16, 0x0062	; load ball flags
	cpi r17, 0x02
	breq hit2padup
	nop
	nop
	rjmp hit2saveflags	; keep current vertical direction
hit2padup:
	nop
	nop
	sbr r16, 0x02	; set vertical direction up
hit2saveflags:
	sts 0x0062, r16	; save ball flags
	nop
	nop
	rjmp movepads

hit3:
	lds r16, 0x0063	; load angle
	cpi r16, 0x03
	brne hit3angle
	; set random angle to 45 or 67.5
	ldi r16, 0x03
	sbrs r18, 0
	ldi r16, 0x02
	nop
	nop
	nop
	rjmp hit3saveangle
hit3angle:
	cpi r16, 0x02
	brne hit3angle2
	; set random angle to 22.5 or 45
	ldi r16, 0x01
	sbrs r18, 0
	ldi r16, 0x02
	rjmp hit3saveangle
hit3angle2:
	; set random angle to 0 or 22.5
	ldi r16, 0x00
	sbrs r18, 0
	ldi r16, 0x01
	nop
hit3saveangle:
	sts 0x0063, r16	; save angle
	; check vertical direction
	lds r16, 0x0062	; load ball flags
	cpi r17, 0x02
	breq hit3padup
	nop
	nop
	rjmp hit3saveflags	; keep current vertical direction
hit3padup:
	nop
	nop
	sbr r16, 0x02	; set vertical direction up
hit3saveflags:
	sts 0x0062, r16	; save ball flags
	rjmp movepads

hit4:
	lds r16, 0x0063	; load angle
	cpi r16, 0x03
	brne hit4angle
	; set random angle to 45 or 67.5
	ldi r16, 0x03
	sbrs r18, 0
	ldi r16, 0x02
	nop
	rjmp hit4saveangle
hit4angle:
	; set random angle to 22.5 or 45
	ldi r16, 0x01
	sbrs r18, 0
	ldi r16, 0x02
	nop
	nop
hit4saveangle:
	sts 0x0063, r16	; save angle
	; check vertical direction
	lds r16, 0x0062	; load ball flags
	cpi r17, 0x01
	breq hit4paddown
	nop
	nop
	rjmp hit4saveflags	; keep current vertical direction
hit4paddown:
	nop
	nop
	cbr r16, 0x02	; set vertical direction down
hit4saveflags:
	sts 0x0062, r16	; save ball flags
	nop
	nop
	rjmp movepads

hit5:
	; set random angle to 45 or 67.5
	ldi r16, 0x03
	sbrs r18, 0
	ldi r16, 0x02
	nop
	sts 0x0063, r16	; save angle
	; set ball's vertical direction to "down"
	lds r16, 0x0062	; load ball flags
	cbr r16, 0x02
	sts 0x0062, r16	; save ball flags
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp movepads

nohit:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop

paddlefixed:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	rjmp movepads

movepads:
	; TODO: demo, move the paddle in ball's direction
	lds r19, 0x0062	; load ball flags
	sbrs r19, 0
	rjmp moverpad
	nop
movelpad:
	mov r18, r23	; r18 = previous left paddle position
	mov r19, r24	; r19 = previous right paddle position
	lds r17, 0x006A	; load random offset
	mov r16, r23	; left paddle position
	add r16, r17
	cp r26, r16		; compare ball Y position with middle of the paddle
	brlo lpadup
	breq lpadfix
	inc r23 ; add r23, r18
	cpi r23, 0x5A
	brsh setmaxlpad
	nop
	nop
	rjmp spendandgo
setmaxlpad:
	ldi r23, 0x5A
	rjmp spendandgo
lpadup:
	dec r23 ; sub r23, r18
	cpi r23, 0x5A
	brlo lpadcont
	ldi r23, 0x00
	nop
	rjmp spendandgo
lpadfix:
	nop
	nop
	nop
lpadcont:
	nop
	rjmp spendandgo

moverpad:
	mov r18, r23	; r18 = previous left paddle position
	mov r19, r24	; r19 = previous right paddle position
	lds r17, 0x006B	; load random offset
	mov r16, r24	; right paddle position
	add r16, r17
	cp r26, r16		; compare ball Y position with middle of the paddle
	brlo rpadup
	breq rpadfix
	; TODO: replace following instruction with a nop to temporarely inactive right paddle for tests
	inc r24 ; add r24, r18
	cpi r24, 0x5A
	brsh setmaxrpad
	nop
	nop
	rjmp spendandgo
setmaxrpad:
	ldi r24, 0x5A
	rjmp spendandgo
rpadup:
	; TODO: replace following instruction with a nop to temporarely inactive right paddle for tests
	dec r24 ; sub r24, r18
	cpi r24, 0x5A
	brlo rpadcont
	ldi r24, 0x00
	nop
	rjmp spendandgo
rpadfix:
	nop
	nop
	nop
rpadcont:
	nop
	rjmp spendandgo

spendandgo:
	; update paddles direction
	cp r23, r18
	brne chklpaddown
	lds r16, 0x0066	; left paddle direction counter
	inc r16
	sts 0x0066, r16
	cpi r16, 0x0A	; maximum delay to remember paddle's direction
	brsh setlpadfix
	nop
	nop
	nop
	nop
	nop
	rjmp updaterpad
chklpaddown:
	brsh setlpadup
	ldi r16, 0x01
	sts 0x0064, r16	; set left paddle direction to down
	nop
	nop
	nop
	nop
	nop
	rjmp resetlpadcount
setlpadup:
	ldi r16, 0x02
	sts 0x0064, r16	; set left paddle direction to down
	nop
	nop
	nop
	nop
	rjmp resetlpadcount
setlpadfix:
	sts 0x0064, r22	; set left paddle direction to fixed
resetlpadcount:
	sts 0x0066, r22
updaterpad:
	cp r24, r19
	brne chkrpaddown
	lds r16, 0x0067	; left paddle direction counter
	inc r16
	sts 0x0067, r16
	cpi r16, 0x0A	; maximum delay to remember paddle's direction
	brsh setrpadfix
	nop
	nop
	nop
	nop
	nop
	rjmp updatepadend
chkrpaddown:
	brsh setrpadup
	ldi r16, 0x01
	sts 0x0065, r16	; set left paddle direction to down
	nop
	nop
	nop
	nop
	nop
	rjmp resetrpadcount
setrpadup:
	ldi r16, 0x02
	sts 0x0065, r16	; set left paddle direction to down
	nop
	nop
	nop
	nop
	rjmp resetrpadcount
setrpadfix:
	sts 0x0065, r22	; set left paddle direction to fixed
resetrpadcount:
	sts 0x0067, r22
updatepadend:

	; spending remaining cycles
	ldi r16, 0x5B
loopmb2:
	dec r16
	brne loopmb2
	rjmp loop
