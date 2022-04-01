* ------------------- *
* M68k system monitor
* Jackson Miller
* MCD 2022
* ------------------- *

* -- Symbol equates -- *
BS:         EQU     $08     ; Backspace
CR:         EQU     $0D     ; Carriage Return
LF:         EQU     $0A     ; Line Feed
SPACE:      EQU     $20     ; Space
NUL:        EQU     $00     ; Null
CTRL_A:     EQU     $01     ; Quits line editing
CTRL_C:     EQU     $03     ; Quits line editing
EOT:        EQU     $04     ; End-of-Transmission ctrl^d

* -- Device addresses -- *
ROM:        EQU     $000000     ; ROM Start
RAM:        EQU     $010000     ; RAM Start
DUART:      EQU     $020000     ; DUART base address

STACK:      EQU     $020000     ; Location of stack (grows up from bottom of RAM)
MAXCHR:     EQU     64          ; Length (bytes) of input line buffer

* Data and global variable definition
DATA:       EQU     RAM+$C00    ; Data origin
LNBUFF:     DS.B    MAXCHR      ; Input line buffer
BUFFEND:    EQU     LNBUFF+MAXCHR-1 ; end of line buffer
BUFFPT:     DS.L    1           ; Pointer to line buffer
PARAMTR:    DS.L    1           ; Last parameter from line buffer
ECHO:       DS.B    1           ; Enable input echo when clear
U_CASE:     DS.B    1           ; Flag for upper-case conversion


* -- Simulator select bit -- *
sim:        EQU     $1          ; 1 -> simulator / 0 -> hardware


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

        move.l  #758*$10000+700,D1 ; Set screen size to 80 x 
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
        bsr     HEADING         ; and print it

WARM:   clr.l   D7              ; Warm entry point - clear error flag
        bsr     NEW_LINE        ; Print a newline
        bsr     GET_LINE        ; Get command line
        bsr     CLEAN_UP        ; Clean up readline buffer contents
        bsr     EXECUTE         ; Interpret command
        bra     WARM            ; Repeat forever


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
        move.l  D0,-(SP)    ; save state
.loop:  move.b  (A1)+,D1    ; Load next character in D0
        beq     .exit       ; If null then return (z-flag set)
        bsr     PUT_CHAR    ; otherwise print character.
        bra     .loop       ; Repeat with next char

.exit   move.l (SP)+,D0     ; restore state and return
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
        lea     PRMT(PC),A1     ; Load prompt string
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
        bra     PRINT_STR       ; and return

.exec   move.l  (A3),A3         ; Get relative command address
        lea     COMTAB(PC),A4   ; pointed to by A3 and add it to
        add.l   A4,A3           ; The PC to generate the actual
        jmp     (A3)            ; command address. Then execute it.

* -- SEARCH -- *
* Recusivly search through entries in the  command table
* pointed to by A3 for a command matching the first word
* in the line buffer.
* after execution:
*   A3 - Pointer to command subroutine vector (entry point address)
SEARCH:
        clr.l   D0
        move.b  (A3),D0         ; Get number of chars for command string
        beq     .fail           ; If zero then exit
        lea     6(A3,D0.W),A4   ; Calculate address of next command entry in A4 (for later)
        move.b  1(A3),D1        ; Get number of characters to match

        lea     LNBUFF(A6),A5   ; Point A5 to command line buffer.
        move.b  2(A3),D2        ; Get first character for this entry
        cmp.b   (A5)+,D2        ; from the table and match with buffer.
        beq     .cont           ; If match then check rest

.next   move.l  A4,A3           ; Else set pointer to next entry
        bra     SEARCH          ; and repeat this routine.

.cont   sub.b   #1,D1           ; Decrement characters to match
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

.fail   and.b   #$FE,CCR        ; Fail - clear carry to indicate
        rts                     ; command not found and return


* -------------------- *
* DUART Device Drivers *
* -------------------- *

; DUART sub-addresses (odd offset required)
MRA	    EQU	$1	; Mode Register A	(if Reading)
SRA	    EQU	$3	; Status Register A	(if Reading)
CSRA	EQU	$3	; Clock Select Register A	(if Writing)
CRA	    EQU	$5	; Command Register A	(if Writing)
HRA	    EQU	$7	; Holding Register A (Rx if Read, Tx if Write)
ACR	    EQU	$9	; Auxiliary Control Register (if Writing)
; Other DUART definitions
MRA_rst	    EQU	$10	; Reset MRA pointer to MR1A
RxA_rst	    EQU	$20	; Software reset RxA
TxA_rst	    EQU	$30	; Software reset TxA
ENABLE  	EQU	$05	; Tx/Rx Enable
BAUD_T2	    EQU	$80	; Use 2nd baud rate table (for speed 19.2k)
BAUD_RATE	EQU	$CC	; Baud rate value = 19,200
MR1_Set     EQU	$13	; 8-bits, no parity, 1 stop bit
MR2_Norm	EQU	$07	; Normal mode, CTS/RTS disabled, stop bit length = 1
MR2_Echo	EQU	$47	; Auto-echo, CTS/RTS disabled, stop bit length = 1

