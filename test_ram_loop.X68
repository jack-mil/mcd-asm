*-----------------------------------------------------------
* Program    : RAM Test Loop
* Date       : 2022
* Description: Testing RAM with a subroutine jump. To jump
*              to a subroutine, the PC and SR are pushed onto
*              the stack which is a location in RAM. If the
*              program continually loops, the RAM is working
*-----------------------------------------------------------
SUPER_STACK     EQU     $020000 ; MUST BE A VALID RAM LOCATION
START   ORG     $000000
        DC.L    SUPER_STACK     ; Store reset vector
        DC.L    MAIN

         ORG     $000600
MAIN     JSR RAM_TEST
         JMP MAIN

RAM_TEST NOP
         NOP
         NOP
         RTS
         END     MAIN


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
