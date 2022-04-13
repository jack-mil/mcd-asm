*-----------------------------------------------------------
* Title      : String Output Test
* Written by : Jacob Kelsey
* Date       : 2021-04-14
* Description: Sets Duart to normal mode, then outputs a string on a loop
*-----------------------------------------------------------
* Definitions
STACK       EQU    $018000    ; Stack Pointer, must point to RAM (grows down)
DUART       EQU    $020000    ; DUART address

* DUART registers
MRA        EQU     $1      Offset for Channel A Mode Register 1

SRA         EQU    $3    ; Status Register A    (if Reading)
CSRA        EQU    $3    ; Clock Select Register A    (if Writing)
CRA         EQU    $5    ; Command Register A    (if Writing)
HRA         EQU    $7    ; Holding Register A (Rx if Read, Tx if Write)
ACR         EQU    $9    ; Auxiliary Control Register (if Writing)
; Other DUART definitions
PAR1        EQU     %00100011   ; 8 bits per character, even parity
                            ; block error mode,
                            ; no Rs-controlled RTSA* deactivation.
PAR2        EQU     %00010111   ; One stop bit, enable TX CTSA* input,
                            ; disable Tx RTSA* output, normal
                            ; operating mode
MRA_rst     EQU    $10    ; Reset MRA pointer to MR1A
RxA_rst     EQU    $20    ; Software reset RxA
TxA_rst     EQU    $30    ; Software reset TxA
CR_Enabl    EQU    $05    ; Tx/Rx Enable
ACR_BAUD    EQU    $80    ; Use 2nd baud rate table (for speed 19.2k)
CSR_BAUD    EQU    $CC    ; Baud rate value = 19,200
MR1_Set     EQU    $13    ; 8-bits, no parity, 1 stop bit
MR2_Norm    EQU    $07    ; Normal mode, CTS/RTS disabled, stop bit length = 1
MR2_Echo    EQU    $47    ; Auto-echo, CTS/RTS disabled, stop bit length = 1

Rx_ready    EQU    $0    ; Recieve ready bit position
Tx_ready    EQU    $2    ; Transmit ready bit position
; End Definitions

; CPU setup
    ORG    $000000
    DC.L    STACK    ; Set SP
    DC.L    INIT     ; Set initial Program Counter
; End CPU setup

    ORG     $0400           ; Start program at $000400
INIT
    LEA DUART,A0    ; Put DUART address into A0
; Software_Reset
    MOVE.B    #MRA_rst, CRA(A0)    ; Reset MRA pointer
    MOVE.B    #RxA_rst, CRA(A0)    ; Reset RxA
    MOVE.B    #TxA_rst, CRA(A0)    ; Reset TxA
; Initialization
    MOVE.B    #ACR_BAUD,  ACR(A0)    ; Selects baud rate set 2
    MOVE.B    #CSR_BAUD, CSRA(A0)    ; Set 19.2k baud Rx/Tx
    MOVE.B    #MR1_Set,   MRA(A0)    ; 8-bits, no parity, 1 stop bit
; MR2_Echo for auto-echo, swap for MR2_Norm to run normally
    MOVE.B    #MR2_Norm, MRA(A0)    ; Set Duart to normal mode
    MOVE.B    #CR_Enabl, CRA(A0)    ; Enable both Tx and Rx on channel A


.return lea    String,A1    ; Load string pointer into A1
.next   move.b  (A1)+,D1
        beq     .return
.wait   btst    #Tx_ready, SRA(A0)
        beq     .wait
        move.b  D1,HRA(A0)
        bra     .next


; out_str    
;             MOVE.B    (A1)+, D1    ; Load char into D1 and increment A1 to point to the next char in string
;     BEQ    .return    ; If char is null (0), return
;     BSR    out_char
;     BRA    out_str    ; To next char
; .return    RTS
    
; out_char    BTST    #Tx_ready, SRA(A0)    ; Check if Tx ready 
;     BEQ    out_char    ; If not then wait
;     MOVE.B    D1, HRA(A0)    ; Put char from D1 into Tx Holding
;     RTS

CR      EQU    $0D
LF      EQU    $0A
NULL    EQU    $00

string
    DC.B    'Hello World!', CR, LF
    DC.B    '0123 4567 89AB CDEF', CR, LF
    DC.B    'abcdefghijklmnopqrstuvwxyz', CR, LF, CR, LF
    dc.b    $E2,$88,$9E,$2B,$50
    DC.B    NULL


    END    INIT

*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
