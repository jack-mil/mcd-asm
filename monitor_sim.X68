* ------------------- *
* M68k system monitor
* jackmil
* MCD 2022
* ------------------- *

* -- Device addresses -- *
ROM:        EQU     $000000     ; ROM Start
RAM:        EQU     $010000     ; RAM Start
DUART:      EQU     $020000     ; DUART base address

STACK:      EQU     $020000     ; Location of stack (grows up from bottom of RAM)

* Data and global variable definition
MAXCHR:     EQU     64          ; Length (bytes) of input line buffer
DATA:       EQU     RAM         ; Data origin
LNBUFF:     DS.B    MAXCHR      ; Input line buffer
BUFFEND:    EQU     LNBUFF+MAXCHR-1 ; end of line buffer
BUFFPT:     DS.L    1           ; Pointer to line buffer
PARAMTR:    DS.L    1           ; Last parameter from line buffer
ECHO:       DS.B    1           ; Enable input echo when clear
U_CASE:     DS.B    1           ; Flag for upper-case conversion
REG_F:      DS.W    37          ; Frame for D0-D7, A0-A6, USP, SSP, SR, PC


* -- Simulator select bit -- *
sim:        EQU     $1          ; 1 -> simulator / 0 -> hardware
            OPT     SEX

* ---------------------- *
*       RESET START      *
* ---------------------- *
        ORG     $000000
        DC.L    STACK       ; Supervisor stack pointer on reset
        DC.L    RESET       ; Reset address vector

RESET:  ORG     $008000         ; Cold entry point for monitor
        IFNE sim                ; Disable keyboard echo on simulator
        move.b  #$00,D1
        move.b  #12,D0
        trap    #15

        move.l  #758*$10000+700,D1 ; Set screen size to ~80 columns
        move.b  #33,D0
        trap    #15

        move.l  #STACK,A7       ; Manually SSP because simulator weird?
        ENDC
        jsr     INIT_SERIAL     ; Initilize duart device

        * Setup global vars
        lea     DATA,A6         ; A6 points to data area
        clr.b   U_CASE(A6)      ; Set automatic upper-case conversion
        clr.b   ECHO(A6)        ; Set automatic input echo

        * Print welcome

        lea     BANNER(PC),A1   ; Point to welcome banner,
        bsr     PRINT_STR       ; and print it

WARM:   clr.l   D7              ; Warm entry point - clear error flag
        bsr     NEW_LINE        ; Print a newline
        bsr     GET_LINE        ; Get command line
        bsr     CLEAN_UP        ; Clean up readline buffer contents
        bsr     EXECUTE         ; Interpret command
        bra     WARM            ; Repeat forever



* -------------------- *
* DUART Device Drivers *
* -------------------- *

; DUART sub-addresses (odd offset required)
MRA     EQU	$1	; Mode Register A	(if Reading)
SRA     EQU	$3	; Status Register A	(if Reading)
CSRA    EQU	$3	; Clock Select Register A	(if Writing)
CRA     EQU	$5	; Command Register A	(if Writing)
HRA     EQU	$7	; Holding Register A (Rx if Read, Tx if Write)
ACR     EQU	$9	; Auxiliary Control Register (if Writing)
; Other DUART definitions
MRA_rst	        EQU     $10     ; Reset MRA pointer to MR1A
RxA_rst	        EQU     $20     ; Software reset RxA
TxA_rst	        EQU     $30     ; Software reset TxA
ENABLE          EQU     $05     ; Tx/Rx Enable
BAUD_T2	        EQU     $80     ; Use 2nd baud rate table (for speed 19.2k)
BAUD_RATE	EQU     $CC     ; Baud rate value = 19,200
MR1_Set         EQU     $13     ; 8-bits, no parity, 1 stop bit
MR2_Norm        EQU     $07     ; Normal mode, CTS/RTS disabled, stop bit length = 1
MR2_Echo        EQU     $47     ; Auto-echo, CTS/RTS disabled, stop bit length = 1

Rx_rdy          EQU     $0      ; Recieve ready bit position
Tx_rdy          EQU     $2      ; Transmit ready bit position

INIT_SERIAL:
        move.l  A0,-(SP)    ; save state
        lea     DUART,A0    ; load pointer to duart memory

; Perform software reset
        move.b  #MRA_rst,CRA(A0)    ; RESET mode register pointer
        move.b  #RxA_rst,CRA(A0)    ; Reset Rx channel (and disable)
        move.b  #TxA_rst,CRA(A0)    ; Reset Tx channel (and disable)
; Initilize
        move.b  #BAUD_T2,ACR(A0)    ; Select baud rate table 2
        move.b  #BAUD_RATE,CSRA(A0) ; Select 19.2kHz baud rate Rx/Tx

        move.b  #MR1_Set,MRA(A0)    ; Select 8-bit mode, no parity, 1 stop bit
        move.b  #MR2_Norm,MRA(A0)   ; Normal mode, CTS/RTS disabled, stop bit length = 1

        move.b  #ENABLE,CRA(A0)     ; Enable Rx and Tx on channel A

        move.l  (SP)+,A0    ; restore state
        rts

* -- PUT_CHAR -- *
* Transmit a single character over serial
* parameters:
*   D1 - ASCII byte to send
PUT_CHAR:
        movem.l  D0/A0,-(SP)     ; save state
    IF.B    sim <EQ> #0 THEN.L
        lea     DUART,A0        ; load pointer to DUART memory
