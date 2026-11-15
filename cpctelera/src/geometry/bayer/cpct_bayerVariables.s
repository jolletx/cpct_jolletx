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
;;      91 bytes (including 4x16 LUT of full octet pixels)
;;-------------------------------------------------------------------------------

.area _DATA
;; Default data is computed with pen1 = 1 and pen2 = 2
bayer_pen1::  .db         1             ;; (1) Current pen1 value (0..3)
bayer_pen2::  .db         2             ;; (1) Current pen2 value (0..3)
bayer_intensity::  .db    0             ;; (1) Current intensity (0..15)
bayer_intensityPtr:: .dw  #bayer_lutM1  ;; (2) Pointer to sub line 0 of current intensity 

bayer_fullColorBytes:: 
    .db         #0x00                   ;; (1) pen 0 full color
    .db         #0xF0                   ;; (1) pen 1 full color
    .db         #0x0F                   ;; (1) pen 2 full color
    .db         #0xFF                   ;; (1) pen 3 full color

;; Constant 4x4 matrix of 0..15 bayer dithering
;; If M[x,y] <= intensity : use pen1 else pen2
bayer_matrix4x4:: 
    .db         0x00, 0x08, 0x02, 0x0A  ;; (4)
    .db         0x0C, 0x04, 0x0E, 0x06  ;; (4)
    .db         0x03, 0x0B, 0x01, 0x09  ;; (4)
    .db         0x0F, 0x07, 0x0D, 0x05  ;; (4)
bayer_matrix4x4_end::

;; Computed M1 octets based on pen1=1, pen2=2
bayer_lutM1::
    .db         0xF0, 0xF0, 0xF0, 0xF0  ;; (4) Intensity 0, line 0..3
    .db         0x78, 0xF0, 0xF0, 0xF0  ;; (4) Intensity 1, line 0..3
    .db         0x78, 0xF0, 0xD2, 0xF0  ;; (4)
    .db         0x5A, 0xF0, 0xD2, 0xF0  ;; (4)
    .db         0x5A, 0xF0, 0x5A, 0xF0  ;; (4)
    .db         0x5A, 0xB4, 0x5A, 0xF0  ;; (4)
    .db         0x5A, 0xB4, 0x5A, 0xE1  ;; (4)
    .db         0x5A, 0xA5, 0x5A, 0xE1  ;; (4)
    .db         0x5A, 0xA5, 0x5A, 0xA5  ;; (4)
    .db         0x1E, 0xA5, 0x5A, 0xA5  ;; (4)
    .db         0x1E, 0xA5, 0x4B, 0xA5  ;; (4)
    .db         0x0F, 0xA5, 0x4B, 0xA5  ;; (4)
    .db         0x0F, 0xA5, 0x0F, 0xA5  ;; (4)
    .db         0x0F, 0x2D, 0x0F, 0xA5  ;; (4)
    .db         0x0F, 0x2D, 0x0F, 0x87  ;; (4)
    .db         0x0F, 0x0F, 0x0F, 0x87  ;; (4) Intensity 15, line 0..3
bayer_lutM1_end::

;; Internal data fort draw API
bayer_startScreen:: .dw   0             ;; (2) Starting screen adress (usualy 0xC000)
