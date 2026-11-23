.module cpct_geometry

.globl _cpct_drawLineM1_f
.macro CallLineMethod
    call _cpct_drawLineM1_f
.endm

.area _CODE

cpct_drawPolygonM1_f_asm::

.include "../cpct_drawPolygonCommon.asm"
