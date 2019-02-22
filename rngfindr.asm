; ******************************************************
; EEET2256 - Intro to Embedded Systems 2017
; PING Range Finder Project
; by Eric White and Tim Davis
;
; Diagram:
;
; SIG pin
;
;   -->|   |<--tOut
;       -->|       |<--tHoldOff
;               -->|                    |<--tInMax
;               -->|  |<--tInMin
;
;      |---|       |--------------------|             5V (high)
;      |   |       |  .                 |
;      |   |       |  .                 |
; -----|   |-------|  ..................|----------   0V (low)
;
; Sonar TX
;
;          -->|      |<--tBurst
;
;             ||||||||
;             ||||||||
;             ||||||||
; ------------||||||||---------------------------
;
; tOut = 5uS
; tHoldOff = 750uS
; tBurst = 200uS at 40 kHz
; tInMin = 115uS
; tInMax = 18.5mS
; Delay before next measurement 200uS
;
; Plan:
; 1. Microcontroller make the I/O line output (Using DDRx Reg)
; 2. The I/O line is made low
; 3. Wait for 10uS
; 4. Make the I/O line high - tOut
; 5. Wait for 5uS - tOut
; 6. Make the I/O line low - tHoldOff
; 7. Wait for 750uS
; 8. Now make I/O line input - for tInx
; 9. Wait till the module becomes high to start the timer - tInx
; 10. Now we have the time it takes for the wave to hit the obstacle and come back
; 11. Use tInx to calculate the distance
; 12. Display as LEDs
;
; Notes:
;
; Nominal Frequency (MHz) = 1.0
; For a 1MHz clock that means 1000000 cycles per second
; So, 1 cycle equals 1/1000000 seconds or 1uS
;
; Lecture notes say 1cm = 29.034uS
; ******************************************************

; for eric's computer
.include "C:\2_UNI_PROGRAMS\VMLAB\include\m32def.inc"

; for linux usb
;.include "C:\PROGRA~1\VMLAB\include\m32def.inc"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Define interupts
reset:
	jmp start ; Reset Handler
	jmp EXT_INT0 ; IRQ0 Handler
	jmp EXT_INT1 ; IRQ1 Handler
	jmp EXT_INT2 ; IRQ2 Handler
	jmp TIM2_COMP ; Timer2 Compare Handler
	jmp TIM2_OVF ; Timer2 Overflow Handler
	jmp TIM1_CAPT ; Timer1 Capture Handler
	jmp TIM1_COMPA ; Timer1 CompareA Handler
	jmp TIM1_COMPB ; Timer1 CompareB Handler
	jmp TIM1_OVF ; Timer1 Overflow Handler
	jmp TIM0_COMP ; Timer0 Compare Handler
	jmp TIM0_OVF ; Timer0 Overflow Handler
	jmp SPI_STC ; SPI Transfer Complete Handler
	jmp USART_RXC ; USART RX Complete Handler
	jmp USART_UDRE ; UDR Empty Handler
	jmp USART_TXC ; USART TX Complete Handler
	jmp ADC ; ADC Conversion Complete Handler
	jmp EE_RDY ; EEPROM Ready Handler
	jmp ANA_COMP ; Analog Comparator Handler
	jmp TWI ; Two-wire Serial Interf

; Define unused interupt reutines
EXT_INT0:   reti ; IRQ0 Handler
EXT_INT1:   reti ; IRQ1 Handler
EXT_INT2:   reti ; IRQ2 Handler
TIM2_COMP:	reti ; Timer2 Compare Handler
TIM2_OVF:	reti ; Timer2 Overflow Handler
TIM1_CAPT:	reti ; Timer1 Capture Handler
TIM1_COMPA:	reti ; Timer1 CompareA Handler
TIM1_COMPB: reti ; Timer1 CompareB Handler
TIM1_OVF:	reti ; Timer1 Overflow Handler
;TIM0_COMP:	reti ; Timer0 Compare Handler
TIM0_OVF:	reti ; Timer0 Overflow Handler
SPI_STC:		reti ; SPI Transfer Complete Handler
USART_RXC:	reti ; USART RX Complete Handler
USART_UDRE:	reti ; UDR Empty Handler
USART_TXC:	reti ; USART TX Complete Handler
ADC:			reti ; ADC Conversion Complete Handler
EE_RDY:		reti ; EEPROM Ready Handler
ANA_COMP:	reti ; Analog Comparator Handler
TWI:			reti ; Two-wire Serial Interface Handler
SPM_RDY:		reti ; Store Program Memory Ready Handler   rjmp start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; This interupt happens when when tcnt0(timer0) and ocr0(timer0 compare) are the same.
TIM0_COMP:	
	;see what step we are in
	cpi CurrentStep, $01 ; if we were in send ping and we got here
	breq SendPing ; We didn't recieve a response, so send another ping
	reti
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
start:
.def  low  = r0
.def 	high = r1
.def	temp = r16
.def 	sig  = r18
.def  LED  = r19
.def	CurrentStep = r20

	; initialise stack pointer to the end of the data memory
	ldi temp, low(RAMEND)
   out SPL, temp
   ldi temp, high(RAMEND)
   out SPH, temp

	clr low	;Load 0b00000000 in low (r0)
	ser temp ;Load Ob1111 1111 in temp
	mov high, temp ;Load Ob1111 1111 in high (r1)
	
   out DDRB, high	;Configure LEDs on the OUSB to output **Do I need this?