.wait   btst    #tx_rdy,SRA(A0) ; poll Tx status register
        beq     .wait           ; wait until Tx is ready
        move.b  D1,HRA(A0)      ; move byte to tx holding register A

    ELSE
        move.l  #06,D0          ; setup task 6, Display single ASCII char in D1
        trap    #15             ; call trap #15
    ENDI
        movem.l (SP)+,D0/A0     ; restore state
        rts

* -- GET_CHAR -- *
* Get a single character from serial connection into D1
* Uses trap 15 task 5 if running in simulator
* after execution:
*   D1 - Byte received
GET_CHAR:
        movem.l  D0/A0,-(SP)     ; save D0
    IF.B SIM <EQ> #0 THEN.L
        lea     DUART,A0        ; load pointer to DUART memory
.wait   btst    #Rx_rdy,SRA(A0) ; poll Rx status register
        beq     .wait           ; wait until Rx received
        move.b  HRA(A0),D1      ; Get byte from holding into D1
    ELSE
        move.l  #05,D0          ; setup trask 5, Read single ASCII character into D1
        trap    #15             ; call trap #15
    ENDI

        and.b   #$7F,D1         ; Strip MSB of input (ASCII is 7-bit)
    * Convert case
        tst.b   U_CASE(A6)      ; Test for conversion required
        bne     .echo           ; If not set, skip conversion
        btst    #6,D1           ; Test input for lower-case
        beq     .echo           ; If already upper, skip conversion
        and.b   #%11011111,D1   ; Else clear bit 5 for upper case conversion
    * Echo input
.echo   tst.b   ECHO(A6)        ; Test is echo input set
        bne.s   .exit           ; If ECHO global var not clear then no echo
        bsr     PUT_CHAR        ; Else software echo the input (look into loopback later)
.exit   movem.l  (SP)+,D0/A0    ; Restore state
        rts                     ; and return



* ----------------------- *
*    TEXT I/O ROUTINES    *
* ----------------------- *

* -- NEW_LINE -- *
* Moves cursur to start of newline
NEW_LINE:
        movem.l A1,-(SP)        ; save state
        lea     CRLF(PC),A1     ; point to CRLF string
        bsr     PRINT_STR       ; print it
        movem.l (SP)+,A1        ; restore state and return
        rts

* -- HEADING -- *
* Same as PRINT_STR but with leading and trailing newlines
*   A1 - pointer to null-terminated string
HEADING:
        bsr     NEW_LINE    ; Print a newline
        bsr     PRINT_STR   ; And the string in A1
        bra     NEW_LINE    ; Return from NEW_LINE routine

* -- PRINT_STR -- *
* parameters:
*   A1 - pointer to null-terminated string
PRINT_STR:
        move.l  D1,-(SP)    ; save state
.loop:  move.b  (A1)+,D1    ; Load next character in D1
        beq     .exit       ; If null then return (z-flag set)
        bsr     PUT_CHAR    ; otherwise print character.
        bra     .loop       ; Repeat with next char

.exit   move.l (SP)+,D1     ; restore state and return
        rts

* -- GET_LINE -- *
* Get a line of characters into the buffer
* parameters:
*   A6 should point to data area
* while executing:
*   A3 points to next free entry in line buffer
*   A2 points to end of buffer
*   A1 points to start of buffer
*   D1 holds character to be stored
GET_LINE:
    * Setup
        lea     LNBUFF(A6),A1   ; A1 points to start of line
        lea     (A1),A3         ; A3 points to start (initially)
        lea     MAXCHR(A1),A2   ; A2 points to end of buffer
    * Print prompt
        lea     PS1(PC),A1    ; Load prompt string
        bsr     PRINT_STR       ; and print it
    * Loop start
.cont   bsr     GET_CHAR        ; Receive a character in D1.
        cmp.b   #CTRL_C,D1      ; If CTRL^A then reject this line
        beq     .exit           ; and get another line.
        cmp.b   #BS,D1          ; If backspace then move back pointer
        bne     .proc           ; else skip past delete steps
        * Delete Steps
        cmp.l   A1,A3           ; Check if buffer is already empty.
        beq     .cont           ; If it is, get a new character.
        lea     -1(A3),A3       ; Else decrement buffer pointer (delete the char)
        bra     .cont           ; and continue with next character
    * Process char
.proc   move.b  D1,(A3)+        ; Store character and update head pointer
        cmp.b   #CR,D1          ; Test for command terminator
        bne     .chk            ; If not CR then skip past exit
    * Exit point
        bra     NEW_LINE         ; Else, print newline and exit from that routine
    * Check buffer
.chk    cmp.l   A2,A3           ; Test for buffer overflow
        bne     .cont           ; If buffer not full then continue
    * Loop end
.exit   bsr     NEW_LINE         ; Else move to next line,
        bra     GET_LINE        ; and repeat this routine

* -- CLEAN_UP -- *
* Clean up the line buffer by removing multiple and leading spaces.
* after execution:
* BUFFPT points to the first parameter following the command.
CLEAN_UP:
    * Setup
        lea     LNBUFF(A6),A0   ; A0 points to line buffer.
        lea     (A0),A1         ; A1 points to start of line buffer.
    * Find first non-space
.start  move.b  (A0)+,D0        ; Read character from buffer into D0.
        cmp.b   #SPACE,D0       ; Repeat until first non-space
        beq     .start          ; character is found.
        lea     -1(A0),A0       ; Backstep to first character (b/c post-increment used)
    * Remove leading spaces
