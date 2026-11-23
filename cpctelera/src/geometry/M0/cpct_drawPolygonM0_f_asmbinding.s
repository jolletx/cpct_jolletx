.module cpct_drawPolygonM0_f

.globl _cpct_drawLineM0_f
.macro CallLineMethod
    call _cpct_drawLineM0_f
.endm


.area _CODE

cpct_drawPolygonM0_f_asm::

.include "../cpct_drawPolygonCommon.asm"
