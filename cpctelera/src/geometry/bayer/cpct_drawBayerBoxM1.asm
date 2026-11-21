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

.include "macros/cpct_undocumentedOpcodes.h.s"

.globl      bayer_startScreen
.globl      cpct_getScreenPtr_asm
.globl      cpct_drawBayerLineFast_asm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_drawBayerBox
;;
;;    Draw a rectangular box on screen using bayer dithering.
;;    
;;
;; C Definition:
;;    void <cpct_drawBayerBox>(u16 xmin, u16 xmax, u8 ymin, u8 ymax);
;;
;; Input Parameters:
;;    (2B HL)     xmin - Left bound    (inclusive)
;;    (2B DE)     xmax - Right bound   (inclusive)
;;    (2B BC)     ymin - Top bound = C (inclusive) ymax - Bottom bound = B  (inclusive)
;;
;; Details:
;;    Draw a box using a Bayer dithering set by <cpct_setBayerMatrixM1>.
;;    cpct_setBayerMatrixM1 must be called before to set requested vmem start / intensity / pens
;;    Uses self modifying code: not suitable for ROMs
;; 
;; Destroyed Register values:
;;    AF, BC, DE, HL
;;
;; Required memory:
;;    Uses cpct_drawBayerLineFast_asm from cpct_bayerHelpers.s
;;    (+36 bytes for cpct_subPixelHorizontalMask_M1)
;;    (+94 bytes for bayer internal data)
;;
;; Time Measures: (does not include 35 us call to cpct_getScreenPtr_asm)
;; (start code)
;;    Case / Coordinates                       | Pixels | microSecs (us) | CPU Cycles
;;   ---------------------------------------------------------------------------------
;;    Box x0=0 x1=100 y0=0 y1=4                | 505    | ~1321          | ~
;;    Box x0=0 x1=319 y0=0 y1=199              | 101    | ~94375         | ~
;;   ---------------------------------------------------------------------------------
;; (end code)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;; HL = X0, DE = X1 C = y0 B = Y1 
    ;; Check which is min / max
    push    ix                                  ;; Preserve IX/IY for Fast line inputs
    push    iy
    push    hl                                  ;; [4] Save x0
    sbc     hl,de                               ;; [4] HL = x0 - X1
    pop     hl                                  ;; [3] Retrieve x0
    jr      c,#bb_noXExx                        ;; [2/3] if x1 > x0 no exchange
    ex      de,hl                               ;; [1] Exchange x0 and x1
bb_noXExx:
    ld      a,b                                 ;; [1] A = y1
    sub     a,c                                 ;; [1] A = y1 - y0
    jr      nc,#bb_noYExx                       ;; [2/3] If y1 > y0 no exchange 
    ld      a,b                                 ;; [1] a = y1
    ld      b,c                                 ;; [1] b = y0
    ld      c,a                                 ;; [1] c = y1
bb_noYExx:   

    ;; So now HL < DE C < B
    ld      a,c                                 ;; [1] a = y0
    ld      (bayer_y0),a                        ;; [4] (SMC) Store current Y coordinate
    ;; Compute right octet and subpixel
    ld      a,e                                 ;; [1] a = LSB X1
    and     #0x03                               ;; [2] a = subpixel x1
    ld__ixh_a                                   ;; IXH = right subpixel
    sra     d                                   ;; [2] divide X1 by 4 - first msb
    rr      e                                   ;; [2] then lsb according to carry
    srl     e                                   ;; [2] e = X right offset on screen
    ;; Compute HL octet and subpixel
    ld      a,l                                 ;; [1] a = LSB X0
    and     #0x03                               ;; [2] a = subpixel x0
    ld__ixl_a                                   ;; IXL = left subpixel
    sra     h                                   ;; [2] divide X0 by 4 - first msb
    rr      l                                   ;; [2] then lsb according to carry
    srl     l                                   ;; [2] l = X offset on screen

    ;; Compute and prepare internals
    ld      a,e                                 ;; [1] a = X Right offset
    sub     l                                   ;; [1] a = XRO - XLO = nbOctets
    ld__iyl_a                                   ;; IYL = octet difference
    ld      a,b                                 ;; [1] a = Y1
    sub     c                                   ;; [1] a = Y1-Y0 = nbLines
    ld      (bayer_nbLines),a                   ;; [4] Stores number of line to draw

    ;; Computing screen adress of Left octet and subpixels on line C
    ld      b,c                                 ;; [1] B = y0
    ld      c,l                                 ;; [1] C = XLeft offset
    ld      de,(bayer_startScreen)              ;; [6] de = screen adress start
    call    cpct_getScreenPtr_asm               ;; [5] Output HL = screen start of X0,Y0

    ;; Algo

bb_lineLoop::
    ;; Draw line from left to right
bayer_y0=. + 1
    ld      a,#0                                ;; (SMC) A = current Y
    and     #0x03                               ;; A = Bayer subline
    ld      c,a                                 ;; C = Bayer subline

    push    hl                                  ;; Preserve start of line address
    call    cpct_drawBayerLineFast_asm
    pop     hl                                  ;; Retrieve X0 left screen address

    ;; deal with line loop  
bayer_nbLines=. + 1
    ld      a,#0                                ;; [2] (SMC) Check nbLines
    or      a                                   ;; [1] == 0 ?
    jr      z,bb_endBayerBox                    ;; [2/3] Yes : we have finished drawing
    dec     a                                   ;; [1] decrease nbLines
    ld      (bayer_nbLines),a                   ;; [4] (SMC) Stores new value
    ;; Change screen adress to new line and increase y0 for next subline
    ld      a,(bayer_y0)                        ;; [4] a = y0
    inc     a                                   ;; [1] increase y0
    ld      (bayer_y0),a                        ;; [4] (SMC) stores y0
    and     #7                                  ;; [2] check if Y+1 is on a new char line
    jr      z,bb_adjustHL                       ;; [2/3] if yes, adjust HL 
    ld      a,h                                 ;; [1] a = MSB screen adress
    add     a,#8                                ;; [2] a = a + 8 - Move to next line
    ld      h,a                                 ;; [1] HL = HL + 0x800
    jp      bb_lineLoop                         ;; [3] Loop to next line
bb_adjustHL::
    ld      bc,#0xc850                          ;; [3] Set bc = 0x800 - 0x4000 + 0x50  to move from char line 7 to char line 0 of next char line
    add     hl,bc                               ;; [3] Adjust hl to next line
    jp      bb_lineLoop                         ;; [3] Loop to next line

bb_endBayerBox::
    pop     iy                                  ;; Restore caller's IY
    pop     ix                                  ;; Restore caller's IX
    ret                                         ;; [3] End of drawBayerBoxM1 