.l1     move.b  (A0)+,D0        ; Move the string left to remove
        move.b  D0,(A1)+        ; any leading space
    * Remove multiple embedded space
        cmp.b   #SPACE,D0       ; Test for embedded space.
        bne     .eol            ; If not space, then test for line end.
.l2     cmp.b   #SPACE,(A0)+    ; If space skip multiple
        beq     .l2             ; embedded spaces.
        lea     -1(A0),A0       ; Move back pointer
.eol    cmp.b   #CR,D0          ; Test for line end (carriage return)
        bne     .l1             ; If not CR, then read next char
    * Find first param after initial chars
        lea     LNBUFF(A6),A0   ; Restore buffer pointer
.l3     cmp.b   #CR,(A0)        ; Test for end of line (carriage return)
        beq     .exit           ; If EOL, exit
        cmp.b   #SPACE,(A0)+    ; Test for space and increment
        bne     .l3             ; Repeat until delimiter or EOL
.exit   move.l  A0,BUFFPT(A6)   ; Update buffer pointer
        rts

* -- EXECUTE -- *
* Matches the command in the line buffer with command table
* and executes appropriate subroutine.
EXECUTE:
        lea     COMTAB(PC),A3   ; Search command table
        bsr     SEARCH
        bcs     .exec           ; If found then execute command
        lea     ER_INV(PC),A1   ; Else print invalid message
        bra     PRINT_STR       ; and tail return

.exec   move.l  (A3),A3         ; Get relative command address
        lea     COMTAB(PC),A4   ; pointed to by A3 and add it to
        add.l   A4,A3           ; the command table location to generate the actual
        jmp     (A3)            ; command address. Then execute it. (RTS provided)

* -- SEARCH -- *
* Recursively search through entries in the  command table
* pointed to by A3 for a command matching the first word
* in the line buffer.
* after execution:
*   A3 - Pointer to command subroutine vector (entry point address)
SEARCH:
        clr.l   D0
        move.b  (A3),D0         ; Get number of chars for command string
        beq     .exit           ; If zero then exit (table end reached)
        lea     6(A3,D0.W),A4   ; Calculate address of next command entry in A4 (for later)
        move.b  1(A3),D1        ; Get number of characters to match in D1

        lea     LNBUFF(A6),A5   ; Point A5 to command line buffer.
        move.b  2(A3),D2        ; Get first character for this entry in D2
        cmp.b   (A5)+,D2        ; and match with first char in buffer.
        beq     .skip           ; If match then check rest

.next   move.l  A4,A3           ; Else set pointer to next entry
        bra     SEARCH          ; and repeat this routine.

.skip   sub.b   #1,D1           ; Decrement characters to match
        beq     .end            ; If counter zero then finished
        lea     3(A3),A3        ; Else point to next character

.loop   move.b  (A3)+,D2        ; And match next character
        cmp.b   (A5)+,D2        ; from buffer (A5)
        bne     .next           ; If no match then try next entry
        sub.b   #1,D1           ; Else decrement match counter and
        bne     .loop           ; repeat until chars to match reaches 0

.end    lea     -4(A4),A3       ; Calculate address of command routine vector
        or.b    #1,CCR          ; Set carry flag to indicate success
        rts                     ; and return

.exit   and.b   #$FE,CCR        ; Fail - clear carry to indicate
        rts                     ; command not found and return

* -- PARAM -- *
* Read the next parameter (longword) from the command line buffer
* Resulting converted longword is placed in PARAMTR(A6) and D1
* Sets D7 bit 1 if conversion error occurs
PARAM:
        movem.l  D2/A0,-(SP)    ; Save state
        clr.l   D2              ; Clear input accumulator
        move.l  BUFFPT(A6),A0   ; Get pointer to first parameter in A0

.loop   move.b  (A0)+,D1        ; Get character from line buffer
        cmp.b   #SPACE,D1       ; Test for delimiter
        beq     .exit           ; and exit

        asl.l   #4,D2           ; Shift accumulated result 4 bits left
        sub.b   #$30,D1         ; Convert ASCII char to hex
        bmi     .error          ; If result less than $30, then not valid hex
        cmp.b   #$09,D1         ; If less than 10
        ble     .cont           ; then continue
        sub.b   #$07,D1         ; Else convert to range $A-$F
        cmp.b   #$0F,D1         ; If more than $F
        bgt     .error          ; then exit to non-hex error

.cont   add.b   D1,D2           ; Add latest nybble to total in D2
        cmp.b   #CR,(A0)        ; See if next char is carriage return
        beq     .exit           ; Exit if so
        bra     .loop           ; Otherwise repeat until delimiter found
.exit   move.l  A0,BUFFPT(A6)   ; Save pointer (to next parameter) in memory
        move.l  D2,PARAMTR(A6)  ; Save parameter in memory
        move.l  D2,D1           ; Put parameter in D1 for return
        bra     .end            ; Return without error

.error  or.b    #2,D7           ; Set error flag before return
.end    movem.l  (SP)+,D2/A0    ; Restore state
        rts                     ; return (with error if set)

* ------------------ *
*  UTILITY ROUTINES  *
* ------------------ *

