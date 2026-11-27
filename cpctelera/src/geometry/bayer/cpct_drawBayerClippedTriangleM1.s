;;-----------------------------LICENSE NOTICE------------------------------------
;;  This file is part of CPCtelera: An Amstrad CPC Game Engine
;;  Copyright (C) 2026 Xavier Jollet (@SagaDS)
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
.module cpct_bayeretry

.globl cpct_clipTriangle_asm
.globl cpct_drawBayerPolygonM1_asm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_drawBayerClippedTriangleM1_asm
;;
;;    Clip and draw a input triangle using bayer dithering.
;;    
;;
;; C Definition:
;;    void <cpct_drawBayerClippedTriangleM1>(const i16 *PtArray);
;;
;; Input Parameters:
;;    (2B HL)     PtArray - Adress of 3 i16 Points defining a triangle to draw
;;
;; Details:
;;    Use an internal buffer of 7 Points to generate a clipped polygon from triangle input.
;;    Then draws the generated polygon if it is valid.
;;    Uses cpct_clipTriangle_asm and cpct_drawBayerPolygonM1_asm
;; 
;; Destroyed Register values:
;;    AF, BC, DE, HL
;;
;; Required memory:
;;
;;
;; Time Measures: (does not include 35 us call to cpct_getScreenPtr_asm)
;; (start code)
;;    Case / Coordinates                       | Pixels | microSecs (us) | CPU Cycles
;;   ---------------------------------------------------------------------------------
;;    Box x0=0 x1=319 y0=0 y1=199              | 101    | ~94375         | ~
;;   ---------------------------------------------------------------------------------
;; (end code)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


.area _CODE
_cpct_drawBayerClippedTriangleM1::
cpct_drawBayerClippedTriangleM1_asm::
    ld      de,#bayer7PointBuffer               ;; [3] DE = 7 x 4 Bytes points buffer
    call    cpct_clipTriangle_asm               ;; [5] Call the clip triangle API with HL pointing to the triangle
    cp      #3                                  ;; [2] Check that output is a valid polygon
    ret     c                                   ;; [2/4] Return if not

    ld      e,a                                 ;; [1] E = Nbpoints of polygon
    ld      hl,#bayer7PointBuffer               ;; [3] HL = Generated polygon definition
    call    cpct_drawBayerPolygonM1_asm         ;; [5] draw the Bayer polygon
    ret                                         ;; [3] Return
bayer7PointBuffer:: .ds 28                      ;; (28) Buffer with capacity for seven points
