.module cpct_geometry

.globl _cpct_drawLineM1
.macro CallLineMethod
    call _cpct_drawLineM1
.endm

.area _CODE

cpct_drawPolygonM1_asm::

.include "../cpct_drawPolygonCommon.asm"