* -- HEX INPUT -- *
* Read characters from serial and convert to number in D1
* Sets D7 bit 0 if hex input error occurs
*   - HEX    =   Get 1 hex digits in D1
*   - BYTE   =   Get 2 hex digits in D1
*   - WORD   =   Get 4 hex digits in D1
*   - LONGWD =   Get 8 hex digits in D1
HEX:
        bsr     GET_CHAR        ; Read character from console into D1
hack2   sub.b   #$30,D1         ; Convert ASCII to binary
        bmi     .inv            ; Exit with error if result less than $0
        cmp.b   #$09,D1         ; Test for numeric range
        ble     .exit           ; If number then exit successfully,
        sub.b   #$07,D1         ; else convert to $A-$F range
        cmp.b   #$0F,D1         ; If in range
        ble     .exit           ; exit successfully
.inv    or.b    #1,D7           ; If invalid set error flag
.exit   rts                     ; and return
BYTE:
* Get a byte
        move.l  D2,-(SP)        ; Save working register
        bsr     HEX             ; Get first hex char in D1
hack3   asl.b   #4,D1           ; Move it into MS position
        move.b  D1,D2           ; Save MS nybble in D2
        bsr     HEX             ; Get next nybble
        add.b   D2,D1           ; Merge MS and LS nybbles
        move.l  (SP)+,D2        ; Restore state
        rts                     ; and return
WORD:
* Get a word
        bsr     BYTE            ; Get upper byte
        asl.w   #8,D1           ; Shift to MS position
        bra     BYTE            ; Get lower byte, tail return
LONGWD:
        bsr     WORD            ; Get upper word
        swap    D1              ; Move to MS position
        bra     WORD            ; Get lower word, tail return

* -- HEX OUTPUT -- *
* Converts data in D1 to ascii and prints it
*   - OUT1X  =  Print 1 Hex character
*   - OUT2X  =  Print 2 Hex characters
*   - OUT4X  =  Print 2 Hex characters
*   - OUT8X  =  Print 2 Hex characters
OUT1X:
* Print single character (nybble)
        move.b  D1,-(SP)        ; Save D1
        and.b   #$0F,D1         ; Isolate first nybble
        add.b   #$30,D1         ; Convert to ascii (value + 0x30)
        cmp.b   #$39,D1         ; Check if out of numeric range
        bls     .print          ; if not, print numeric char
        add.b   #$07,D1         ; Else, add extra 7 for capital A-F range
.print  bsr     PUT_CHAR        ; Print the character in D1
        move.b  (SP)+,D1        ; Restore original value in D1
        rts                     ; and return
OUT2X:
* Print a byte
        ror.b   #4,D1           ; Swap MS and LS nybble
        bsr     OUT1X           ; Print MS nybble first
        rol.b   #4,D1           ; Restore LS nybble
        bra     OUT1X           ; Print LS nybble last, tail return
OUT4X:
* Print a word
        ror.w   #8,D1           ; Swap MS and LS bytes
        bsr     OUT2X           ; Print MS byte first
        rol.w   #8,D1           ; Restore LS byte
        bra     OUT2X           ; Print LS byte last, tail return
OUT6X:
* Print a representation of an address (24 bits, 6 bytes)
        swap    D1              ; Swap high and low words
        bsr     OUT2X           ; Print most significant byte
        swap    D1              ; Swap back to original
        bra     OUT4X           ; Print low word
OUT8X:
* Print a longword (4 bytes)
        swap    D1              ; Swap high and low words
        bsr     OUT4X           ; Print high word
        swap    D1              ; Swap back to original
        bra     OUT4X           ; Print low word, tail return

P_SPACE:
* Prints a single space
* Saving and restoring D1 on the stack
        move.b  D1,-(SP)        ; Save working register
        move.b  #SPACE,D1       ; Load and print space
        bsr     PUT_CHAR        ; character
        move.b  (SP)+,D1        ; Restore state
        rts                     ; and return

DELAY:
* Provides a small delay. Used in srec loading for host
* to process input
        move.l  D0,-(SP)        ;
        move.l  #$4000,D0       ;
.wait   sub.l   #1,D0
        bne     .wait
        move.l  (SP)+,D0
        rts


* ---------------------- *
*    COMMAND ROUTINES    *
* ---------------------- *

* -- HELP -- *
* Prints help string and info
HELP:
        lea     HLP_MSG(PC),A1  ; Load help message string
        bra     PRINT_STR       ; and tail return

CLEAR:
        move.b  #CTRL_L,D1      ; Load CTRL-L char in D1
        bra     PUT_CHAR        ; Send character

* -- JUMP -- *
* Jump causes execution to begin at the address specified
* Syntax JUMP <address>
JUMP:
        bsr     PARAM           ; Get address from command buffer
        tst.b   D7              ; Test for error bit set
        bne     .err            ; If error flag not 0, exit with error
        tst.l   D1              ; Else test for missing argument
        beq     .err            ; If no address provided, exit with error
        move.l  D1,A0           ; Otherwise load A0 with address
        jmp     (A0)            ; and call the subroutine. USER to provide RTS!!
.err    lea     ER_HEX(PC),A1   ; If error,load error message,
        bra     PRINT_STR       ; print and tail return


* -- MEMORY MODIFY -- *
* Display data at a location specified in parameter
* Syntax: MM <address>
MEM_MOD:
        bsr     PARAM           ; Get start address from line buffer into D1
        tst.b   D7              ; Test for input error
        bne     .er1            ; If error then exit
    * Setup
        lea     MM_MSG(PC),A1   ; Load usage message
        jsr     PRINT_STR       ; and print it
        move.l  D1,A3           ; Load A3 with pointer to memory from parameter
    * Repeat until user enters [ESC]
