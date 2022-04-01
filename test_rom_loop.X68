*-----------------------------------------------------------
* Program    : Test Loop
* Date       : 2022
* Description: Testing ROM. NOP is "No operation" and will
*              simply increase the PC
*-----------------------------------------------------------
SUPER_STACK     EQU     $000FFE  ; note this stack pointer points to a location
                                ; in ROM and therefore will not function as a
                                ; stack, it is simply used as a place holder.
START   ORG     $000000
        DC.L    SUPER_STACK     ; Store reset vector
        DC.L    MAIN

        ORG     $000100
MAIN    NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        JMP     MAIN

        END     MAIN


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
