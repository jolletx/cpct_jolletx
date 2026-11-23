.module cpct_drawPolygonM1

.globl _cpct_drawLineM1
.macro CallLineMethod
    call _cpct_drawLineM1
.endm

.area _CODE
_cpct_drawPolygonM1::
    pop af
    pop bc
    push af

.include "../cpct_drawPolygonCommon.asm"