.loop   bsr     NEW_LINE        ; Print newline
        bsr     OUT_MEM         ; Print current address and contents (increments A3)
        bsr     P_SPACE         ; and a space
        bsr     GET_CHAR        ; then wait for user input
        cmp.b   #ESC,D1         ; If input is <ESC> or Ctrl-C
        beq     .exit           ; exit
        cmp.b   #CTRL_C,D1
        beq     .exit
        cmp.b   #BS,D1          ; If input is <BACK> (CTRL^H) character, go backwards
        bne     .sk1            ; Else skip backstep procedure
    * Backstep
        lea     -2(A3),A3       ; Move pointer back 2 bytes
        bra     .loop           ; Repeat until <ESC> to exit
.sk1    cmp.b    #CR,D1         ; Test for <CR> for next entry
        beq     .loop           ; If <CR> then display next location

    * Hack to intercept GET_BYTE routine to include nibble already in D1
        move.l  #.cont,-(SP)    ; Else manipulate the stack return address to get a byte to store
        move.l  D2,-(SP)        ; Save D2 to match stack pop at end of BYTE routine
        move.l  #hack3,-(SP)    ; Prime stack return address with middle of BYTE routine
        bra     hack2           ; Branch to the middle of the first HEX call in BYTE routine
    * Test for input error
.cont   tst.b   D7              ; Test for input error
        bne     .er2            ; Goto error exit if invalid input
        ; lea     ER_HEX(PC),A1 ; Load error message
        ; bra     PRINT_STR     ; and print it (tail return)
        move.b  D1,-1(A3)       ; Store new byte (A3 was post incremented)
        bra     .loop           ; Repeat until <ESC>
.exit   rts
.er1    lea     MM_ERR(PC),A1
        bra     PRINT_STR
.er2    lea     ER_HEX(PC),A1   ; Print error messages here
        bra     PRINT_STR

OUT_MEM:
* Print the pointer in A3 and the byte pointed to by A3
* Increments A3 by 1 after execution:
        move.l  D1,-(SP)        ; Save working register
        move.l  A3,D1           ; Load A3 into input for output address routine
        bsr     OUT6X           ; Print 8 nybbles (4 bytes, long word)
        bsr     P_SPACE         ; Print single space
        move.b  (A3)+,D1        ; Move byte data at this address into D1
        bsr     OUT2X           ; and display it
        move.l  (SP)+,D1        ; Restore state
        rts                     ; and return


* -- MEMORY DUMP -- *
* Hex Dump a block of data in memory
* Each line has 16 bytes and the corresponding ascii characters
* Starting address is aligned to 16 bytes
* C020    31 32 33 34 35 36 37 38 39 FF FF FF FF FF FF    123456789......
* Syntax: MD <addr1> [addr2]
* If addr2 omitted, print 9 lines from starting point
MEM_DMP:
        bsr     PARAM           ; Get starting address in D1
        tst.b   D7              ; Test for input error
        bne     .er1            ; If error then exit
        and.l   #$FFFFF0,D1     ; Truncate input to 6 bytes and align to 16 bytes
        cmp.l   #DUART,D1       ; Ensure only memory from Ram/Rom can be displayed
        bge     .er2            ; Reading randomly from the DUART space can cause issues
        move.l  D1,A3           ; Move start to A3
* Optional second parameter
        bsr     PARAM           ; Get second parameter in D1
        tst.b   D7              ; Error test again
        beq     .sk1            ; If error on second argument just
        move.l  A3,D1           ; print 9 lines of 16 bytes
        add.l   #$90,D1         ; by default if no second argument supplied
.sk1    move.l  D1,A4           ; Store end address in A4
* Print heading
        lea     MD_MSG(PC),A1
        bsr     PRINT_STR
    * Outer loop (print lines)
.lp3    move.l  A3,D1           ; Load starting address into A3
        bsr     OUT6X           ; and print the 6 byte address

.word   lea     DIV_1(PC),A1    ; Load space separator,
        bsr     PRINT_STR       ; and print it

    * Inner loop 1 (print raw bytes)
        move.w  #15,D6          ; Load loop counter for 16 loops
.lp1    move.b  (A3)+,D1        ; Print byte at A3
        bsr     OUT2X           ; and increment pointer
        bsr     P_SPACE         ; Print spaces between bytes
        dbra    D6,.lp1         ; loop 16 times

    * Prepare for ascii section
        lea     DIV_2(PC),A1     ; Load space separator
        bsr     PRINT_STR        ; and print it

        lea     -16(A3),A3      ; Backup A3 16 bytes

    * Inner loop 2 (print data as characters)
        move.w  #15,D6          ; Load loop counter for another 16 loops
.lp2    move.b  (A3)+,D1        ; Get byte at A3 into register, prime next byte
        cmp.b   #$20,D1         ; If data not in printable ASCII range
        blt     .unp            ; Use a placeholder character ('-')
        cmp.b   #$7E,D1         ;
        ble     .print          ; Else skip to printing D1
.unp    move.b  #'-',D1         ; Load non-printable placeholder
.print  bsr     PUT_CHAR        ; Print ASCII data (or non printable)
        dbra    D6,.lp2         ; loop 16 times

        bsr     NEW_LINE        ; Print newline

        cmp.l   A4,A3           ; Reached end of range?
        ble     .lp3            ; Loop until entire range printed
        rts                     ; Else, exit if finished
    * Error occurred
