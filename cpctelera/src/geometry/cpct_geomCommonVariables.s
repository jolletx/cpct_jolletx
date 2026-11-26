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

;; Define common variables used inside geometry functions (Video Memory, X0, Y0 ...)
;;
;; Do not move around variables, some mono byte variable have specific 2 bytes access
;; ScreenOffset + SubPixel for example
;;
;;  Size:
;;      52 bytes 
;;-------------------------------------------------------------------------------


.module         cpct_geometry

.area _DATA

geomStartScreen::  .ds 2                            ;; (2) Base address of screen memory
geomX0::           .ds 2                            ;; (2) An horizontal coordinate 
geomY0::           .ds 2                            ;; (2) A vertical coordinate 
geomX1::           .ds 2                            ;; (2) An horizontal coordinate
geomY1::           .ds 2                            ;; (2) A vertical coordinate 
geomCurrentX::     .ds 2                            ;; (2) Current horizontal coordinate
geomCurrentY::     .ds 2                            ;; (2) Current vertical coordinate
geomPreviousX::    .ds 2                            ;; (2) Previous horizontal coordinate
geomPreviousY::    .ds 2                            ;; (2) Previous vertical coordinate
geomDeltaX::       .ds 2                            ;; (2) Horizontal coordinate difference
geomDeltaY::       .ds 2                            ;; (2) Vertical coordinate difference

geomBottomY::      .ds 1                            ;; (1) Lower vertical coordinate bound
geomTopY::         .ds 1                            ;; (1) Upper vertical coordinate bound

geomInputPtr::     .ds 2                            ;; (2) Pointer to input data
geomNbInput::      .ds 1                            ;; (1) Number of input elements
geomInputColor::   .ds 1                            ;; (1) Input color value
geomOutputPtr::    .ds 2                            ;; (2) A current Adress
geomCurrentPtr::   .ds 2                            ;; (2) A current Adress
geomNextPtr::      .ds 2                            ;; (2) A next Adress
geomLeftScrOctet:: .ds 1                            ;; (1) A left Screen octet (0..79)
geomLeftSubPixel:: .ds 1                            ;; (1) A left Sub Pixel (0..3)
geomCurScrOctet::  .ds 1                            ;; (1) A current Screen octet (0..79)
geomCurSubPixel::  .ds 1                            ;; (1) A current Sub Pixel (0..3)
geomRightScrOctet::.ds 1                            ;; (1) A right Screen octet (0..79)
geomRightSubPixel::.ds 1                            ;; (1) A right Sub Pixel (0..3)

geomStartX::       .ds 2                            ;; (2) Starting horizontal coordinate
geomEndX::         .ds 2                            ;; (2) Ending horizontal coordinate
geomStartY::       .ds 1                            ;; (1) Starting vertical coordinate
geomEndY::         .ds 1                            ;; (1) Ending vertical coordinate
geomIndex::        .ds 1                            ;; (1) Index of the current element
geomStep::         .ds 1                            ;; (1) Increment or direction used to advance
geomError::        .ds 2                            ;; (2) Accumulated intermediate error value
geomThreshold::    .ds 2                            ;; (2) Comparison threshold
