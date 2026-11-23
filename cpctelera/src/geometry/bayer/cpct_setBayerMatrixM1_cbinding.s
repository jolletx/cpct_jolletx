;;-----------------------------LICENSE NOTICE------------------------------------
;;  This file is part of CPCtelera: An Amstrad CPC Game Engine
;;  Copyright (C) 2026 Xavier Jollet (@SagaDS)
;;  Copyright (C) 2026 ronaldo / Fremos / Cheesetea / ByteRealms (@FranGallegoBR)
;;
;;  This program is free software: you can redistribute it and/or modify
;;  it under the terms of the GNU Lesser General Public License as published by
;;  the Free Software Foundation, either version 3 of the License, or
;;  (at your option) any later version.
;;
;;  This program is distributed in the hope that it will be useful,
;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;  GNU Lesser General Public License for more details.
;;
;;  You should have received a copy of the GNU Lesser General Public License
;;  along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;-------------------------------------------------------------------------------
.module cpct_geometry

;;
;; C bindings for <cpct_setBayerMatrixM1>
;;      void cpct_setBayerMatrixM1(u8* vmem, u16 intensity, u8 pen1, u8 pen2 ) __z88dk_callee; 
;;
;;  10 microSecs, 3 bytes
;;
.include "macros/cpct_undocumentedOpcodes.h.s"

_cpct_setBayerMatrixM1::
    ;; HL = vmem , DE = intensity (only E is used)

    pop     af                  ;; [3] Retrieve return adress
    pop     bc                  ;; [3] Retrieve pen1 in C and pen2 in B
    push    af                  ;; [4] Put back the return adress on stack

.include /cpct_setBayerMatrixM1.asm/
