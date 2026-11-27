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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_setBayerMatrixM1
;;
;;    Sets starting screen adress, intensity and color pens of 4x4 Bayer dithering APIs
;;
;; C Definition:
;;    void <cpct_setBayerMatrixM1>(u8* vmem, u16 intensity, u8 pen1, u8 pen2);
;;      (u8 *) vmem         - Starting adress of screen (typically 0xC000)
;;      (u16 ) intensity    - Bayer intensity from pen1 (0) to pen2 (15)
;;      (u8  ) pen1         - Pen to use for color 1
;;      (u8  ) pen2         - Pen to use for color 2
;;
;; Assembly:
;;      call <cpct_setBayerMatrixM1_asm>
;;
;; Assembly input Parameters:
;;    (2B HL)     vmem start (typically 0xC000)
;;    (1B  E)     intensity of bayer dithering (0..15)
;;    (1B  C)     pen1 (0..3)
;;    (1B  B)     pen2 (0..3)
;;
;; Details:
;;    Stores starting adress for all bayer API calls.
;;    Prepare a 15 * 4 table filled with full octet value for each intensity by line.
;;    Stores a pointer to current intensity adress inside the table.
;;    Stores current pens and intensity to accelerate computation.
;;
;; Notes:
;;    Bayer dithering 4x4 matrix is a way to fill an area with a gradient matrix between 2 colors.
;;    Intensity 0 uses the full color 1, intensity 15 uses 15 pixel of color 2 and 1 of color 1.
;;    An increase of one in intensity adds a new color 2 pixel inside the 4x4 bayer matrix.   
;;    The bayer matrix is fixed with the screen coordinates, so when a geometry moves, filling area does not.
;;
;; Destroyed Register values:
;;    BC, DE, HL
;;
;; Required memory:
;;    188 bytes (95 bytes + 90 bytes for bayer internal data + 3 bytes C binding wrapper)
;;    (+4 bytes for bayer internal data)
;;
;; (start code)
;;    Case                        | microSecs (us) | CPU Cycles
;;   -----------------------------------------------------------
;;    Modify pens and intensity   | ~4834          | ~19336
;;    Modify pens only            | ~4812          | ~19248
;;    Modify intensity only       | ~51            | ~204
;;   ---------------------------------------------------------------------------------
;; (end code)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.globl      bayer_pen1
.globl      bayer_pen2
.globl      bayer_intensity
.globl      bayer_intensityPtr
.globl      bayer_lutM1
.globl      bayer_lutM1_end
.globl      bayer_matrix4x4_end
.globl      bayer_fullColorBytes
.globl      geomStartScreen

.macro  addPen2toPixel  MASK,CPLMASK,?lbl
    dec     hl                          ;; [2] Move to previous bayer matrix value
    ld      a,(hl)                      ;; [2] get bayer matrix value
    cp      c                           ;; [1] Compare with current intensity
    jr      nc,#lbl                     ;; [2/3] If < intensity use pen1 so jump
    jr      z,#lbl                      ;; [2/3] If = intensity use pen1 so jump
    ld      a,b                         ;; [1] A = current computed octet
    and     #CPLMASK                    ;; [2] Clear current pixel
    ld      b,a                         ;; [1] Stores it
    ld      a,#MASK                     ;; [2] Current pixel mask
    and__iyh                            ;; [2] Set pen2 on pixel
    or      b                           ;; [1] Add current filtered octet
    ld      b,a                         ;; [1] Stores it
lbl:                                    ;;  exit macro label
.endm

;;  Start

    ld      (geomStartScreen),hl        ;; [5] Stores screen start

;; Check of previous calls to recompute only when needed
    ld      a,(bayer_pen2)              ;; [4] Retrieve A = current pen2
    cp      b                           ;; [1] Check if pen2 modified
    jr      nz,#b_computeMx             ;; [2/3] Different? Need to recompute
    ld      a,(bayer_pen1)              ;; [4] Retrieve A = current pen1
    cp      c                           ;; [1] Check if pen1 modified
    jp      z,#b_checkIntensity         ;; [2/3] Equal? Move to intensity check

b_computeMx:
    push    de                          ;; [4] Stores intensity
    push    iy                          ;; [5] To get 2 more 8 bit registers
    ld      a,c                         ;; [1] A = pen1
    ld      (bayer_pen1),a              ;; [4] Store pen1
    ld      a,b                         ;; [1] A = pen2
    ld      (bayer_pen2),a              ;; [4] Store pen2
    ld      hl,#bayer_fullColorBytes    ;; [3] HL = Start of full color array
    ld      d,#0                        ;; [2] D = 0
    ld      e,b                         ;; [1] DE = Pen 2
    add     hl,de                       ;; [3] HL = Pen 2 full color adress (Carry is reset)
    ld      a,(hl)                      ;; [2] A = Full color of pen2
    ld__iyh_a                           ;; [2] IYH = Full color of pen2
    sbc     hl,de                       ;; [4] Move back to start adress
    ld      e,c                         ;; [1] DE = Pen 1 
    add     hl,de                       ;; [3] HL = Pen 1 full color adress
    ld      a,(hl)                      ;; [2] A = Full color of pen1
    ld__iyl_a                           ;; [2] IYL = Full color of pen1
    ld      de,#bayer_lutM1_end         ;; [3] DE = End of LUT (intensity = 15)
    ld      a,e                         ;; [1] A = LSB end of LUT adress 
    and     #0xFC                       ;; [2] Align to previous 4 boundary
    ld      e,a                         ;; [1] DE = End of LUT but 4 aligned (last 2 bits = 0)
    ld      c,#15                       ;; [2] Let's compute all 16 intensities
