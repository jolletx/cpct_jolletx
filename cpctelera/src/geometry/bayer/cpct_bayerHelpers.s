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

.globl      cpct_subPixelHorizontalMask_M1
.globl      cpct_getScreenPtr_asm

.globl      bayer_screenY
.globl      bayer_intensityPtr
.globl      geomStartScreen

.include "macros/cpct_undocumentedOpcodes.h.s"

;;-------------------------------------------------------------------------------
;;  Common methods for Bayer drawing APIs
;;
;;-------------------------------------------------------------------------------


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_drawBayerLineFast_asm
;;
;;    Draw an horizontal line on screen using bayer dithering.
;;    
;;
;; Inputs:
;;    HL = screen octet of left point
;;    C = bayer subline (0..3)
;;    IXL = Left subpixel (0..3) (preserved)
;;    IXH = Right subpixel (0..3)
;;    IYL = NbOctet between left point and right point
;;    Preserved : IXL,IXH,IYL
;;    Modified : HL (screen octet of right point)
;;
;; Details:
;;    Draw a line using a Bayer dithering set by <cpct_setBayerMatrixM1>.
;;    cpct_setBayerMatrixM1 must be called before to set requested intensity / pens
;;    Uses self-modifying code: not suitable for ROMs or reentrant use.
;; 
;; Destroyed Register values:
;;    AF, BC, DE, HL
;;
;; Required memory:
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
cpct_bayerDrawHLineM1_asm::
    push    ix
    push    iy
    call    cpct_bayerDrawHLineM1_worker_asm
    pop     iy
    pop     ix
    ret

;; Internal worker for callers that already preserve IX/IY.
cpct_bayerDrawHLineM1_worker_asm::
    push    bc                                  ;; Preserve screen start
    and     #0x03                               ;; [2] A = bayer subLine  - Resets Carry flag
    ld      c,a                                 ;; C = Bayer subline
    push    hl                                  ;; [4] Save x0
    sbc     hl,de                               ;; [4] HL = x0 - X1
    pop     hl                                  ;; [3] Retrieve x0
    jr      c,#bh_noXExx                        ;; [2/3] if x1 > x0 no exchange
    ex      de,hl                               ;; [1] Exchange x0 and x1
bh_noXExx:
    ; Right octet / subpixel
    ld      a,e                                 ;; [1] a = LSB X1
    and     #0x03                               ;; [2] a = subpixel x1
    ld__ixh_a                                   ;; [4] IXH = Left subpixel
    sra     d                                   ;; [2] divide X1 by 4 - first msb
    rr      e                                   ;; [2] then lsb according to carry
    srl     e                                   ;; [2] e = X right offset on screen

    ; Left octet/subpixel
    ld      a,l                                 ;; [1] a = LSB X0
    and     #0x03                               ;; [2] a = subpixel x0
    ld__ixl_a                                   ;; [4] IXL = Left subpixel
    sra     h                                   ;; [2] divide X0 by 4 - first msb
    rr      l                                   ;; [2] then lsb according to carry
    srl     l                                   ;; [2] l = X offset on screen

    ; NbOctets to draw
    ld      a,e                                 ;; [1] a = e = X Right offset
    sub     l                                   ;; [1] a = a - X Left offset = XRO - XLO = nbOctets
    ld__iyl_a                                   ;; IYL = NbOCtets
    ; Left Screen adress
    pop     de                                  ;; Retrieve screen Y Adress
    add     hl,de                               ;; hl = XLO + screen adress 
    call    cpct_drawBayerLineFast_asm
    ret


;; Prepare the repeated-octet target for a fixed box span.
;;    IXL = Left subpixel
;;    IYL = NbOctet
;; Clobbers AF, BC; preserves HL, DE, IX, and IY.
cpct_bayerPrepareBoxLine_asm::
    push    hl
    ld__a_iyl
    or      a
    jr      z,bh_boxNoRepeat
    ld__a_ixl
    or      a
    ld__a_iyl
    jr      z,bh_boxRepeatCountReady
    ld__a_iyl
    dec     a
    jr      bh_boxRepeatCountReady
bh_boxNoRepeat:
    xor     a
bh_boxRepeatCountReady:
    add     a,a
    ld      b,#0
    ld      c,a
    ld      hl,#bh_lastOctet
    or      a                                   ;; Clear carry before subtracting the repeat length
    sbc     hl,bc
    ld      (bh_jmpBlock),hl                    ;; (SMC) Cache the fixed box repeat target
    pop     hl
    ret

