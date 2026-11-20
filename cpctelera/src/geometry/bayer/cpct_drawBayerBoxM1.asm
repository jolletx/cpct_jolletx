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

.globl      bayer_startScreen
.globl      bayer_intensityPtr
.globl      cpct_getScreenPtr_asm
.globl      cpct_subPixelHorizontalMask_M1

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
;;    351 bytes (348 bytes routine + 3 bytes C binding wrapper)
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
    ld      (bayer_rightSP),a                   ;; [4] (SMC) Store right subpixel
    sra     d                                   ;; [2] divide X1 by 4 - first msb
    rr      e                                   ;; [2] then lsb according to carry
    srl     e                                   ;; [2] e = X right offset on screen
    ;; Compute HL octet and subpixel
    ld      a,l                                 ;; [1] a = LSB X0
    and     #0x03                               ;; [2] a = subpixel x0
    ld      (bayer_leftSP),a                    ;; [4] (SMC) Store left subpixel
    ld      (bayer_leftSPForLast),a             ;; [4] (SMC) Store left subpixel for last subpixel if nbOctet = 0
    sra     h                                   ;; [2] divide X0 by 4 - first msb
    rr      l                                   ;; [2] then lsb according to carry
    srl     l                                   ;; [2] l = X offset on screen

    ;; Compute and prepare internals
    ld      a,e                                 ;; [1] a = X Right offset
    sub     l                                   ;; [1] a = XRO - XLO = nbOctets
    ld      (bayer_nbOctets),a                  ;; [4] (SMC) Stores the octet difference between X1 and X0
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
    ;; Get current line intensity octet
    ex      de,hl                               ;; [1] Preserve hl=screenAdress in de
    ld      hl,(bayer_intensityPtr)             ;; [5] Get current intensity adress 
bayer_y0=. + 1
    ld      a,#0                                ;; [2] (SMC) A = Y0 
    and     #0x03                               ;; [2] A = subLine 
    or      l                                   ;; [1] Add subline to pointer
    ld      l,a                                 ;; [1] HL = Adress of subline for this intensity
    ld      a,(hl)                              ;; [2] A = Intensity Octect of subLine
    ex      de,hl                               ;; [1] Retrieve hl = screenAdress
    ;; Prepare values for horizontal line algo
    ld      d,a                                 ;; [1] D = Intensity octet of subline
bayer_nbOctets=. + 1
    ld      e,#1                                ;; [2] (SMC) E = nbOctet

    ;; Draw line from left to right
    push    hl                                  ;; [4] Preserve start of line adress
    ;; check if line is on same octet
    ld      a,e                                 ;; [1] A = nbOctet
    or      a                                   ;; [1] nbOctet == 0 ?
    jp      z,#bb_lastOctet                     ;; [3] yes : we are on last octet
    ;; Check if left subpixel is 0, so we can use full repetition size
bayer_leftSP=. + 1    
    ld      a,#0                                ;; [4] (SMC) A = left subpixel
    or      a                                   ;; [1] == 0 ?
    jr      z,#bb_setRepeat                     ;; [2/3] yes, can use full octet
    ;; Deal wih first octet from subpixel a to subpixel 3
    ld      c,#3                                ;; [2] c= Subpixel 3 (a = left subpixel)
    call    b_setScreenOctetFromSubpixels       ;; [5] set screen octet from subpixel a to 3
    xor     a                                   ;; [1] A = 0
    ld      (bayer_leftSPForLast),a             ;; [4] (SMC) Set last octet left subpixel to 0
    dec     e                                   ;; [1] Decrease nbOctet (can be 0 now)

bb_setRepeat::
    ld      a,e                                 ;; [1] A = nbOctet
    add     a,a                                 ;; [1] A = nbOctet * 2 (ld (hl),d inc hl) - Carry cannot be set 
    ld      b,#0                                ;; [2] b = 0
    ld      c,a                                 ;; [1] BC = nbOctet * 2
    push    hl                                  ;; [4] preserve screen adress
    ld      hl,#bb_lastOctet                    ;; [3] Points to next instruction after jumpBlock
    sbc     hl,bc                               ;; [4] Decrease pointer to nb octet to set
    ld      (b_jmpBlock),hl                     ;; [5] (SMC) modify jump access
    pop     hl                                  ;; [3] retrieve screen adress

b_jmpBlock=. + 1
    jp      bb_lastOctet                        ;; [3] (SMC) Jumps to correct amount of octet to draw
    .rept   79
    ld      (hl),d                              ;; [2] Set screen octet to current intensity full octet
    inc     hl                                  ;; [2] Increase screen adress
    .endm
bb_lastOctet::
bayer_rightSP=. + 1                             
    ld    c,#3                                  ;; [2] (SMC) C = right subpixel 
bayer_leftSPForLast=. + 1     
    ld    a,#0                                  ;; [4] (SMC) A = left subpixel for last
    call  b_setScreenOctetFromSubpixels         ;; [5] Set last octet subpixels from a to c with color

    pop     hl                                  ;; [3] Retrieve X0 left screen adress

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
    ret                                         ;; [3] End of drawBayerBoxM1 

;; Set screen octet from A subpixel to C subpixel
b_setScreenOctetFromSubpixels::
    push  hl                                    ;; [4] Preserve hl
    ld    b,#0                                  ;; [2] reset b
    add   a,a                                   ;; [1] a = lsp*2
    add   a,a                                   ;; [1] a = lsp*4
    add   a,c                                   ;; [1] a = lsp*4 + rsp
    ld    hl, #cpct_subPixelHorizontalMask_M1   ;; [3] mask table
    ld    c,a                                   ;; [1] bc = index in table
    add   hl,bc                                 ;; [3] hl = adress of mask to use
    ld    a,(hl)                                ;; [2] a = mask to use for reset pixels with new color
    pop   hl                                    ;; [3] Restore adress
;; Use mask on screen octet
    ld    c,a                                   ;; [1] save mask
    and   (hl)                                  ;; [2] a = current screen pixels with clear pixels from mask
    ld    b,a                                   ;; [1] b = current screen octet (cleared from left subpixel to subpixel 3)
    ld    a,c                                   ;; [1] retrieve mask
    cpl                                         ;; [1] invert mask
    and   d                                     ;; [1] set requested color to inverted pixelsmask
    or    b                                     ;; [1] merge result with current screen octet
    ld    (hl),a                                ;; [2] Set screen octet
    inc   hl                                    ;; [2] Next screen octet
    ret                                         ;; [3] return
