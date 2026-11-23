.module cpct_geometry

.globl _cpct_drawLineM1_f
.macro CallLineMethod
    call _cpct_drawLineM1_f
.endm

.area _CODE
_cpct_drawPolygonM1_f::
    pop af
    pop bc
    push af

.include "../cpct_drawPolygonCommon.asm"
