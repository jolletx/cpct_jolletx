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
;; Function: cpct_scanFillM0
;;
;;    Fills an area defined by a point and its actual color with a new color in Mode 0 (160x200, 16 colors)
;;
;; C Definition:
;;    void cpct_scanFillM0 (u8* vmem, u16 x, u8 y, u8 newColor) __z88dk_callee;
;;
;; Input Parameters:
;;    (2B HL)  vmem       - Base VRAM memory address (typically 0xC000)
;;    (2B DE)  x          -  X coordinate (0-159 no checks)
;;    (1B  C)  y          -  Y coordinate (0-199 no checks)
;;    (1B  B)  newColor   -  Color to use (0-15)
;;
;; Assembly call:
;;    > call cpct_scanFillM0_asm
;;
;; Destroyed Register values:
;;    AF, BC, DE, HL
;;
;; Algorithm & Details:
;;    Scanline Fill, starting from a point, it fills the area with the color specified.
;;    It will stop when it finds a pixel with a different color than the one found initialy
;;
;;    Init algo: 
;;       get screen adress from X,Y, compute X Offset and subpixel, get old color on X,Y
;;       Compute new and old_color subpixels and full octet, exit if new color == old color
;;       Push X Offset, subpixel and Y in point stack 
;;    Main loop:
;;        pop a point from stack - Exit is stack was empty (no more things to do)
;;        drawOnLeft to find left most pixel which is still old_color, try to use full_octet if possible. Stop at begining of screen if needed.
;;        drawOnRight to find right most pixel which is still old_color, try to use full_octet if possible. Stop at end of screen if needed.
;;        get left side of line on above line (decreasing Y)   (do it again after with below line (increase y)
;;        initSubLoop
;;             set a search flag to 'search old_color'
;;        subLoop
;;             if geomStep is 'search Old Color'
;;                check if pixel is old color
;;                if yes
;;                   pushcurrent  point into stack and set search flag to 'search not old color'
;;             else  (search for 'not old color')
;;                check if pixel is old color
;;                if not
;;                   set search flag to 'search old color'
;;             endif
;;             move to next pixel on the right, check if right end of previous drawnn line reached to exit subLoop
;;             try to jump over full octets
;;                old color if 'not old color' (will slow back to pixel checks if not found)
;;                new_color if 'old_color'  (only case we have values ready, else switch back to pixel check)
;;                fall back to pixel checking in doubt, exit subLoop if right end of drawn line is reached or passed
;;
;;    Comment on stack size:
;;        A memory buffer is set to store next points to check above and below vurrent line.
;;        By default this is a 30 points storage using 2 Bytes each, 60 Bytes.
;;        If area to fill has a lot of different vertical area to fill
;;        the algorithm will need all this area. The algorithm stops adding points if 
;;        buffer is filled. So some area will not be checked and some area may miss in result.
;;        A simple rectangular area just need 2 points.
;;        If you know how many elements in stacks you need, you can adjust 
;;        the STACK_SIZE value to your need and recompile cpctelera to decrease memory need.
;;
;; (start code)
;; Required memory:
;;    578 bytes core routine (including 3 bytes of c binding) + 81 bytes data
;;
;; Test measure: 
;;    Screen set to color 0
;;    4 points:
;;       pt1 (80,100) pt2 (125,75) pt3 (150,100) pt4 (125,125)
;;    4 lines of color 2 between:
;;       pt1,pt2  pt2,pt3 pt3,pt4 pt4,pt1
;;    Time to fill from pt (125,100) with color 3
;;
;;  Totals and assumptions (approximate):
;;    Pixels drawn: 1,201
;;    Drawing work: 1,201 pixels at an average of about 23.6 NOPs/pixel = 28,300 NOPs
;;    Above/below checks and point-queue work: about 42.8 NOPs/pixel = 51,400 NOPs
;;    Core total: 28,300 + 51,400 = 79,700 NOPs
;;  Estimated overall:
;;    79,700 NOPs plus roughly 30 NOPs for the initial screen-pointer helper
;;    and 10 NOPs for the C-binding overhead = 79,740 NOPs; round to about
;;    80,000 NOPs, allowing a few hundred more for setup.
;; (end code)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Global Methods
.globl cpct_getScreenPtr_asm

;; Common geometry variables
.globl geomStartScreen
.globl geomCurrentY              
.globl geomIndex                 ;; Current stack index
.globl geomCurrentPtr            ;; Current stack pointer
.globl geomStep                  ;; Search Flag to check if looking for old color or not
.globl geomLeftScrOctet          
.globl geomLeftSubPixel
.globl geomInputPtr              ;; Used as left screen adress
.globl geomCurScrOctet
.globl geomCurSubPixel
.globl geomOutputPtr             ;; Used as current screen adress

;; ScanFill variables 
.globl sf_stack
.globl sf_newColorM0
.globl sf_newColorFull
.globl sf_oldColorM0
.globl sf_oldColorFull

;;-------------------------------------------------------------------------------
;; CODE SECTION
;;-------------------------------------------------------------------------------
.area _CODE

   ;;  Inputs: HL = VMEM start ptr - DE = X - C  = Y - B  = New Color 
   ld    (geomStartScreen),hl       ;; [5] Store VMem start
   ld    a,c                     ;; [1] A = Y coord
   ld    (geomCurrentY),a           ;; [4] Store Y value

   ;; Compute new color values
   ;; compute sub pixel 1 - Assuming d=0 because DE < 160 - 
   ;; Input color (0..15)  B = 0  0  0  0  b3 b2 b1 b0
   ;; Need to compute      A = 0  b0 0  b2 0  b1 0  b3
   xor   a                       ;; [1] A =  0  0  0  0  0  0  0  0  CF=0
   srl   b                       ;; [2] B =  0  0  0  0  0  b3 b2 b1 CF=b0
   rla                           ;; [1] A =  0  0  0  0  0  0  0  b0 CF=0  
   rla                           ;; [1] A =  0  0  0  0  0  0  b0 0  CF=0  
   srl   b                       ;; [2] B =  0  0  0  0  0  0  b3 b2 CF=b1
   rl    d                       ;; [2] D =  0  0  0  0  0  0  0  b1 CF=0
   srl   b                       ;; [2] B =  0  0  0  0  0  0  0  b3 CF=b2
   rla                           ;; [1] A =  0  0  0  0  0  b0 0  b2 CF=0  
   rla                           ;; [1] A =  0  0  0  0  b0 0  b2 0  CF=0  
   rla                           ;; [1] A =  0  0  0  b0 0  b2 0  0  CF=0  
   or    d                       ;; [1] A =  0  0  0  b0 0  b2 0  b1 CF=0
   rla                           ;; [1] A =  0  0  b0 0  b2 0  b1 0  CF=0
   rla                           ;; [1] A =  0  b0 0  b2 0  b1 0  0  CF=0  
   or    b                       ;; [1] A =  0  b0 0  b2 0  b1 0  b3 CF=0   CQFD :)  

   ld    (sf_newColorM0 + 1),a         ;; [4] Stores subpixel 1 new color
   ld    b,a                     ;; [1] B = subpixel 1
   rlca                          ;; [1] Rotate copy Carry - A = Subpixel 0
   ld    (sf_newColorM0),a           ;; [4] Stores subpixel 0 new color
   or    b                       ;; [1] A = full octet of sf_newColorM0
   ld    (sf_newColorFull),a      ;; [4] Stores full_octet  

   ;; Compute Screen adress and sub pixel offset from X,Y
   xor   a                       ;; [1] A = 0
   srl   e                       ;; [2] E = byte offset , CF = subpixel
   rla                           ;; [1] A = subpixel
   ld    (geomCurSubPixel),a        ;; [4] Store subpixel
   ld    a,e                     ;; [1] A = screen byte offset
   ld    (geomCurScrOctet),a     ;; [4] Store current x coord
   ld    b, c                    ;; [1] b = Y
   ld    c, a                    ;; [1] c = X in bytes
   ld    de,(geomStartScreen)       ;; [6] de = VMEM_START_ADRESS
   call  cpct_getScreenPtr_asm   ;; [5] HL = Current adress

   ;; Get and store old color from adress HL and sub pixel offset (don't care about offical pen value)
   ld    a,(geomCurSubPixel)        ;; [4] A = X coord
   or    a                       ;; [1] Check subpixel 
   ld    a,(hl)                  ;; [2] A = Screen octet
   jr    z,storeOldCol           ;; [2/3] jump over rotation if subpixel 0
   rlca                          ;; [1] rotate copy carry to left to put subpixel 1 into subpixel 0
storeOldCol:
   and   #0xAA                   ;; [2] Masks subpixel 0
   ld    hl,#sf_oldColorM0           ;; [3] hl = adress of sf_oldColorM0
   ld    (hl),a                  ;; [2] Stores subpixel 0 
   inc   hl                      ;; [2] points sf_oldColorM0+1 = subpixel 1
   ld    b,a                     ;; [1] B = subpixel 0
   rrca                          ;; [1] Rotate copy Carry - A = Subpixel 1
   ld    (hl),a                  ;; [2] Stores subpixel 1 
   inc   hl                      ;; [2] Points sf_oldColorM0+2 = full octet
   or    b                       ;; [1] A = sbp1 | sbp0 = full octet of sf_oldColorM0
   ld    (hl),a                  ;; [2] Stores full_octet  

   ld    hl,#sf_newColorFull      ;; [3] hl = adress of sf_newColorFull
   cp    (hl)                    ;; [2] Check if sf_oldColorM0 == sf_newColorM0
   ret   z                       ;; [2/4] If equal sf_oldColorM0==sf_newColorM0, end : nothing to replace

initALgo:
   ;; Init Stack
   xor   a                       ;; [1] A = 0
   ld    (geomIndex),a           ;; [4] Stack index = 0
   ld    a,<#sf_stack            ;; [2] A = low byte of Stack Adress
   ld    (geomCurrentPtr),a        ;; [4] Init low Stack Adress
   ld    a,>#sf_stack            ;; [2] A = high byte of Stack Adress
   ld    (geomCurrentPtr+1),a      ;; [4] Init high Stack Adress

   ld    de,(geomCurScrOctet)    ;; [6] Retrieve current values for init
   ld    a,(geomCurrentY)           ;; [4] Retrieve Y value
   ld    c,a                     ;; [1] c = y val

   call  pushPoint               ;; [5] Push current point DE, C into stack

   ;; During loop, D = subpixel, E = X-octet, C = Y, HL = compute adress based on E/C
mainLoop:
   call  popPoint                ;; [5] Pop next point from stack into DE, C
   ret    z                      ;; [2/4] If stack is empty, algo is finished

   call  computeAdress           ;; [5] Retrieve HL adress based on E,C (untouched)
   ld    a,c                     ;; [1] a = y value
   ld    (geomOutputPtr),hl         ;; [5] Save cur adress
   ld    (geomCurScrOctet),de    ;; [6] and byte offset / subpixel
   ld    (geomCurrentY),a           ;; [4] and Y value

   call  checkOldColor           ;; [5] If point is no more old color, we have already turned around this point and fill it
   jr    nz,mainLoop             ;; [2/3] Skip it

	ld    a,(sf_newColorFull)  	   ;; [4] A = sf_newColorM0 full
   ld    b,a                     ;; [1] b = full octet new color

   call  searchAndDrawLeft       ;; [5] Find first left pixel which is not an old color

   ld    (geomInputPtr),hl        ;; [5] Store last old color left adress
   ld    (geomLeftScrOctet),de   ;; [6] Store last old color Left byte and subpixel

   ld    hl, (geomOutputPtr)        ;; [5] Retrieve starting values
   ld    de, (geomCurScrOctet)   ;; [6] "       "      "
   call  searchAndDrawRight      ;; [5] Find first right pixel which is not an old color

   ld    (geomOutputPtr),hl         ;; [5] Store last right adress for above and below boundaries checks
   ld    (geomCurScrOctet),de    ;; [6] Store last right byte and subpixel
ml_searchNewPoints:              ;; Check lines above and below for new points

   ld    hl, (geomInputPtr)       ;; [5] Retrieve left values
   ld    de, (geomLeftScrOctet)  ;; [6]

   ;; Move along upper line to check if new points should be stacked
   call  changeYUp               ;; [5] Compute a new HL and C (c = Y -1), z if c==0 when called
   jr    z,ml_checkBelow         ;; [2/3] Cannot move up, check other line
   call  searchNewPoints         ;; [5] Push new points inside stack if sf_oldColorM0 found above drawn line
   inc   c                       ;; [1] Accomodate Y valuebefore resetting HL to current line
ml_checkBelow:                   ;; C was not changed if from jr z
   ld    hl, (geomInputPtr)       ;; [5] Retrieve left values (C = Y)
   ld    de, (geomLeftScrOctet)  ;; [6]
   call  changeYDown             ;; [5] Compute a new HL and C, z if top of screen reached
   jr    z,ml_continue           ;; [2/3] Cannot move down, check other line
   call  searchNewPoints         ;; [5] Push new points inside stack if sf_oldColorM0 found above drawn line
ml_continue:
   jr    mainLoop                ;; [3] Check new point in stack

searchAndDrawLeft:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Move HL / DE / B until a pixel which is not sf_oldColorM0 or left of screen
;; First pixel is set here
sdl_loopSubpixel:
   call  plotPixel               ;; [5] set new color of d subpixel at HL with color B, first pixel is drawn here
   call  decreaseSubpixel        ;; [5] move cur pixel to the left
   ret   z                       ;; [2/4] if ZFLag, we have reach left screen boundary

   ld    a,d                     ;; [1] a = subpixel
   or    a                       ;; [1] check if a is subpixel 0 (so moved from 1 to 0)
   jr    z, sdl_checkSubpixel    ;; [2/3] Yes ?  so we are not on right subpixel and can't check whole octet

   ld    a,(sf_newColorFull)      ;; [4] a = new color full octet
   ld    b,a                     ;; [1] b = new color full octet
   ld    a,(sf_oldColorFull)      ;; [4] a = old color full octet
sdl_loopFullOctet:
   cp    (hl)                    ;; [2] check with screen octet
   jr    nz,sdl_checkSubpixel    ;; [2/3] if not full octet let's do it one subpixel by one subpixel
   ld    (hl),b                  ;; [2] Set full octet to new color
   dec   hl                      ;; [2] decrease adress
   dec   e                       ;; [1] decrease X OCtet
   jp    p, sdl_loopFullOctet    ;; [3] if positif or 0 loop
   ld    d,#0                    ;; [2] d = left subpixel
   inc   hl                      ;; [2] move back to last adress
   inc   e                       ;; [1] set e = 0, so ZFlag is set
   ret                           ;; [3] ret with ZFlag set
sdl_checkSubpixel:
   call  checkOldColor           ;; [5] is subpixel of old color
   jr    z,sdl_loopSubpixel      ;; [2/3] if old color draw it and continue

   call  increaseSubpixel        ;; [5] if not, last subpixel was the last one - move back to it
   ret                           ;; [3] return

searchAndDrawRight:              ;; Move HL / DE until a pixel which is not sf_oldColorM0 or Right of screen - b = full octet sf_newColorM0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Move and draw HL / DE  until a pixel which is not sf_oldColorM0 or right of screen
;; First pixel is skipped here (because leftDraw has already done it)
sdr_loopSubpixel:
   call  increaseSubpixel        ;; [5] Move to subpixel on right
   ret   z                       ;; [2/4] if ZFLag, we have reach right screen boundary

   ld    a,d                     ;; [1] a = subpixel
   or    a                       ;; [1] check if left subpixel (so we reached a new octet)
   jr    nz, sdr_checkSubpixel   ;; [2/3] No ?  Let's print it and move to another one

   ld    a,(sf_newColorFull)      ;; [4] a = new color full octet
   ld    b,a                     ;; [1] c = new color full octet
sdr_loopFullOctet:
   ld    a,(sf_oldColorFull)      ;; [4] a = old color full octet
   cp    (hl)                    ;; [2] check with screen octet
   jr    nz,sdr_checkSubpixel    ;; [2/3] if not full octet let's do it one subpixel by one subpixel
   ld    (hl),b                  ;; [2] Set full octet to new color
   ld    a,e                     ;; [1] a = X OCtet
   cp    #screenNbOctet          ;; [2] Compare with screen size (79)
   jr    z,sdr_lastOctet         ;; [2/3] we reached end of line
   inc   hl                      ;; [2] if not move to next adress
   inc   e                       ;; [1] e = X + 1
   jp    sdr_loopFullOctet       ;; [3] loop
sdr_lastOctet:
   inc   d                       ;; [1] set subpixel to right one
   ret                           ;; [3] ZFlag is still set here
sdr_checkSubpixel:
   call  checkOldColor           ;; [5] is subpixel of old color
   jr    nz,sdr_lastSubpixel     ;; [2/3] if old color draw it and continue
   call  plotPixel               ;; [5] chenge color of subpixel
   jr    sdr_loopSubpixel        ;; [3] continue
sdr_lastSubpixel:
   call  decreaseSubpixel        ;; [5] if not, last subpixel was the last one
   ret                          ;; [3] return

searchNewPoints:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; check and push points which are sf_oldColorM0 (wait for end of sf_oldColorM0 to add another one found)
;; and move to the right until end of previously draw Line 
   ;; Init
   xor   a                       ;; [1] a = 0
   ld    (geomStep),a          ;; [4] reset search flag insertion - looking For sf_oldColorM0 (jump over full new color)

   ;; Alternate between searching sf_oldColorM0 and jumping above sf_oldColorM0 on current line
   ;; Stops when end of right drawn line reached
snp_mainLoop:
   ld    a,(geomStep)          ;; [4] get current geomStep
   or    a                       ;; [1] check == 0
   jr    nz,snp_searchEndOC      ;; [2/3] if !=0 we are looking for end of sf_oldColorM0

;; searching for sf_oldColorM0 pixels
   call  checkOldColor           ;; [5] Do we have an sf_oldColorM0 here?
   jr    nz,snp_nextSearchSP     ;; [2/3] no, move to next subpixel
   
   call  pushPoint               ;; [5] We have a hit, push it on stack and switch flag
   or    a,#0x01                 ;; [2] a != 0
   ld    (geomStep),a          ;; [4] flag != 0 means, search for first pixel which is not sf_oldColorM0 (jump over sf_oldColorM0)
   jr    snp_nextSearchSP        ;; [3] move to next subpixel
snp_searchEndOC:
   call  checkOldColor           ;; [5] search for another color in pixel
   jr    z,snp_nextSearchSP      ;; [2/3] Still old color, wait for another color
   xor   a                       ;; [1] set a = 0
   ld    (geomStep),a          ;; [4] Reset flag : search for old color again
                                 ;; continue to next subpixel
snp_nextSearchSP:
   call  increaseSubpixel        ;; [5] move to right one subpixel
   ret   z                       ;; [2/4] stop if already at end of screen
   call  checkEndOfDrawnLine     ;; [5] Check if end of draw line
   ret   z                       ;; [2/4] stop if increase has gone after drawn line
   ld    a,d                     ;; [1] a = subpixel
   or    a                       ;; [1] check a == 0
   jr    nz, snp_mainLoop        ;; [2/3] Not starting a new octet, let's loop on sub pixels

   ld    a,(geomStep)          ;; [4] check the geomStep to set correct full_octet to test
   or    a                       ;; [1] 
   jr    z,snp_useNewColor       ;; [2/3] if searching for sf_oldColorM0 , we can skip sf_newColorFull octets

   ld    a,(sf_oldColorFull)      ;; [4] a = old color full octet
   jr snp_setColorToJump         ;; [3] continue with this color
snp_useNewColor:
   ld    a,(sf_newColorFull)      ;; [4] a = new color full octet
snp_setColorToJump:
   ld    b,a                     ;; [1] b = color full octet to skip
snp_loopFullOctet:
   ld    a,(geomCurScrOctet)     ;; [4] a = right X Offset
   cp    e                       ;; [1] compare with current X Offset
   ret   c                       ;; [2/4] We move above last pixel (e > a), ret from there
   ld    a,b                     ;; [1] a = color full octet to skip
   cp    (hl)                    ;; [2] compare with screen octet
   jr    nz,snp_mainLoop         ;; [2/3] not equal so we need to check pixels
   inc   e                       ;; [1] increase X ofsset  (keep d = 0 left subpixel)
   inc   hl                      ;; [2] inc screen adress
   jr    snp_loopFullOctet       ;; [3] loop on full octets

checkEndOfDrawnLine:            ;; Return ZFlag when last pixel is passed (still no ZFlag on last subpixel)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,(geomCurScrOctet)     ;; [4] A = right X Offset
   cp    e                       ;; [1] compare actual X Offset with right X Offset
   ret   c                       ;; [2/4] if e > cur X, not on last octet
   jr    nz,cel_resetZFlag       ;; [2/3] if e < cur X, line is overpassed
   ld    a,(geomCurSubPixel)        ;; [4] here e == cur X so check subpixel, A = righ subpixel
   cp    d                       ;; [1] compare with actual subpixel, d must be > a to fire ZFlag
   jr    nc,cel_resetZFlag       ;; [2/3] d <= a , no flag
   xor   a                       ;; [1] force ZFLag ON
   ret   nc                      ;; [2/4] if d <= cur subPixel, ZFlag is set appropiately with comparison
                                 ;; if d> cur subpixel need to set ZFlag
cel_resetZFlag:  
   or   #0x01                    ;; [2] force ZFlag to OFF
   ret                           ;; [3]

plotPixel:                       ;; Plot pixel D at (hl) in sf_newColorM0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   push  de                      ;; [4] Preserve DE
   push  hl                      ;; [4] Preserve HL = screen adress
   ld    a,d                     ;; [1] A = subpixel
   or    a                       ;; [1] Check A for subpixel 0
   ld    a,#0x55                 ;; [2] A = Mask to remove subpixel 0
   ld    hl,#sf_newColorM0           ;; [3] hl = adress of new color subpixel 0
   jr    z,pp_useMask            ;; [2/3] jr if subpixel 0
   rlca                          ;; [1] A = 0xAA = Mask to remove subpixel 1
   inc   hl                      ;; [2] HL = adress of sf_newColorM0 subpixel 1 
pp_useMask:
   ld    e,(hl)                  ;; [2] e = sf_newColorM0 subpixel
   pop   hl                      ;; [3] retrieve screen adress
   and   (hl)                    ;; [2] a = subpixel reset of screen octet
   or    e                       ;; [1] a = merge reset screen octet with sf_newColorM0 subpixel
   ld    (hl),a                  ;; [2] Set screen octet
   pop   de                      ;; [3] Retrieve DE
   ret                           ;; [3] return
computeAdress:                   ;; Compute HL = VMemStart + c mod 7 * &800 + 80 * (c % 7) + E  - From cpct_getScreenPtr_asm
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   push  bc                      ;; [4] Preserve BC
   ld    a, c                    ;; [1] rA = Y-Coordinate
   and   #0x07                   ;; [2] /
   ld    h, a                    ;; [1] \ rH = Y % 8      ;; << rH contains Line number [0-7] inside character Row
   xor   c                       ;; [1] / rA = ( rB and #0x07 ) xor rB  =  rB and #0xF8
   ld    l, a                    ;; [1] \ rL = 8*int(Y/8) ;; << L contains Screen Character Row multiplied by 8
   rrca                          ;; [1] /
   rrca                          ;; [1] \ rA' = rA / 4 = 2*int(Y/8)
   add   a, l                    ;; [1] /
   ld    l, a                    ;; [1] \ rL = rL + rA' = 8*int(Y/8) + 2*int(Y/8) = 10*int(Y/8)
   add   hl, hl                  ;; [3] /
   add   hl, hl                  ;; [3] |
   add   hl, hl                  ;; [3] \ rHL' = 8*rHL = 2048*L + 80*R
   ld    b,#0                    ;; [2] Reset b
   ld    c,e                     ;; [1] c = byte offset
   add   hl, bc                  ;; [3] rHL' = rHL + x octet
   ld    bc,(geomStartScreen)       ;; [6] BC = VMEM start
   add   hl, bc                  ;; [3] rHL' = rHL + geomStartScreen
   pop   bc                      ;; [3] retrieve BC
   ret                           ;; [3] return

checkOldColor:                  ;; Returns ZFlag ON if color of the pixel at (HL),D is an sf_oldColorM0
   ld    b,(hl)                  ;; [2] b = screen octet
   ld    a,(sf_oldColorFull)      ;; [4] A = full octet old color
   xor   b                       ;; [1] check if A == B
   ret   z                       ;; [2/4] If full octet is sf_oldColorM0 ret ZFlag

   push  hl                      ;; [4] save screen adress
   ld    a,d                     ;; [1] A = subpixel
   or    a                       ;; [1] Check subpixel
   ld    a,#0xAA                 ;; [2] A = Mask to remove subpixel 0
   ld    hl,#sf_oldColorM0           ;; [3] HL = adress of sf_oldColorM0 subpixel 0
   jr    z,co_useMask            ;; [2/3] if subpixel 0 jump
   inc   hl                      ;; [2] HL = adress of sf_newColorM0 subpixel 1
   rrca                          ;; [1] A = 0x55 = remove Subpixel 1
co_useMask:
   and   b                       ;; [1] a = masked screen octet
   xor   (hl)                    ;; [2] a = actual subpixel xor oldcolor pixel- ZFlag is set if A == (HL)
   pop   hl                      ;; [3] retrieve screen adress
   ret                           ;; [3] Z Flag is true if color found in pixel
pushPoint:                       ;; Push point DE and C into stack - FZ not set : OK - FZ set : no more room
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,(geomIndex)           ;; [4] Get current stack index
   cp    #SF_STACK_SIZE          ;; [2] Check if stack is full
   ret   z                       ;; [2/4] Return if full

   inc   a                       ;; [1] a = geomIndex + 1
   ld    (geomIndex),a           ;; [4] store geomIndex

   push  hl                      ;; [4] preserve hl
   ld    hl,(geomCurrentPtr)       ;; [5] HL = Stack Adress

   ;; let's put d at begining of e to save one byte in stack by point
   ld    a,d                     ;; [1] A = Subpixel (0..1)
   rrca                          ;; [1] CF = subpixel
   ld    a,e                     ;; [1] A = byte offset
   rla                           ;; [1] A = byte offset x 2 + subpixel = X coord

   ld    (hl),a                  ;; [2] Save X coord
   inc   hl                      ;; [2] Move down
   ld    (hl),c                  ;; [2] Save Y Coordinates
   inc   hl                      ;; [2] Move down
   ld    (geomCurrentPtr),hl     ;; [5] Save new stack address
   pop   hl                      ;; [3] retrieve hl

   ret                           ;; [3] Going back

popPoint:                        ;; Pop point into DE and C from stack - No need to preserve HL (recomputed) - FZ not set : OK - FZ set : empty stack
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,(geomIndex)           ;; [4] Get current stack index
   or    a                       ;; [1] Check if stack is empty
   ret   z                       ;; [2/4] If not empty, continue

   dec   a                       ;; [1] a = stck_idx - 1
   ld    (geomIndex),a           ;; [4] store geomIndex

   ld    hl,(geomCurrentPtr)       ;; [5] Points to last stack adress - no need to preserve, will be recomputed
   dec   hl                      ;; [2] Move up
   ld    c,(hl)                  ;; [2] Get Y coordinates
   dec   hl                      ;; [2] Move up
   ld    e,(hl)                  ;; [2] E =  cooordinate
   srl   e                       ;; [2] E = byte offset, CF = subpixel
   ld    d,#0                    ;; [2] D = 0
   rl    d                       ;; [2] D = subpixel
   ld    (geomCurrentPtr),hl       ;; [5] Save new stack address
   or    #0x01                   ;; [2] reset Z flag

   ret                           ;; [3] return
changeYUp:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,c                     ;; [1] a = c = Y value
   or    a                       ;; [1] Check if 0
   ret   z                       ;; [2/4] Top of screen reached, return ZFlag ON
   dec   c                       ;; [1] c = Y - 1
   and   #7                      ;; [2] Check Y char line 
   or    a                       ;; [1] Check if Y was on char line 0
   jr    z,cyu_adjustHL          ;; [2/3] if so, needs to adjust whole hl value
   ld    a,h                     ;; [1] a = MSB screen adress
   sub   a,#8                    ;; [2] a = a - 8 - Move to next line
   ld    h,a                     ;; [1] HL = HL - 0x800
   or    #1                      ;; [2] Resets zero flag if needed (can happe,n if VMEMStart = 0x0000)
   ret                           ;; [3] returns
cyu_adjustHL:
   push  bc                      ;; [4]
   ld    bc,#0x37B0              ;; [3] Set bc = 0x4000-0x50-0x800 to move from char line 0 to char line 7 of preious char line
   add   hl,bc                   ;; [3] Adjust hl to previous line
   pop   bc                      ;; [3]
   or    #0x01                   ;; [2] make sure ZFlag is OFF (we arrived with a jr z and add hl,bc does not impact it)
   ret                           ;; [3] return

changeYDown:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,c                     ;; [1] a = c = Y value
   cp    #YMax                   ;; [2] Compare with max screen height
   ret   z                       ;; [2/4] Top of screen reached, return ZFlag ON
   inc   a                       ;; [1] a = Y + 1
   ld    c,a                     ;; [1] c = Y + 1
   and   #7                      ;; [2] check if Y+1 is on a new char line
   jr    z,cyd_adjustHL          ;; [2/3] if yes, adjust HL 

   ld    a,h                     ;; [1] a = MSB screen adress
   add   a,#8                    ;; [2] a = a + 8 - Move to next line
   ld    h,a                     ;; [1] HL = HL + 0x800
   or    #1                      ;; [2] make sure ZFlag is OFF (not sure it can happen here)
   ret                           ;; [3] returns
cyd_adjustHL:
   push  bc                      ;; [4]
   ld    bc,#0xc850              ;; [3] Set bc = 0x800 - 0x4000 + 0x50  to move from char line 7 to char line 0 of next char line
   add   hl,bc                   ;; [3] Adjust hl to next line
   pop   bc                      ;; [3]
   or    #0x01                   ;; [2] make sure ZFlag is OFF (we arrived with a jr z and add hl,bc does not impact it)
   ret                           ;; [3] return

decreaseSubpixel:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,d                     ;; [1] a = subpixel
   or    a                       ;; [1] check a == 0
   jr    z,dsp_changeXOffset     ;; [2/3] Subpixel == 0, move to previous octet
   dec   d                       ;; [1] decrease subpixel
   or    a                       ;; [1] To reset Z Flag as d == 0
   ret                           ;; [3] return
dsp_changeXOffset:
   ld    a,e                     ;; [1] a = X octet in line
   or    a                       ;; [1] Check a == 0
   ret   z                       ;; [2/4] Z flag is set : cannot move before sub pixel 0 of X-Offset 0
   inc   d                       ;; [1] d = last subpixel (1)
   dec   hl                      ;; [2] decrease screen adress
   dec   e                       ;; [1] decrease X Octet
   or    a                       ;; [1] to reset ZFlag if e = 0
   ret                           ;; [3] return

increaseSubpixel:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ld    a,d                     ;; [1] a = subpixel
   or    a                       ;; [1] Compare subpixel with 3
   jr    nz,isp_changeXOffset    ;; [2/3] subpixel == 1, move to next octet
   inc   d                       ;; [1] increase subpixel (ZFlag cannot be set)
   ret                           ;; [3] return
isp_changeXOffset:
   ld    a,e                     ;; [1] a = X Octet in line
   cp    #screenNbOctet          ;; [2] compare with end of line
   ret   z                       ;; [2/4] Z flag is set : cannot move after sub pixel 1 of last X-Offset
   dec   d                       ;; [1] d = left subpixel (0)
   inc   hl                      ;; [2] increase screen adress
   inc   e                       ;; [1] increase X (ZFlag cannot be set)
   ret                           ;; [3] return
