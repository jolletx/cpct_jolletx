.module cpct_drawPolygonM0

.globl _cpct_drawLineM0
.macro CallLineMethod
    call _cpct_drawLineM0
.endm

.area _CODE
_cpct_drawPolygonM0::
    pop af
    pop bc
    push af

.include "../cpct_drawPolygonCommon.asm"
