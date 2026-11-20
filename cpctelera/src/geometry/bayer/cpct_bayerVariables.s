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
.module cpct_bayer

;;-------------------------------------------------------------------------------
;;  Data storage for common bayer values
;;
;;  Size:
;;      94 bytes (including 4x16 LUT of full octet pixels and its overhead for alignement)
;;-------------------------------------------------------------------------------

.area _DATA
;; Default data is computed with pen1 = 1 and pen2 = 2
bayer_pen1::  .db         0xFF          ;; (1) Current pen1 value (0..3) - default to recompute
bayer_pen2::  .db         0xFF          ;; (1) Current pen2 value (0..3) - default to recompute
bayer_intensity::  .db    0xFF          ;; (1) Current intensity (0..15) - default to recompute
bayer_intensityPtr:: .dw  #bayer_lutM1  ;; (2) Pointer to sub line 0 of current intensity 

bayer_fullColorBytes:: 
    .db         #0x00, #0xF0, #0x0F, #0xFF ;; (4) pen 0..3 full color

;; Constant 4x4 matrix of 0..15 bayer dithering
;; If M[x,y] <= intensity : use pen1 else pen2
bayer_matrix4x4:: 
    .db         0x00, 0x08, 0x02, 0x0A  ;; (4)
    .db         0x0C, 0x04, 0x0E, 0x06  ;; (4)
    .db         0x03, 0x0B, 0x01, 0x09  ;; (4)
    .db         0x0F, 0x07, 0x0D, 0x05  ;; (4)
bayer_matrix4x4_end::


;; LUT of 16 intensity by 4 lines octet values
;; Small buffer to help bayer_LUTM1 to align on 4 for easy line adding in adress with an OR
paddingForAlignment: .ds 3              ;; (3) Padding values to align on 4
_bayer_lutM1::
bayer_lutM1::
    .ds         64                      ;; (64) 16 values of 4 lines + 3 to find an alignement adress
bayer_lutM1_end::

;; Internal data fort draw API
bayer_startScreen:: .dw   0             ;; (2) Starting screen adress (usualy 0xC000)
