*-----------------------------------------------------------
* Program    : Test Loop
* Date       : 2022
* Description: Testing ROM. NOP is "No operation" and will
*              simply increase the PC
*-----------------------------------------------------------
SUPER_STACK     EQU     $020000 ; Stacks starts at top of RAM (decreases)
START   ORG     $000000
        DC.L    SUPER_STACK     ; Store reset vector
        DC.L    MAIN

        ORG     $000600
MAIN    NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        BRA     MAIN

        END     MAIN