Rx_ready	EQU	$0	; Recieve ready bit position
Tx_ready	EQU	$2	; Transmit ready bit position

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
        move.l  D0,-(SP)     ; save state
    IF.B    sim <EQ> #0 THEN.L
        lea     DUART,A0        ; load pointer to DUART memory
.wait   move.b  SRA(A0),D0      ; poll status register
        btst    #tx_ready,D0    ;
        beq     .wait           ; wait until Tx is ready
        move    D1,HRA(A0)      ; move byte to tx holding register A

    ELSE
        move.l  #06,D0          ; setup task 6, Display single ASCII char in D1
        trap    #15             ; call trap #15
    ENDI
        move.l (SP)+,D0     ; restore state
        rts

* -- GET_CHAR -- *
* Get a single character from serial connection into D1
* Uses trap 15 task 5 if running in simulator
* after execution:
*   D1 - Byte received
GET_CHAR:
        movem.l  D0/A0,-(SP)        ; save D0
    IF.B SIM <EQ> #0 THEN.L
        lea     DUART,A0        ; load pointer to DUART memory
.wait   move.b  SRA(A0),D0      ; poll status register
        btst    #Rx_ready,D0    ; wait for input
        beq     .wait
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
        DC.B    0,0         ; End of table


* ---------------------- *
*    COMMAND ROUTINES    *
* ---------------------- *

* -- HELP -- *
* Prints help string and info
HELP:
        lea     HLP_MSG(PC),A1  ; Load help message string
        bra     PRINT_STR       ; and return



* ---------------------- *
*         STRINGS        *
* ---------------------- *
CRLF:   DC.B    CR,LF,0
BANNER:
        DC.B                  '                    | |/ /___  _ __ ___   ___   __| | ___'
        DC.B            CR,LF,'                    | ',$27,' // _ \| ',$27,'_ ` _ \ / _ \ / _` |/ _ \'
        DC.B            CR,LF,'                    | . \ (_) | | | | | | (_) | (_| | (_) |'
        DC.B            CR,LF,'                    |_|\_\___/|_| |_| |_|\___/ \__,_|\___/'
        DC.B            CR,LF,CR,LF,'                            Komodo Monitor v0.1.0'
        DC.B            CR,LF,'(Type HELP for help)',CR,LF,0

PRMT:   DC.B    CR,LF,'$> ',0

;                        )/_
;              _.--..---"-,--c_
;         \L..'           ._O__)_
; ,-.     _.+  _  \..--( /           a:f
;   `\.-''__.-' \ (     \_      
;     `'''       `\__   /\
;                 ')

HLP_MSG:
        DC.B   CR,LF,'Welcome to the Komodo Monitor v0.1.0 for M68k processor'
        DC.B   CR,LF
        DC.B   CR,LF,'                       )/_'
        DC.B   CR,LF,'             _.--..---"-,--c_'
        DC.B   CR,LF,'        \L..',$27,'           ._O__)'
        DC.B   CR,LF,',-.     _.+  _  \..--( /'
        DC.B   CR,LF,'  `\.-',$27,$27,'__.-',$27,$27,' \ (     \_'
        DC.B   CR,LF,'    `',$27,$27,$27,'       `\__   /\'
        DC.B   CR,LF,'               ',$27,')'
        DC.B   CR,LF,'COMMANDS:'
        DC.B   CR,LF,'> [RM]  (REG)  - Display or modify any D0-D7, A0-A6 register'
        DC.B   CR,LF,'> [MD]  (LOC)  - Display data in any readable location'
        DC.B   CR,LF,'> [MM]  (LOC)  - Modify data in any writable location (some is protected)'
        DC.B   CR,LF,'> [L]OAD (string) - Load S-Record data over serial port. "string" is sent to host'
        DC.B   CR,LF,'> [T]             - Execute program in RAM'
        DC.B   CR,LF,'> [H]ELP          - Display this message'
        DC.B   CR,LF
        DC.B   CR,LF,'Created for the final project of Microcomputer Design, 2022'
        DC.B   CR,LF,'Author: Jackson Miller'
        DC.B   CR,LF,'Website: www.github.com/jack-mil/mcd-asm'

ER_INV: DC.B    'Invalid command (Type [H]elp for list of commands)',0

* ---------------------- *
    END RESET