.er1    lea     ER_HEX(PC),A1   ; Load error message
        bra     PRINT_STR       ; Print and return
.er2    lea     ER_MEM(PC),A1
        bra     PRINT_STR

; IS_ASCII:
; * Check if byte in D1 is in ascii range
;         cmp.b   #20,D1
;         blt     .unp
;         cmp.b   #$7E,D1
;         ble     .print
; .unp    or.b    #2,D7
; .print  rts


* -- REGISTERS -- *
* The state of volatile registers are saved to a frame structure
* in memory before an exception in execution.
*   ---------------
*   | D0-D7 (7 L) |
*   ---------------
*   | A0-A6 (6 L) |
*   ---------------
*   |  SSP (1 L)  |
*   ---------------
*   |  SR (1 W)   |
*   ---------------
*   |  PC (1 L)   |
*   ---------------
* Modify a register stored in the display frame.
* Syntax: RM <reg> <value>. E.g. RM D2 1200
REG_MOD:
    * Parse register parameter
        clr.l   D1              ; D1 holds the name of the register
        lea     BUFFPT(A6),A0   ; Get address of pointer to first param in line buffer
        move.l  (A0),A0         ; Dereference pointer. A0 contains address of first char in buffer

        move.b  (A0)+,D1        ; Get one byte at time in case of odd address
        rol.w   #8,D1           ; Shift first character of param left
        move.b  (A0)+,D1        ; Get second char in D1 LSB position
    * Setup next parameter
        lea     1(A0),A0        ; Move pointer past space between params
        move.l  A0,BUFFPT(A6)   ; Update buffer pointer
    * Loop setup
        clr.l   D2              ; D2 stores index of matched register
        lea     REGS(PC),A0     ; A0 points to string of register names
        ; lea     (A0),A1         ; Copy A0 to A1 as well (?)
.loop   cmp.w   (A0)+,D1        ; Compare character pair to parameter in D1
        beq     .found          ; If match found then exit loop
        add.l   #1,D2           ; Else increment match counter
        cmp.l   #19,D2          ; Test for end of loop (Register not found)
        bne     .loop           ; Continue until all pairs searched
    * Match error
        lea     ER_REG(PC),A1   ; If here then input error.
        bra     PRINT_STR       ; Display error message and tail return
    * Calculate selected register location
.found  lea     REG_F(A6),A1    ; A1 points to pseudo register frame
        asl.l   #2,D2           ; Multiply register number by 4 (4 bytes/entry)
        cmp.l   #72,D2          ; Test if PC was selected (last entry)
        bne     .calc           ; If not PC then finished
        sub.l   #2,D2           ; Else decrement by 2 because SR is a word (2 bytes)
.calc   lea     (A1,D2),A2      ; Calculate address of entry in display table
        move.l  (A2),D1         ; Get old contents
        bsr     OUT8X           ; and display them
        bsr     NEW_LINE
        bsr     PARAM           ; Get new value
        tst.b   D7              ; Test for input error
        beq     .store          ; If no error then goto store data
        lea     ER_HEX(PC),A1   ; Else, load error message
        bra     PRINT_STR       ; Display and tail return
    * Store 'register' value in frame
.store  cmp.l   #68,D2          ; If the Status Register was selected then
        beq     .word           ; only a word to store
        move.l  D1,(A2)         ; Else store new data in memory frame
        rts
.word   move.w  D1,(A2)         ; Store one word SR
        rts

* -- DISPLAY -- *
* Display the saved registers in the data frame
* Saved in REG_F global table
DISP:
        lea     REG_F(A6),A5        ; A5 points to display frame
        lea     DISP_MSG(PC),A1     ; Point to heading message
        bsr     PRINT_STR           ; and print it
        move.w  #7,D6               ; 8 pairs of registers to display
        clr.b   D5                  ; D5 is the line counter
.loop   move.b  D5,D1               ; Put current register number in D0
        bsr     OUT1X               ; and print it
        bsr     P_SPACE             ; and a space
        add.b   #1,D5               ; Update counter for the next pair
        move.l  (A5),D1             ; Get register data from frame
        bsr     OUT8X               ; and display it
        lea     SP_10(PC),A1        ; Point to spaces
        bsr     PRINT_STR           ; and print it
        move.l  32(A5),D1           ; Data address register from frame
        bsr     OUT8X               ; which is 32 byte offset from corresponding D-reg
        bsr     NEW_LINE            ;
        lea     4(A5),A5            ; Increment pointer to next register
        dbra    D6,.loop            ; Repeat until all 8 pairs displayed
    *
        lea     32(A5),A5           ; Adjust pointer by 8 longwords
        bsr     NEW_LINE            ; to point to SSP
        lea     D_MSG1(PC),A1       ; Point to "SSP ="
        bsr     PRINT_STR           ; Print it
        move.l  (A5)+,D1            ; Get System Stack Pointer
        jsr     OUT8X               ; and print it
        bsr     NEW_LINE
    *
        lea     D_MSG2(PC),A1       ; Point to "SR ="
        bsr     PRINT_STR           ; Print it
        move.w  (A5)+,D1            ; Get status register
        bsr     OUT4X               ; Print it
        bsr     NEW_LINE
    *
        lea     D_MSG3(PC),A1       ; Point to "PC ="
        bsr     PRINT_STR           ; Print it
        move.l  (A5)+,D1            ; Get Program counter
        bsr     OUT8X               ; Print it
        bra     NEW_LINE            ; Newline and tail return