;; Inputs:
;;    HL = screen octet of left point
;;    C = bayer subline
;;    IXL = Left subpixel (preserved)
;;    IXH = Right subpixel
;;    IYL = NbOctet (preserved)
;;    IYH = Current left subpixel during drawing
;; Clobbers AF, BC, DE, HL, IYH.
cpct_drawBayerLineFast_asm::
    ld__a_ixl
    ld__iyh_a                                   ;; Keep IXL constant; track the active left subpixel in IYH

    ; Retrieve bayer octet
    ex      de,hl                               ;; [1] Preserve hl=screenAdress in de
    ld      hl,(bayer_intensityPtr)             ;; [5] Get current intensity adress 
    ld      a,c                                 ;; [2] A = Bayer subline 
    or      l                                   ;; [1] Add subline to pointer
    ld      l,a                                 ;; [1] HL = Adress of subline for this intensity
    ld      a,(hl)                              ;; [2] A = Intensity Octect of subLine
    ex      de,hl                               ;; [1] Retrieve hl = screenAdress - e = nbOctet
    ld      d,a                                 ;; [1] D = Intensity octet of subline

    ;; check if line is on same octet
    ld__a_iyl                                   ;; [1] E = nbOctet
    or      a                                   ;; [1] nbOctet == 0 ?
    jp      z,#bh_lastOctet                     ;; [3] yes : we are on last octet
    ;; Check if left subpixel is 0, so we can use full repetition size
    ld__a_iyh                                   ;; [4] A = left subpixel
    or      a                                   ;; [1] == 0 ?
    jr      z,#bh_setRepeat                     ;; [2/3] yes, can use full octet
    ;; Deal wih first octet from subpixel a to subpixel 3
    ld      c,#3                                ;; [2] c= right Subpixel 3 (a = left subpixel)
    call    b_setScreenOctetFromSubpixels       ;; [5] set screen octet from subpixel a to 3
    xor     a                                   ;; a = 0
    ld__iyh_a                                   ;; Set left subpixel to 0 for last octet
    ld__a_iyl
    dec     a                                   ;; Exclude the first octet without changing IYL
    jr      bh_setRepeatCount
bh_setRepeat::
    ld__a_iyl
bh_setRepeatCount:
    push    hl                                  ;; [4] preserve screen adress
    add     a,a                                 ;; [1] A = repeat count * 2 bytes
    ld      b,#0                                ;; [2] b = 0
    ld      c,a                                 ;; [1] BC = nbOctet * 2
    ld      hl,#bh_lastOctet                    ;; [3] End of the repeated-octet block
    or      a                                   ;; Clear carry before subtracting the repeat length
    sbc     hl,bc                               ;; [4] Decrease pointer to nb octet to set
    ld      (bh_jmpBlock),hl                    ;; [5] (SMC) modify jump access
    pop     hl                                  ;; [3] retrieve screen adress
    jr      bh_jumpRepeat

;; Box-only draw path; cpct_bayerPrepareBoxLine_asm must be called first.
cpct_drawBayerLineFastBox_asm::
    ld__a_ixl
    ld__iyh_a                                   ;; Reinitialize the left subpixel for this row

    ; Retrieve bayer octet
    ex      de,hl
    ld      hl,(bayer_intensityPtr)
    ld      a,c
    or      l
    ld      l,a
    ld      a,(hl)
    ex      de,hl
    ld      d,a

    ld__a_iyl
    or      a
    jp      z,#bh_lastOctet
    ld__a_iyh
    or      a
    jr      z,bh_boxSetRepeat
    ld      c,#3
    call    b_setScreenOctetFromSubpixels
    xor     a
    ld__iyh_a
bh_boxSetRepeat:
    jr      bh_jumpRepeat

bh_jumpRepeat:
bh_jmpBlock=. + 1
    jp      bh_lastOctet                        ;; [3] (SMC) Jumps to correct amount of octet to draw
    .rept   79
    ld      (hl),d                              ;; [2] Set screen octet to current intensity full octet
    inc     hl                                  ;; [2] Increase screen adress
    .endm
bh_lastOctet::
    ld__c_ixh                                   ;; C = rightsubpixel
    ld__a_iyh                                   ;; A = current left subpixel (either input or 0)

