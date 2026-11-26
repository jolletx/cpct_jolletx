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
;; Common methods for Bayer drawing APIs
;;-------------------------------------------------------------------------------
;;
;; Global size
;;    399 octets (+ 4 bytes common bayer variables + 52 common geometric variables)
;;

;;-------------------------------------------------------------------------------
;; Function: <cpct_bayerPrepareBoxLine_asm>
;;-------------------------------------------------------------------------------
;;
;;    Prepare the repeated-octet target for drawBayerBox.
;;
;;   Input:
;;     IXL = Left subpixel
;;     IYL = NbOctet
;; 
;;   Modifies AF, BC, Preserves HL, DE, IX, and IY
;;    
;; Timings
;;     39 NOPS max
cpct_bayerPrepareBoxLine_asm::
    push    hl                                  ;; [4] preserve HL
    ld__a_iyl                                   ;; [2] A = NbOctet
    or      a                                   ;; [1] Check with 0
    jr      z,bh_boxRepeatCountReady            ;; [2/3] if a == 0 Norepeat
    ld__a_ixl                                   ;; [2] A = left subpixel
    or      a                                   ;; [1] Check with 0
    ld__a_iyl                                   ;; [2] Reset A to NbOctet before jump
    jr      z,bh_boxRepeatCountReady            ;; [2/3] if subpixel == 0 
    dec     a                                   ;; [1] Decrease NbOctet to perform because first octet is partial
bh_boxRepeatCountReady:
    add     a,a                                 ;; [1] A = a x 2 (ld (hl),d / inc hl)
    ld      b,#0                                ;; [2] B = 0
    ld      c,a                                 ;; [1] BC = NbOctet to repeat * 2
    ld      hl,#bh_lastOctet                    ;; [3] Init hl to first adress after the macro repeat
    sbc     hl,bc                               ;; [4] Move backward from bh_lastOctet
    ld      (bh_jmpBlock),hl                    ;; [5] (SMC) Set the fixed box repeat target 
    pop     hl                                  ;; [3] Retrieve input HL
    ret                                         ;; [3] return


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_bayerDrawHLineM1_worker_asm
;;
;;    Draw an horizontal line on screen using bayer dithering.
;;
;; Inputs:
;;    BC = Screen adress of the current row getScreenPtr (0 , Y)
;;    A = Current Y row (0..199) to compute Bayer subLine
;;    HL = X0 (0..319)
;;    DE = X1 (0..319)
;;
;; Modifies all registers even IX / IY
;;
;; Details:
;;    Draw a line using a Bayer dithering set by <cpct_setBayerMatrixM1>.
;;    cpct_setBayerMatrixM1 must be called before to set requested intensity / pens
;;    Uses self-modifying code: not suitable for ROMs or reentrant use.
;; 
;; Destroyed Register values:
;;    AF, BC, DE, HL (output = screen adress of last point + 1) , IX, IY
;;
;; Required memory:
;;    (+36 bytes for cpct_subPixelHorizontalMask_M1)
;;    (+94 bytes for bayer internal data)
;;
;; Time Measures:
;; (start code)
;;    Case / Coordinates                       | Pixels | microSecs (us) | CPU Cycles
;;   ---------------------------------------------------------------------------------
;;    Line x0=3 x1=102 y0=3                    | 100    | ~xxxx          | ~xxxx
;;    Line x0=0 x1=319 y0=4                    | 320    | ~xxxx          | ~xxxx
;;   ---------------------------------------------------------------------------------
;; (end code)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

cpct_bayerDrawHLineM1_asm::
    push    bc                                  ;; [4] Preserve screen start
    and     #0x03                               ;; [2] A = bayer subLine  - Resets Carry flag
    ld      c,a                                 ;; [1] C = Bayer subline
    push    hl                                  ;; [4] Save x0
    sbc     hl,de                               ;; [4] HL = x0 - X1
    pop     hl                                  ;; [3] Retrieve x0
    jr      c,#bh_noXExx                        ;; [2/3] if x1 > x0 no exchange
    ex      de,hl                               ;; [1] Exchange x0 and x1
