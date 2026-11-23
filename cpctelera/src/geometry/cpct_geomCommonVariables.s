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
.module         cpct_geometry

.area _DATA

geomStartScreen::  .ds 2  ;; Base address of screen memory

geom7PointBuffer::        ;; Buffer with capacity for seven points
geomX0::           .ds 2  ;; Specific access inside geom7PointBuffer for X0 
geomY0::           .ds 2  ;; Specific access inside geom7PointBuffer for Y0 
geomX1::           .ds 2  ;; Specific access inside geom7PointBuffer for X1
geomY1::           .ds 2  ;; Specific access inside geom7PointBuffer for Y1 
                   .ds 20 ;; Buffer with capacity for five points

geomCurrentY::     .ds 1  ;; Current vertical coordinate
geomCurrentX::     .ds 2  ;; Current horizontal coordinate
geomDeltaX::       .ds 2  ;; Horizontal coordinate difference
geomDeltaY::       .ds 2  ;; Vertical coordinate difference

geomBottomY::      .ds 1  ;; Lower vertical coordinate bound
geomTopY::         .ds 1  ;; Upper vertical coordinate bound

geomInputPtr::     .ds 2  ;; Pointer to input data
geomNbInput::      .ds 1  ;; Number of input elements
geomInputColor::   .ds 1  ;; Input color value
geomCurrentPtr::   .ds 2  ;; A current Adress
geomNextPtr::      .ds 2  ;; A next Adress

geomIndex::        .ds 1  ;; Index of the current element
geomEndX::         .ds 2  ;; Ending horizontal coordinate
geomStartY::       .ds 1  ;; Starting vertical coordinate
geomEndY::         .ds 1  ;; Ending vertical coordinate
geomStep::         .ds 1  ;; Increment or direction used to advance
geomError::        .ds 2  ;; Accumulated intermediate error value
geomThreshold::    .ds 2  ;; Comparison threshold