;; Set an octet subpixels from a to c with color in d
b_setScreenOctetFromSubpixels:                  
    push  hl                                    ;; [4] Preserve hl = screen adress
    ld    b,#0                                  ;; [2] reset b
    add   a,a                                   ;; [1] a = lsp*2
    add   a,a                                   ;; [1] a = lsp*4
    add   a,c                                   ;; [1] a = lsp*4 + rsp
    ld    c,a                                   ;; [1] bc = index in table
    ld    hl, #cpct_subPixelHorizontalMask_M1   ;; [3] mask table
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

;; Clips X value to 0 if < 0 and to 319 if >319
;; A BC DE modified - Output HL = X vlaue to use
cpct_clipX::                              ;; Clamp signed HL to the horizontal screen range.
    ld de,#0                        ;; Set the lower bound.
    call cpct_compareSigned16       ;; Compare X with zero.
    jr nc,clipX_upper               ;; Check the upper bound when X is nonnegative.
    ld hl,#0                        ;; Replace negative X with the left edge.
    ret                             ;; Return the clipped coordinate.
clipX_upper:                        ;; X is nonnegative; check the right edge.
    ld de,#319                      ;; Set the maximum visible X coordinate.
    call cpct_compareSigned16       ;; Compare X with 319.
    jr c,clipX_done                 ;; Keep X when it is below 319.
    jr z,clipX_done                 ;; Keep X when it equals the inclusive boundary.
    ld hl,#319                      ;; Clamp X above 319 to the right edge.
clipX_done:                         ;; HL contains the clipped coordinate.
    ret                             ;; Return the clipped coordinate.


;; Compare signed 16-bit HL with signed 16-bit DE; carry means HL < DE. z means HL == DE
;; A BC modified - HL DE preserved
cpct_compareSigned16::                  ;; Shared signed-coordinate comparison helper.
    ld a,h                         ;; Load HL's high byte.
    xor #0x80                      ;; Bias its sign bit for unsigned ordering.
    ld b,a                         ;; Save the biased high byte of HL.
    ld a,d                         ;; Load DE's high byte.
    xor #0x80                      ;; Bias its sign bit for unsigned ordering.
    ld c,a                         ;; Save the biased high byte of DE.
    ld a,b                         ;; Compare the biased high bytes first.
    cp c                           ;; Set carry/zero flags for the high-byte order.
    ret nz                         ;; Return when the high bytes differ.
    ld a,l                         ;; High bytes match; load HL's low byte.
    cp e                           ;; Compare low bytes as unsigned values.
    ret                            ;; Return carry/zero flags for the full comparison.

; HL = TopY
; All registers modified
cpct_compScreenLine::
    ld      de,(geomStartScreen)       ;; Get stored start screen
    ; check if TopY is < 0 
    ld      a,h                         ;; a = MSB of TopY
    rlca                                ;; put msb to Carry
    jr      c,b_storeYScreen            ;; if TopY < 0, use Y=0 so start screen
    ld      b,l                         ;; b = Y = lsb of TopY ( < 199 is already checked)
    ld      c,#0                        ;; c = X = 0
    call    cpct_getScreenPtr_asm       ;; compute HL = Y screen adress of 0/TopY 
    ex      de,hl                       ;; DE = screen adress 
b_storeYScreen:
    ld      (bayer_screenY),de
    ret


; Input A = Current Y value
; A HL BC modified
cpct_incScreenLine::
    ld      hl,(bayer_screenY)                      ;; HL = screen Y Adress
    inc     a                                   ;; [1] a = y0 + 1
    and     #7                                  ;; [2] check if Y+1 is on a new char line
    jr      z,bt_adjustHL                       ;; [2/3] if yes, adjust HL 
    ld      a,h                                 ;; [1] a = MSB screen adress
    add     a,#8                                ;; [2] a = a + 8 - Move to next line
    ld      h,a                                 ;; [1] HL = HL + 0x800
    jr      bt_setNewAdress                     ;; [3] Jump to storae
bt_adjustHL:
    ld      bc,#0xc850                          ;; [3] Set bc = 0x800 - 0x4000 + 0x50  to move from char line 7 to char line 0 of next char line
    add     hl,bc                               ;; [3] Adjust hl to next line
bt_setNewAdress:
    ld      (bayer_screenY),hl                      ;; Store HL = screen Y+1 Adress
    ret                                         ;; [3] Return
