* ----------------------- *
* Counter Example Program *
* jackmil                 *
* MCD 2022                *
* ----------------------- *

* All user programs should originate in USER ram space
* 01 1000 - 01 C000
CR:     EQU     $0D     ; Carriage Return
LF:     EQU     $0A     ; Line Feed

sta:  EQU     $13000

beg     ORG     $12000
        lea     sta,A3          ; Start and
        lea     $90(A3),A4      ; and end address
        clr.l   D1

.loop   move.l  #$07,D1         ; Setup D1 as counter (8 iterations)
.l1     move.w  #$FF00,(A3)+    ; Place word in memory
        dbra    D1,.l1

        move.l  #$07,D1         ; Reset counter
.l2     move.w  #$00FF,(A3)+    ; Alternate word for patern
        dbra    D1,.l2

        cmp.l     A4,A3         ; Check if written 9 lines
        blt     .loop
        rts

    END beg

; FF 00 FF 11 FF 22 FF 33 FF 44 FF 55 FF 66 FF 77
; 00 FF 11 FF 22 FF 33 FF 44 FF 55 FF 66 FF 77 FF
; FF 11 FF 22 FF 33 FF 44 FF 55 FF 66 FF 77 FF 88
; 11 FF 22 FF 33 FF 44 FF 55 FF 66 FF 77 FF 88 FF
; FF 22 FF 33 FF 44 FF 55 FF 66 FF 77 FF 88 FF 99
; 22 FF 33 FF 44 FF 55 FF 66 FF 77 FF 88 FF 99 FF
; FF 33 FF 44 FF 55 FF 66 FF 77 FF 88 FF 99 FF AA
; 33 FF 44 FF 55 FF 66 FF 77 FF 88 FF 99 FF AA FF
; FF 44 FF 55 FF 66 FF 77 FF 88 FF 99 FF AA FF BB


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
