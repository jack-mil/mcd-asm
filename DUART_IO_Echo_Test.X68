*-----------------------------------------------------------
* Title      : I/O Echo Test
* Written by : Jacob Kelsey
* Date       : 2021-04-14
* Description: Sets Duart to normal mode, then loops to always output the input
*-----------------------------------------------------------
* Definitions
STACK       EQU    $01F000  ; Stack Pointer, must point to RAM (grows down)
DUART       EQU    $020000  ; DUART address
* DUART sub-addresses offsets
MRA         EQU    $1       ; Mode Register A    (if Reading)
SRA         EQU    $3       ; Status Register A    (if Reading)
CSR         EQU    $3       ; Clock Select Register A    (if Writing)
CRA         EQU    $5       ; Command Register A    (if Writing)
HRA         EQU    $7       ; Holding Register A (Rx if Read, Tx if Write)
ACR         EQU    $9       ; Auxiliary Control Register (if Writing)
* Other DUART constants
MRA_rst     EQU    $10      ; Reset MRA pointer to MR1A
RxA_rst     EQU    $20      ; Software reset RxA
TxA_rst     EQU    $30      ; Software reset TxA
EN          EQU    $05      ; Tx/Rx Enable
ACR_BAUD    EQU    $80      ; Use 2nd baud rate table (for speed 19.2k)
CSR_BAUD    EQU    $CC      ; Baud rate value = 19,200
MR1_Set     EQU    $13      ; 8-bits, no parity, 1 stop bit
MR2_Norm    EQU    $07      ; Normal mode, CTS/RTS disabled, stop bit length = 1
MR2_Echo    EQU    $47      ; Auto-echo, CTS/RTS disabled, stop bit length = 1

Rx_ready    EQU    $0       ; Receive ready bit position
Tx_ready    EQU    $2       ; Transmit ready bit position

; CPU setup
    ORG    $000000
    DC.L    STACK           ; Set SSP
    DC.L    DUART_init      ; Set initial Program Counter
; End CPU setup

    ORG    $0F00    ; Start program at $000F00
DUART_init:
    LEA         DUART, A0    ; Put DUART address into A0
; Software_Reset
    MOVE.B      #MRA_rst, CRA(A0)    ; Reset MRA pointer
    MOVE.B      #RxA_rst, CRA(A0)    ; Reset RxA
    MOVE.B      #TxA_rst, CRA(A0)    ; Reset TxA
; Initialization
    MOVE.B      #ACR_BAUD,  ACR(A0)    ; Selects baud rate set 2
    MOVE.B      #CSR_BAUD, CSR(A0)    ; Set 19.2k baud Rx/Tx
    MOVE.B      #MR1_Set,   MRA(A0)    ; 8-bits, no parity, 1 stop bit
; MR2_Echo for auto-echo, swap for MR2_Norm to run normally
    MOVE.B      #MR2_Norm, MRA(A0)    ; Set Duart to normal mode
    MOVE.B      #EN,CRA(A0)           ; Enable both Tx and Rx on channel A

LOOP:
    BSR         GET_CHAR
    BRA         LOOP

GET_CHAR:
    BTST        #Rx_ready, SRA(A0)  ; Check if Rx has input
    BEQ         GET_CHAR            ; If not then wait
    MOVE.B      HRA(A0), D1         ; Move char from Rx Holding into D1
    BRA         PUT_CHAR            ; Immediately display on screen, tail return

PUT_CHAR:
    BTST        #Tx_ready, SRA(A0)  ; Check if Tx ready
    BEQ         PUT_CHAR            ; If not then wait
    MOVE.B      D1, HRA(A0)         ; Put char from D1 into Tx Holding
    RTS                             ; Return

    END    DUART_INIT


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