* --------------- *
*    LOAD SREC    *
* --------------- *
* Load an assembled s-record formatted program into RAM storage
* While executing: D3 - Checksum accumulator, D2 - Byte count to read
*                  D1 - Current byte read,    A2 - Destination address
LOAD:
        ; add.b   #1,ECHO(A6)         ; Disable auto echo
        bsr     NEW_LINE            ;
        ; bsr     DELAY               ; Wait for host to settle (?)
        ; bsr     DELAY               ;
    * Transmit string argument (srecord file name to load)
        move.l  BUFFPT(A6),A4       ;
.arg    move.b  (A4)+,D1            ; Read from buffer
        bsr     PUT_CHAR            ; and output characters
        cmp.b   #CR,D1              ; until End of Line
        bne     .arg
        bsr     NEW_LINE            ; Send an extra newline to indicate ready for transmision
    * Check for end
.next   bsr     GET_CHAR            ; Each line of records must start
        cmp.b   #CTRL_C,D1          ; Exit load loop
        beq     .exit               ; when CTRL-C received
        cmp.b   #'S',D1             ; Else, check for start of record
        bne     .next               ; Must start with S1/S2 (data) or S9/S8 (termination)
        bsr     GET_CHAR            ; Get character after the 'S'
        cmp.b   #'9',D1             ; Test for S9 or S8 terminators
        beq     .exit               ; If S9 type then check for errors and exit
        cmp.b   #'8',D1             ; else test for S8 type, fall through to exit
        bne     .data               ; else goto process data type record
    * Load exit point
.exit   clr.b   ECHO(A6)            ; Enable automatic echo
        btst    #0,D7               ; Test for input error
        beq     .chk                ; If no input error, check checksum error
        lea     ER_HEX(PC),A1       ; Else, Load and print error message
        bsr     PRINT_STR           ; continue to also handle checksum error
.chk    btst    #2,D7               ; Test for checksum error
        beq     .rts                ; If clear then exit
        lea     ER_LOD(PC),A1       ; If error, then load error message
        bsr     PRINT_STR           ; and Print it
.rts    rts                         ; Return from LOAD
    * Check data record type (S1/S2)
.data   cmp.b   #'1',D1             ; Test for S1 type record
        beq     .s1                 ; If S1 then read it
        cmp.b   #'2',D1             ; Else test for S2 record
        bne     .next               ; If unsupported type, skip to next one
    * Process 3-byte addr for S2 type record
        clr.b   D3                  ; Else S2 type. Clear initial checksum
        bsr     .read1              ; Get the record length in D1
        sub.b   #4,D1               ; Subtract 4 from record length (3 byte address, 1 chksum)
        move.b  D1,D2               ; D2 holds byte count to be read
        clr.l   D1                  ; Clear D1 to accumulate address
        bsr     .read1              ; Read most significant byte of address
        asl.l   #8,D1               ; Shift one byte left
        bsr     .read1              ; Read middle byte of address
        asl.l   #8,D1               ; Shift both one byte left
        bsr     .read1              ; Read last byte of address
        move.l  D1,A2               ; A2 points to destination of data
        bra     .store              ; Skip S1 processing section
    * Process 2-byte addr for S1 type record
.s1     clr.b   D3                  ; S1 record found. Clear checksum
        bsr     .read1              ; Get length byte and update checksum
        sub.b   #3,D1               ; Subtract 3 from record length (2 byte address, 1 chksum)
        move.b  D1,D2               ; D2 holds byte count to be read
        clr.l   D1                  ; Clear D1 to accumulate address
        bsr     .read1              ; Get MS byte of destination address
        asl.l   #8,D1               ; Shift MS byte in position
        bsr     .read1              ; Get LS byte in D2
        move.l  D1,A2               ; A2 points to destination of data
    * Read n bytes and store starting at addr in A3
.store  bsr     .read1              ; Read byte of data from record
        move.b  D1,(A2)+            ; Store it
        sub.b   #1,D2               ; Decrement byte counter
        bne     .store              ; Loop until all bytes read
    * Final checksum calculation
    * Byte sum of length + address + data + checksum + 1 should = 0
        bsr     .read1              ; Read checksum (final byte)
        add.b   #1,D3               ; Add 1 to calculated sum
        beq     .next               ; If zero (chk passed) then start next record
        or.b    #%0000100,D7        ; Else set checksum error bit flag
        bra     .exit               ; and cleanup and exit LOAD

    * Utility to get a byte from the srec and update running sum
.read1  bsr     BYTE                ; Get a byte in D1
        add.b   D1,D3               ; Update checksum
        rts

* ------------------- *
*    COMMAND TABLE    *
* ------------------- *
* Built in command table. All entries are string length + number of chars to match
* + the string and the address of the command subroutine relative to COMTAB
*        ------------------
* 1 byte | command length |
*        ------------------
* 1 byte | chars to match |
*        ------------------
* 4 byte |   rel command  |
*        |    address     |
*        -----------------
COMTAB: DC.B    4,1
        DC.B    'HELP'
        DC.L    HELP-COMTAB
    *
        DC.B    6,5
        DC.B    'CLEAR '
        DC.L    CLEAR-COMTAB
    *
        DC.B    4,2
        DC.B    'MM  '
        DC.L    MEM_MOD-COMTAB
    *
        DC.B    4,2
        DC.B    'MD  '
        DC.L    MEM_DMP-COMTAB
    *
        DC.B    4,2
        DC.B    'RM  '
        DC.L    REG_MOD-COMTAB
    *
        DC.B    6,4
        DC.B    'DISP '
        DC.L    DISP-COMTAB
    *
        DC.B    6,4
        DC.B    'LOAD  '
        DC.L    LOAD-COMTAB
    *
        DC.B    4,3
        DC.B    'JMP '
        DC.L    JUMP-COMTAB
    *
        DC.B    0,0         ; End of table


