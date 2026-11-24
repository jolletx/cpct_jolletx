;;-----------------------------LICENSE NOTICE------------------------------------
;;  This file is part of CPCtelera: An Amstrad CPC Game Engine 
;;  Copyright (C) 2026 Xavier Jollet (@SagaDS)
;;  Copyright (C) 2015 ronaldo / Fremos / Cheesetea / ByteRealms (@FranGallegoBR)
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

;; Define common variables used inside scanFill methods shared between M0 and M1
.module         cpct_geometry

.include "cpct_geomConstants.h.s"

.area _DATA

;; Stack - M0 uses one byte less (X coordinate (0..159 ) is used instead of X octet + Subpixel
;; So if only M0 is necessary, it is recommended remove subpixel .db 0
;; M1 will continue to build/link but Out of Bound writing might occur if API is used
sf_stack::                       ;; Stack of points to fill horizontaly
   .rept SF_STACK_SIZE           ;; Allocate a fixed size stack of points 
      .db 0                      ;; (30) X Octet from left (0..79)
      .db 0                      ;; (30) Sub pixel offset  (0..3) M1
      .db 0                      ;; (30) Y coordinates from top (0..199)
   .endm

;; So if only M0 is necessary, removing .ds 2 from M1 lines should be enough to build/link

sf_newColorM1::   .ds 2          ;; (4) new color values for sub pixel 0..3
sf_newColorM0::   .ds 2          ;; Direct access for M0 new_color
sf_newColorFull:: .db 0          ;; (1) new color full octet for quick checks of octet
sf_oldColorM1::   .ds 2          ;; (4) old color values for sub pixel 0..3
sf_oldColorM0::   .ds 2          ;; Direct access for M0 old_color
sf_oldColorFull:: .db 0          ;; (1) old color full octet for quick fill of octet