bh_noXExx:
    ; Right octet / subpixel
    ld      a,e                                 ;; [1] a = LSB X1
    and     #0x03                               ;; [2] a = subpixel x1
    ld__ixh_a                                   ;; [2] IXH = Right subpixel
    sra     d                                   ;; [2] divide X1 by 4 - first msb
    rr      e                                   ;; [2] then lsb according to carry
    srl     e                                   ;; [2] e = X right offset on screen

    ; Left octet/subpixel
    ld      a,l                                 ;; [1] a = LSB X0
    and     #0x03                               ;; [2] a = subpixel x0
    ld__ixl_a                                   ;; [2] IXL = Left subpixel
    ld__iyh_a                                   ;; [2] Keep IXL constant; track the active left subpixel in IYH
    sra     h                                   ;; [2] divide X0 by 4 - first msb
    rr      l                                   ;; [2] then lsb according to carry
    srl     l                                   ;; [2] l = X offset on screen

    ; NbOctets to draw
    ld      a,e                                 ;; [1] a = e = X Right offset
    sub     l                                   ;; [1] a = a - X Left offset = XRO - XLO = nbOctets
    ld__iyl_a                                   ;; [2] IYL = NbOCtets
    ; Left Screen adress
    pop     de                                  ;; [3] Retrieve screen Y Adress
    add     hl,de                               ;; [3] hl = XLO + screen adress 

    ; Retrieve bayer octet
    ex      de,hl                               ;; [1] Preserve hl=screenAdress in de
    ld      hl,(bayer_intensityPtr)             ;; [5] Get current intensity adress 
    ld      a,c                                 ;; [1] A = Bayer subline (0..3)
    or      l                                   ;; [1] Add subline to pointer (LUT is aligned to 4 Bytes)
    ld      l,a                                 ;; [1] HL = Adress of subline for this intensity
    ld      a,(hl)                              ;; [2] A = Intensity Octect of subLine
    ex      de,hl                               ;; [1] Retrieve hl = screenAdress - e = nbOctet
    ld      d,a                                 ;; [1] D = Intensity octet of subline

    ;; check if line is on same octet
    ld__a_iyl                                   ;; [2] E = nbOctet
    or      a                                   ;; [1] nbOctet == 0 ?
    jp      z,#bh_lastOctet                     ;; [3] yes : we are on last octet
    ;; Check if left subpixel is 0, so we can use full repetition size
    ld__a_iyh                                   ;; [2] A = left subpixel copy
    or      a                                   ;; [1] == 0 ?
    jr      z,#bh_setRepeat                     ;; [2/3] yes, can use full octet
    ;; Deal wih first octet from subpixel a to subpixel 3
    ld      c,#3                                ;; [2] c= right Subpixel 3 (a = left subpixel)
    call    b_setScreenOctetFromSubpixels       ;; [5] set screen octet from subpixel a to 3
    xor     a                                   ;; [1] a = 0
    ld__iyh_a                                   ;; [2] Set left subpixel to 0 for last octet
    ld__a_iyl                                   ;; [2] A = NbOctet
    dec     a                                   ;; [1] Exclude the first octet without changing IYL
    jr      bh_setRepeatCount                   ;; [3] Jump over next line
bh_setRepeat:
    ld__a_iyl                                   ;; [2] A = NbOctet without modifications
bh_setRepeatCount:
    push    hl                                  ;; [4] preserve screen adress
    add     a,a                                 ;; [1] A = repeat count * 2 bytes
    ld      b,#0                                ;; [2] b = 0
    ld      c,a                                 ;; [1] BC = nbOctet * 2
    ld      hl,#bh_lastOctet                    ;; [3] End of the repeated-octet block
    or      a                                   ;; [1] Clear carry before subtracting the repeat length
    sbc     hl,bc                               ;; [4] Decrease pointer to nb octet to set
    ld      (bh_jmpBlock),hl                    ;; [5] (SMC) modify jump access
    pop     hl                                  ;; [3] retrieve screen adress
    jr      bh_jumpRepeat                       ;; [3] Jumps over specific Box Access 

;; Box-only draw path; cpct_bayerPrepareBoxLine_asm must be called first.
cpct_drawBayerLineFastBox_asm::
    ld__a_ixl                                   ;; [2] A = Left Subpixel
    ld__iyh_a                                   ;; [2] Copy into IYH for possible modification

    ; Retrieve bayer octet
    ex      de,hl                               ;; [1] Preserve hl=screenAdress in de
    ld      hl,(bayer_intensityPtr)             ;; [5] Get current intensity adress 
    ld      a,c                                 ;; [1] A = Bayer subline (0..3)
    or      l                                   ;; [1] Add subline to pointer (LUT is aligned to 4 Bytes)
    ld      l,a                                 ;; [1] HL = Adress of subline for this intensity
    ld      a,(hl)                              ;; [2] A = Intensity Octect of subLine
    ex      de,hl                               ;; [1] Retrieve hl = screenAdress - e = nbOctet
    ld      d,a                                 ;; [1] D = Intensity octet of subline

    ld__a_iyl                                   ;; [2] A = NbOctet
    or      a                                   ;; [1] Check == 0 ?
    jp      z,#bh_lastOctet                     ;; [3] Yes, we already are on last octet
    ld__a_iyh                                   ;; [2] A = Left Subpixel
    or      a                                   ;; [1] Check == 0 ?
    jr      z,bh_jumpRepeat                     ;; [2/3] If left subpixel is first one, we can repeat NbOctet directly
    ld      c,#3                                ;; [2] Set right subpixel = 3 (last)
    call    b_setScreenOctetFromSubpixels       ;; [5] Modify first octet from Left subpixel to last
    xor     a                                   ;; [1] A = 0
    ld__iyh_a                                   ;; [2] Set Left subpixel to 0 for last octet