MainLoop:
	call SendPing
	call RecievePing
	call Display
	rjmp MainLoop

SendPing: ; this loop sends a ping for 5us then waits for a reply
; save what step the loop is in (so timer knows what to do later on)
	ldi CurrentStep, $01
; send ping
	out ddrc, high ; set port C as an output
	out portc, high ; start outputting ping
	nop
	nop
	nop
	nop ; 1*nop = 1us delay
	nop
	nop
	out portc, low ; stop outputting ping
	out ddrc, low ; set portC as an input
	
; wait for response for a maximum of 800us
	; setup timer
	; set to interupt when timer0 overflows
	ldi	temp, 0b00000010
	out 	timsk, temp
	;enable global interrupts (enables bit 7 of register SREG)
   sei
	; for timer0, set clock to 8 (1 count = 8us), set to interupt on a compare
	ldi	temp, 0b00010010
	out	tccr0, temp
	; set the register that the timer0 compares against to $64 (count 100 = 800us)
	ldi	temp, $64
	out	ocr0, temp
	rjmp forever1 ; loop at forever until 800us occurs or start receiving ping response

forever1: ; keep checking for a response until 800us has passed
	in temp, portc
	cp	temp, r0 ; Watch PortC until we recieve a response
	brne RecievePing ; when we recieve a response jump to RecievePing
	rjmp forever1	

RecievePing:
	; this loop does...........
; save what step the loop is in (so timer knows what to do later on)
	ldi CurrentStep, $02

forever:
   out DDRC, low	;Configure all pins on PortC as outputs for tOut
   out PORTC, low	;Writes all 0's to the pins of PortC
   NOP				;Delay to let the port settle
   out PORTC, high;Writes all 1's to the pins of PortC to set off the pulse (tOut)
   ;Delay 5uS
   out PORTC, low ;tHoldOff
   out DDRC, high	;Configure all pins on PORTC as Inputs for tInx
   ;Delay 750uS
   in	 sig, PINC	;Sets sig to the returning signal



	JMP Display		;Display the distance on the LEDs

rjmp forever

Display:
   JMP CalcLEDs	;Calculate the number of LEDs to light up
   out PORTB, LED ;
	ret

calcLEDs:
	;some kind of if statment for distance (idk how distance is returned)
	;LED Increment Numbers:
	;0x01,0x03,0x07,0x0F,0x1F,0x3F,0x7F,0xFF
	ret
	
	
;*************************************
; Example from lab3
;
; Delay routine
; Input: none
; outputs: none
; uses: nothing (saves registers and restores)
;
; this has an inner loop and an outer loop.  The delay is approximately
; equal to 256*256*number of inner loop instruction cycles (4) (~21mS)
; You can vary this by changing the initial values in the registers.
; If you need a much longer delay change one of the loop counters
; to a 16-bit register such as X or Y.
;
;*************************************
Delay:   ret
         PUSH R16			; save R16 and 17 as we're going to use them
         PUSH R17       ; as loop counters
         PUSH R0        ; we'll also use R0 as a zero value for compare
         CLR R0
         CLR R16        ; init inner counter
         CLR R17        ; and outer counter
L1:      DEC R16         ; counts down from 0 to FF to 0
			CPSE R16, R0    ; equal to zero?
			RJMP L1			 ; if not, do it again
			CLR R16			 ; reinit inner counter
L2:      DEC R17
         CPSE R17, R0    ; is it zero yet?
         RJMP L1			 ; back to inner counter
;
         POP R0          ; done, clean up and return
         POP R17
         POP R16
         RET
;*************************************



;References and helpful links:
;
;PING Sensor documentation:
;https://www.parallax.com/sites/default/files/downloads/28015-PING-Sensor-Product-Guide-v2.0.pdf
;
;setting I/O via DDRx:
;http://www.avr-tutorials.com/digital/digital-input-output-assembly-programming-atmel-8-bits-avr-microcontrollers