* ---------------------- *
*       STRING DATA      *
* ---------------------- *

* -- Symbol equates -- *
BS:         EQU     $08     ; Backspace
CR:         EQU     $0D     ; Carriage Return
LF:         EQU     $0A     ; Line Feed
ESC:        EQU     $1B     ; Escape
SPACE:      EQU     $20     ; Space
NUL:        EQU     $00     ; Null
CTRL_A:     EQU     $01     ; Quits line editing
CTRL_C:     EQU     $03     ; Quits line editing
CTRL_L:     EQU     $0C     ; Clear console
EOT:        EQU     $04     ; End-of-Transmission ctrl^d

* Null terminated strings *

CRLF:   DC.B    CR,LF,0
BANNER:
        DC.B            CR,LF,'                    | |/ /___  _ __ ___   ___   __| | ___'
        DC.B            CR,LF,'                    | ',$27,' // _ \| ',$27,'_ ` _ \ / _ \ / _` |/ _ \'
        DC.B            CR,LF,'                    | . \ (_) | | | | | | (_) | (_| | (_) |'
        DC.B            CR,LF,'                    |_|\_\___/|_| |_| |_|\___/ \__,_|\___/'
        DC.B            CR,LF,CR,LF,'                            Komodo Monitor v0.1.0'
        DC.B            CR,LF,'(Type HELP for help)',CR,LF,0

PS1:  DC.B    '$> ',0

HLP_MSG:
        DC.B    CR,LF,'Welcome to the Komodo Monitor v0.1.0 for M68k processor'
        DC.B    CR,LF
        DC.B    CR,LF,'                       )/_'
        DC.B    CR,LF,'             _.--..---',$22,'-,--c_'
        DC.B    CR,LF,'        \L..',$27,'           ._O__)'
        DC.B    CR,LF,',-.     _.+  _  \..--( /'
        DC.B    CR,LF,'  `\.-',$27,$27,'__.-',$27,$27,' \ (     \_'
        DC.B    CR,LF,'    `',$27,$27,$27,'       `\__   /\'
        DC.B    CR,LF,'               ',$27,')'
        DC.B    CR,LF,'COMMANDS:'
        DC.B    CR,LF,'> DISP                 - Display Registers, PC, and Status'
        DC.B    CR,LF,'> RM   <reg>  <value>  - Set a new value for any of D0-D7, A0-A7, SS, SR, PC'
        DC.B    CR,LF,'> MM   <address>  - Modify data in any writable location (some is protected)'
        DC.B    CR,LF,'> MD   <addr1> [addr2] - Print a block of formatted data from any readable location'
        DC.B    CR,LF,'> LOAD (string) - Load S-Record data over serial port. "string" is sent to host'
        DC.B    CR,LF,'> JMP  <address> - Begin execution at provided address'
        ; DC.B    CR,LF,'> [T]             - Execute program in RAM'
        DC.B    CR,LF,'> CLEAR         - Clear the screen'
        DC.B    CR,LF,'> HELP          - Display this message'
        DC.B    CR,LF
        DC.B    CR,LF,'Created for the final project of Microcomputer Design, 2022'
        DC.B    CR,LF,'Author: Jackson Miller'
        DC.B    CR,LF,'Website: www.github.com/jack-mil/mcd-asm',0

DISP_MSG:
        DC.B    CR,LF,'  Data reg         Address reg',CR,LF,0
SP_10:  DC.B    '          ',0
D_MSG1: DC.B    'SSP =',0
D_MSG2: DC.B    'SR  =',0
D_MSG3: DC.B    'PC  =',0

MM_ERR: DC.B    CR,LF,'Syntax: MM <addr>. Must be within RAM 010000 - 01FFFF',CR,LF,0
MM_MSG: DC.B    '[BACKSP] previous byte | [ENTER] next byte | [ESC] to exit',0

MD_MSG: DC.B    CR,LF,'Address:   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F     0123456789ABCDEF',CR,LF,0
DIV_1:  DC.B    '  |  ',0
DIV_2:  DC.B    ' |  ',0

ER_INV: DC.B    CR,LF,'Invalid command (Type [H]elp for list of commands)',CR,LF,0
ER_HEX: DC.B    CR,LF,'Invalid hex input',CR,LF,0
ER_REG: DC.B    CR,LF,'Invalid register name',CR,LF,0
ER_MEM: DC.B    CR,LF,'Invalid memory access',CR,LF,0
ER_LOD: DC.B    CR,LF,'Load error (Checksum invalid) ',CR,LF,0

* Register name pairs are used for matching parameters for RM command
        DS.W    0       ; Force even word alignment here
REGS:   DC.B    'D0D1D2D3D4D5D6D7'
        DC.B    'A0A1A2A3A4A5A6A7'
        DC.B    'SSSRPC  ',0
* ---------------------- *
    END RESET