bh_jumpRepeat:
bh_jmpBlock=. + 1
    jp      bh_lastOctet                        ;; [3] (SMC) Jumps to correct amount of octet to draw
    .rept   79
    ld      (hl),d                              ;; [2] Set screen octet to current intensity full octet
    inc     hl                                  ;; [2] Increase screen adress
    .endm
bh_lastOctet:
    ld__c_ixh                                   ;; [2] C = rightsubpixel
    ld__a_iyh                                   ;; [2] A = current left subpixel (either input or 0)

;; Set an octet subpixels from a to c with color in d
b_setScreenOctetFromSubpixels:                  
    push    hl                                  ;; [4] Preserve hl = screen adress
    ld      b,#0                                ;; [2] reset b
    add     a,a                                 ;; [1] a = lsp*2
    add     a,a                                 ;; [1] a = lsp*4
    add     a,c                                 ;; [1] a = lsp*4 + rsp
    ld      c,a                                 ;; [1] bc = index in table
    ld      hl, #cpct_subPixelHorizontalMask_M1 ;; [3] mask table
    add     hl,bc                               ;; [3] hl = adress of mask to use
    ld      a,(hl)                              ;; [2] a = mask to use for reset pixels with new color
    pop     hl                                  ;; [3] Restore adress
;; Use mask on screen octet
    ld      c,a                                 ;; [1] save mask
    and     (hl)                                ;; [2] a = current screen pixels with clear pixels from mask
    ld      b,a                                 ;; [1] b = current screen octet (cleared from left subpixel to subpixel 3)
    ld      a,c                                 ;; [1] retrieve mask
    cpl                                         ;; [1] invert mask
    and     d                                   ;; [1] set requested color to inverted pixelsmask
    or      b                                   ;; [1] merge result with current screen octet
    ld      (hl),a                              ;; [2] Set screen octet
    inc     hl                                  ;; [2] Next screen octet
    ret                                         ;; [3] return


;;-------------------------------------------------------------------------------
;; Function: <cpct_compareSigned16_asm>
;;-------------------------------------------------------------------------------
;;
;;    Do the comparison of 2 signed 16 bit values.
;;    Returns normal 8 bit comparison flag values.
;;
;;   Input:
;;    HL = Input value
;;    DE = Comparison value
;;   
;;   Output
;;    F Flags
;;    
;;   Modifies A BC - Preserve HL DE
;;    
;; Timings
;;     17 NOPS max

;; Compare signed 16-bit HL with signed 16-bit DE; carry means HL < DE. z means HL == DE
cpct_compareSigned16_asm::                      ;; Shared signed-coordinate comparison helper.
    ld      a,h                                 ;; [1] Load HL's high byte.
    xor     #0x80                               ;; [2] Bias its sign bit for unsigned ordering.
    ld      b,a                                 ;; [1] Save the biased high byte of HL.
    ld      a,d                                 ;; [1] Load DE's high byte.
    xor     #0x80                               ;; [2] Bias its sign bit for unsigned ordering.
    ld      c,a                                 ;; [1] Save the biased high byte of DE.
    ld      a,b                                 ;; [1] Compare the biased high bytes first.
    cp      c                                   ;; [1] Set carry/zero flags for the high-byte order.
    ret     nz                                  ;; [2/4] Return when the high bytes differ.
    ld      a,l                                 ;; [1] High bytes match; load HL's low byte.
    cp      e                                   ;; [1] Compare low bytes as unsigned values.
    ret                                         ;; [3] Return carry/zero flags for the full comparison.


;;-------------------------------------------------------------------------------
;; Function: <cpct_compScreenLine_asm>
;;-------------------------------------------------------------------------------
;;
;;    Retrieve the screen adress of a unsigned row value based on geomStartScreen.
;;    Uses X=0 to compute it
;;
;;   Input:
;;    B = Y row (unsigned value)
;;   
;;   Output
;;    (bayer_screenY) and HL = Screen adress of row if Y >=0, start screen adress if Y<0
;;    
;;    Modified AF BC DE 
;;    
;; Timings
;;     21 NOP (+ call to cpct_getScreenPtr_asm 37 NOP)

cpct_compScreenLine_asm::
    ld      de,(geomStartScreen)                ;; [6] Get stored start screen
    ld      c,#0                                ;; [2] c = X = 0
    call    cpct_getScreenPtr_asm               ;; [5] compute HL = Y screen adress of B = Row 
    ld      (bayer_screenY),hl                  ;; [6] Stores the Adress in internal bayer variable
    ret                                         ;; [3] return

;;-------------------------------------------------------------------------------
;; Function: <cpct_incScreenLine_asm>
;;-------------------------------------------------------------------------------
;;
;;    Increases the screen adress line stored in bayer_screenY into next one.
;;
;;   Input:
;;    A = Y + 1 value
;;    
;;    Modified AF HL BC 
;;    
;; Timings
;;     31 NOPS max

cpct_incScreenLine_asm::
    ld      hl,(bayer_screenY)                  ;; [5] HL = screen Y Adress
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
    ld      (bayer_screenY),hl                  ;; [5] Store HL = screen Y+1 Adress
    ret                                         ;; [3] Return
