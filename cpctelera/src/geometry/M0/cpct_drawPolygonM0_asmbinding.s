.module cpct_drawPolygonM0

.globl _cpct_drawLineM0
.macro CallLineMethod
    call _cpct_drawLineM0
.endm

.area _CODE

cpct_drawPolygonM0_asm::

.include "../cpct_drawPolygonCommon.asm"
