* ------------- *
* ANSI Color &  *
* UTF-8 Demo    *
* jackmil       *
* MCD 2022      *
* ------------- *

* All user programs should originate in USER ram space
* 01 1000 - 01 C000

STACK   EQU     $1D000



START     ORG     $11000

        lea     STACK,A7        ; Set user stack pointer

        lea     STR,A0          ; Load both A0
        lea     (A0),A1         ; and A1 with start of string buffer
    *
        move.b  #2,D6           ; Three lines like this
        move.l  #LHB,D3         ; First line has lower half block
.l2     clr.l   D2
        move.b  #CR,(A0)+       ; Start with
        move.b  #LF,(A0)+       ; a newline
.l1     bsr     color           ; Switch to new color in D2
        move.l  #FB,D0          ; Add 3 unicode
        bsr     shift           ; Full block elements
        bsr     shift
        bsr     shift
        bsr     bold            ; Switch to bold alternate color
        move.l  D3,D0           ; Add 1 other character from D3 (6 bytes)
        bsr     shift           ; half block character
        bsr     norm            ; Switch to normal color
        move.b  #$20,(A0)+      ; add 2 spaces between swatches
        move.b  #$20,(A0)+
    *
        add.b   #1,D2           ; Increment color
        cmp     #8,D2           ; Stop at color 7 (black)
        bne     .l1             ; Print 7 swatches
        move.l  #FB,D3          ; Other 2 times, use Full Block
        dbra    D6,.l2          ; Print 3 lines

    * Now add final line
        bsr     bold
        clr.l   D2
        move.b  #CR,(A0)+       ; Start with
        move.b  #LF,(A0)+       ; a newline
        move.b  #$20,(A0)+
.l3     bsr     color
        move.l  #UHB,D0
        bsr     shift
        bsr     shift
        bsr     shift
        move.b  #$20,(A0)+
        move.b  #$20,(A0)+
        move.b  #$20,(A0)+
        add.b   #1,D2
        cmp     #8,D2
        bne     .l3
    *
        bsr     norm
        move.b  #0,(A0)+        ; Terminate with NUL character

        move.b  #14,D0          ; Print NUL terminated string
        trap    #15             ; pointed to by A1

        trap    #0              ; Return to monitor program

shift:
* Take 6 bytes in D0
* and write it MSB first in the string
* buffer pointer at A0
        swap    D0              ; Swap high and low words
        move.b  D0,(A0)+        ; Print first byte
        swap    D0
        ror.w   #8,D0           ; Swap last two bytes
        move.b  D0,(A0)+
        rol.w   #8,D0           ; Restore LS byte
        move.b  D0,(A0)+
        rts

color:
* Changes foreground color to value in D2.B
* Uses D3 for ascii conversion
        bsr     csi
        move.b  #'3',(A0)+
        move.b  D2,D4
        add.b   #$30,D4
        move.b  D4,(A0)+
        move.b  #'m',(A0)+
        rts

csi:
* Control Sequence Introducer \e[
        move.b  #ESC,(A0)+
        move.b  #'[',(A0)+
        rts

norm:
* Set buffer text to regular
        bsr     csi
        move.b  #'m',(A0)+
        rts

bold:
* Set buffer text to bold
        bsr     csi
        move.b  #'1',(A0)+
        move.b  #'m',(A0)+
        rts


* Data Area *
CR:     EQU     $0D     ; Carriage Return
LF:     EQU     $0A     ; Line Feed
ESC:    EQU     $1B     ;

FB:     EQU     $E29688
LHB:    EQU     $E29684
UHB:    EQU     $E29680

        ORG     (*+3)&-4        ; Force longword alignment
STR:    EQU     *               ; STRING Buffer space begins after program data (In RAM)

    END START


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