b_loopIntensity:
    ld      b,#4                        ;; [2] For 4 lines

    ld      hl,#bayer_matrix4x4_end     ;; [3] As we are doing it reverse, we start from last Bayer Matrix adress
b_loopLine:
    push    bc                          ;; [4] Stores loops values
    ld__b_iyl                           ;; [2] B=Full color of pen1 = Starting color of octet, output of line

    ;; addPen2toPixel compares matrix value with C (intensity) modifies B with pen2 if needed and decrease hl
    addPen2toPixel  0x11   0xEE         ;; [7/19] Check/set sub pixel 0
    addPen2toPixel  0x22   0xDD         ;; [7/19] Check/set sub pixel 1
    addPen2toPixel  0x44   0xBB         ;; [7/19] Check/set sub pixel 2
    addPen2toPixel  0x88   0x77         ;; [7/19] Check/set sub pixel 3

    ex      de,hl                       ;; [1] DE = Bayer Matrix HL = Destination LUT 
    dec     hl                          ;; [2] Decrease LUT
    ld      (hl),B                      ;; [2] Set LUT value
    ex      de,hl                       ;; [1] HL = Bayer matrix DE = Destination LUT

    pop     bc                          ;; [3] Retrieves loop values
    djnz    #b_loopLine                 ;; [3/4] Doing 4 lines
    ld      a,c                         ;; [1] Check current intensity
    or      a                           ;; [1] is it 0
    jr      z,b_endLoopIntensity        ;; [2/3] if so end the loop
    dec     c                           ;; [1] Decrease intensity
    jr      #b_loopIntensity            ;; [3] loop on intensity
b_endLoopIntensity:
    pop     iy                          ;; [5] Retrieve IY from Matrix algo
    pop     de                          ;; [3] Retrieve intensity from Matrix algo
b_checkIntensity:
    ld      a,(bayer_intensity)         ;; [4] Current stored intensity
    cp      e                           ;; [1] Compare with input intensity
    ret     z                           ;; [2/4] Equal? No need to change ptr
    ld      hl,#bayer_lutM1             ;; [3] HL = start of LUT
    ld      a,l                         ;; [1] A = LSB of LUT
    and     #0xFC                       ;; [2] Clear bit 0 and 1 from LSB
    ld      l,a                         ;; [1] HL = LUT aligned to 4
    ld      a,e                         ;; [1] a = intensity
    ld      (bayer_intensity),a         ;; [4] Store new intensity
    rlca                                ;; [1] a = a * 2
    rlca                                ;; [1] a = a * 2 = intensity * 4    
    ld      d,#0                        ;; [2] Reset d
    ld      e,a                         ;; [1] e = intensity * 4
    add     hl,de                       ;; [3] HL = adress of intensity of line 0 (and easy access line 1..3)
    ld      (bayer_intensityPtr),hl     ;; [5] Stores the ptr to use inside bayer draw APIs
    ret                                 ;; [3] Return

.area   _DATA

;; Default data is computed with pen1 = 1 and pen2 = 2
bayer_pen1:        .db    0xFF          ;; (1) Current pen1 value (0..3) - default to recompute
bayer_pen2:        .db    0xFF          ;; (1) Current pen2 value (0..3) - default to recompute
bayer_intensity:   .db    0xFF          ;; (1) Current intensity (0..15) - default to recompute

bayer_fullColorBytes: 
    .db      #0x00, #0xF0, #0x0F, #0xFF ;; (4) pen 0..3 full color

;; Constant 4x4 matrix of 0..15 bayer dithering
;; If M[x,y] <= intensity : use pen1 else pen2
bayer_matrix4x4:
    .db      0x00, 0x08, 0x02, 0x0A     ;; (4)
    .db      0x0C, 0x04, 0x0E, 0x06     ;; (4)
    .db      0x03, 0x0B, 0x01, 0x09     ;; (4)
    .db      0x0F, 0x07, 0x0D, 0x05     ;; (4)
bayer_matrix4x4_end:

;; LUT of 16 intensity by 4 lines octet values
;; Small buffer to help bayer_LUTM1 to align on 4 for easy line adding in adress with an OR
paddingForAlignment: .ds 3              ;; (3) Padding values to align on 4
bayer_lutM1:         .ds 64             ;; (64) 16 values of 4 lines + 3 to find an alignement adress
bayer_lutM1_end:
