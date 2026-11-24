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
.module cpct_geometry

; Common geometric variables
.globl geomCurrentPtr
.globl geomNextPtr
.globl geomOutputPtr
.globl geomIndex
.globl geomStep
.globl geomCurrentX
.globl geomCurrentY
.globl geomX0
.globl geomY0
.globl geomX1                 ; Used as Last point X
.globl geomY1                 ; Used as Last point Y
.globl geomNbInput
.globl geomPreviousX
.globl geomPreviousY

; Clipping variables
.globl clip_xmin
.globl clip_ymin
.globl clip_xend
.globl clip_yend
; Clipping methods
.globl cpct_clipLine_intersect

.area _CODE

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_clipTriangle
;;
;;    Clips a triangle defined by an array of 3 points (2 x i16 information) against the clipping rectangle
;;    set by <cpct_setClipRect>. The resulting polygon is returned in target array (7 points max for a triangle)
;;    that you must allocate.
;;    Mode independent: use it before any cpct_draw*Polygon* function.
;;
;; C Definition:
;;    u8 cpct_clipTriangle(i16* ptArray, i16 *outputPolygon);
;;
;; Input Parameters:
;;    (2B HL)    ptArray       - Pointer to triangle definition: 3 points X,Y (-16384...16383)
;;    (2B DE)    outputPolygon - Pointer to polygon (7 points)
;;
;; Return Value:
;;    (1B A) Returns number of resulting vertices in polygon (0..7). A result with fewer than 3 vertices
;;           is degenerate (no area to fill).
;;
;; Parameter Restrictions:
;;
;;    * Coordinates must be in the range [-16384, 16383], so that differences
;;      between coordinates fit in 16 bits.
;;
;; Details:
;;    Consider triangle as a polygon and compute intersection of each edge
;;    with clipping rectangle. Split or merge point with those intersections into 
;;    an output polygon.
;;    Like cpct_clipLine the intersection is computed exactly and
;;    rounded to the nearest integer, with only 16-bit arithmetic.
;;
;; Usage example:
;; (start code)
;;    i16 triangle [6] = {-40, 20, 400, 150, 30, 400};
;;    i16 polygon  [14];
;;    
;;    u8 nbPoints = cpct_clipTriangle(triangle, polygon);
;;    if ( nbPoints > 2)
;;       cpct_drawPolygonM1(CPCT_VMEM_START, polygon, nbPoints, 1);
;; (end code)
;;
;; Known limitations:
;;
;;  * This function will not work from ROM, as the clipping rectangle is
;;    stored with the code.
;;
;; Destroyed Register values:
;;    AF, BC, DE, HL
;;
;; Required memory:
;;    XXX bytes (<cpct_setClipRect> + <cpct_clipLine> + clipping rectangle
;;    and working data)
;;
;; Time Measures (Measured from C, including call overhead):
;; (start code)
;;    Case (default clipping rectangle)               | microSecs (us)
;;   --------------------------------------------------------------------
;;    Fully inside        (10,10)-(30,50)-(20,90)     | ~xxx
;;    Fully outside       (-1,-2)-(-9,-4)-(-5,-8)     | ~xxx
;;    7 points output     (-50,-20) - (400,250)       | ~xxx
;;   --------------------------------------------------------------------
;; (end code)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
_cpct_clipTriangle::
cpct_clipTriangle_asm::
    ld (geomOutputPtr),de

    ;; No test on empty rectangle.

    ;; Copy the input first so the output may alias it.
    ld de,#ct_bufferA
    ld b,#12
ct_copy_input:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz ct_copy_input

    ld hl,#ct_bufferA
    ld (geomCurrentPtr),hl
    ld hl,#ct_bufferB
    ld (geomNextPtr),hl
    ld a,#3
    ld (geomNbInput),a
    xor a
    ld (geomStep),a
    ld (ct_overflow),a

ct_pass_loop:
    xor a
    ld (ct_dstCount),a
    ld a,(geomNbInput)
    or a
    jp z,ct_return_empty

    dec a
    call ct_getSrcPoint
    call ct_loadPrevPoint
    ld hl,(geomPreviousX)
    ld (ct_testX),hl
    ld hl,(geomPreviousY)
    ld (ct_testY),hl
    call ct_isInside
    ld (ct_prevInside),a

    xor a
    ld (geomIndex),a

ct_vertex_loop:
    ld a,(geomIndex)
    ld b,a
    ld a,(geomNbInput)
    cp b
    jp z,ct_pass_done

    ld a,b
    call ct_getSrcPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomCurrentX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomCurrentY),de

    ld hl,(geomCurrentX)
    ld (ct_testX),hl
    ld hl,(geomCurrentY)
    ld (ct_testY),hl
    call ct_isInside
    ld (ct_currInside),a

    ld a,(ct_prevInside)
    ld b,a
    ld a,(ct_currInside)
    cp b
    jr z,ct_sameSide

    call ct_intersection
    call ct_appendPoint
    ld a,(ct_currInside)
    or a
    jr z,ct_updatePrev
    call ct_setAppendCurrent
    call ct_appendPoint
    jr ct_updatePrev

ct_sameSide:
    ld a,(ct_currInside)
    or a
    jr z,ct_updatePrev
    call ct_setAppendCurrent
    call ct_appendPoint

ct_updatePrev:
    ld hl,(geomCurrentX)
    ld (geomPreviousX),hl
    ld hl,(geomCurrentY)
    ld (geomPreviousY),hl
    ld a,(ct_currInside)
    ld (ct_prevInside),a
    ld a,(geomIndex)
    inc a
    ld (geomIndex),a
    jp ct_vertex_loop

ct_pass_done:
    call ct_removeClosingDuplicate
    ld a,(ct_overflow)
    or a
    jp nz,ct_return_empty

    ld a,(ct_dstCount)
    ld (geomNbInput),a
    or a
    jp z,ct_return_empty

    ld hl,(geomCurrentPtr)
    ld de,(geomNextPtr)
    ld (geomCurrentPtr),de
    ld (geomNextPtr),hl

    ld a,(geomStep)
    inc a
    ld (geomStep),a
    cp #4
    jp nz,ct_pass_loop

    ;; Copy the final cyclic point list to the caller's output buffer.
    ld a,(geomNbInput)
    add a,a
    add a,a
    ld b,a
    ld hl,(geomCurrentPtr)
    ld de,(geomOutputPtr)
ct_copy_output:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz ct_copy_output
    ld a,(geomNbInput)
    jp ct_return

ct_return_empty:
    xor a
ct_return:
    ret

;; A = point index; returns HL = source point address.
ct_getSrcPoint::
    ld l,a
    ld h,#0
    add hl,hl
    add hl,hl
    ld de,(geomCurrentPtr)
    add hl,de
    ret

;; A = point index; returns HL = destination point address.
ct_getDstPoint::
    ld l,a
    ld h,#0
    add hl,hl
    add hl,hl
    ld de,(geomNextPtr)
    add hl,de
    ret

ct_loadPrevPoint::
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomPreviousX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomPreviousY),de
    ret

;; Returns A=1 when (ct_testX,ct_testY) is within the current inclusive edge.
ct_isInside::
    ld a,(geomStep)
    or a
    jr z,ct_insideLeft
    cp #1
    jr z,ct_insideRight
    cp #2
    jr z,ct_insideTop

ct_insideBottom:
    ld hl,(ct_testY)
    ld de,(clip_yend)
    or a
    sbc hl,de
    jp m,ct_insideYes
    xor a
    ret

ct_insideLeft:
    ld hl,(ct_testX)
    ld de,(clip_xmin)
    or a
    sbc hl,de
    jp p,ct_insideYes
    xor a
    ret

ct_insideRight:
    ld hl,(ct_testX)
    ld de,(clip_xend)
    or a
    sbc hl,de
    jp m,ct_insideYes
    xor a
    ret

ct_insideTop:
    ld hl,(ct_testY)
    ld de,(clip_ymin)
    or a
    sbc hl,de
    jp p,ct_insideYes
    xor a
    ret

ct_insideYes:
    ld a,#1
    ret

ct_setAppendCurrent::
    ld hl,(geomCurrentX)
    ld (ct_appendX),hl
    ld hl,(geomCurrentY)
    ld (ct_appendY),hl
    ret

;; Append a point, suppressing consecutive duplicates.
ct_appendPoint::
    ld a,(ct_dstCount)
    or a
    jr z,ct_appendCapacity
    dec a
    call ct_getDstPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomX1),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomY1),de
    ld hl,(ct_appendX)
    ld de,(geomX1)
    or a
    sbc hl,de
    jr nz,ct_appendCapacity
    ld hl,(ct_appendY)
    ld de,(geomY1)
    or a
    sbc hl,de
    ret z

ct_appendCapacity:
    ld a,(ct_dstCount)
    cp #8
    jr nc,ct_appendOverflow
    call ct_getDstPoint
    ld de,(ct_appendX)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld de,(ct_appendY)
    ld (hl),e
    inc hl
    ld (hl),d
    ld a,(ct_dstCount)
    inc a
    ld (ct_dstCount),a
    ret

ct_appendOverflow:
    ld a,#1
    ld (ct_overflow),a
    ret

ct_removeClosingDuplicate::
    ld a,(ct_dstCount)
    cp #2
    ret c

    ld hl,(geomNextPtr)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomX0),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomY0),de

    ld a,(ct_dstCount)
    dec a
    call ct_getDstPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomX1),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomY1),de
    ld hl,(geomX0)
    ld de,(geomX1)
    or a
    sbc hl,de
    ret nz
    ld hl,(geomY0)
    ld de,(geomY1)
    or a
    sbc hl,de
    ret nz
    ld a,(ct_dstCount)
    dec a
    ld (ct_dstCount),a
    ret

;; Compute the crossing point for the active half-plane.
;; Uses cpct_clipLine's shared exact rounded multiply/divide helper.
ct_intersection::
    ld a,(geomStep)
    or a
    jr z,ct_intersectLeft
    cp #1
    jr z,ct_intersectRight
    cp #2
    jr z,ct_intersectTop

ct_intersectBottom:
    ld hl,(geomPreviousY)
    ld (ct_prevAxis),hl
    ld hl,(geomCurrentY)
    ld (ct_currAxis),hl
    ld hl,(clip_yend)
    dec hl
    ld (ct_boundary),hl
    ld hl,(geomPreviousX)
    ld (ct_prevOther),hl
    ld hl,(geomCurrentX)
    ld (ct_currOther),hl
    xor a
    ld (ct_axisIsX),a
    jr ct_intersectionReady

ct_intersectLeft:
    ld hl,(geomPreviousX)
    ld (ct_prevAxis),hl
    ld hl,(geomCurrentX)
    ld (ct_currAxis),hl
    ld hl,(clip_xmin)
    ld (ct_boundary),hl
    ld hl,(geomPreviousY)
    ld (ct_prevOther),hl
    ld hl,(geomCurrentY)
    ld (ct_currOther),hl
    ld a,#1
    ld (ct_axisIsX),a
    jr ct_intersectionReady

ct_intersectRight:
    ld hl,(geomPreviousX)
    ld (ct_prevAxis),hl
    ld hl,(geomCurrentX)
    ld (ct_currAxis),hl
    ld hl,(clip_xend)
    dec hl
    ld (ct_boundary),hl
    ld hl,(geomPreviousY)
    ld (ct_prevOther),hl
    ld hl,(geomCurrentY)
    ld (ct_currOther),hl
    ld a,#1
    ld (ct_axisIsX),a
    jr ct_intersectionReady

ct_intersectTop:
    ld hl,(geomPreviousY)
    ld (ct_prevAxis),hl
    ld hl,(geomCurrentY)
    ld (ct_currAxis),hl
    ld hl,(clip_ymin)
    ld (ct_boundary),hl
    ld hl,(geomPreviousX)
    ld (ct_prevOther),hl
    ld hl,(geomCurrentX)
    ld (ct_currOther),hl
    xor a
    ld (ct_axisIsX),a

ct_intersectionReady:
    ld hl,(ct_currAxis)
    ld de,(ct_prevAxis)
    or a
    sbc hl,de
    call ct_absHL
    ld (ct_tD),hl

    ld hl,(ct_boundary)
    ld de,(ct_prevAxis)
    or a
    sbc hl,de
    call ct_absHL
    ld (ct_tE),hl

    ld hl,(ct_currOther)
    ld de,(ct_prevOther)
    or a
    sbc hl,de
    ld de,(ct_tE)
    ld bc,(ct_tD)
    call cpct_clipLine_intersect
    ld de,(ct_prevOther)
    add hl,de
    ld (ct_intersectionOther),hl

    ld a,(ct_axisIsX)
    or a
    jr z,ct_intersectionOnY
    ld hl,(ct_boundary)
    ld (ct_appendX),hl
    ld hl,(ct_intersectionOther)
    ld (ct_appendY),hl
    ret

ct_intersectionOnY:
    ld hl,(ct_intersectionOther)
    ld (ct_appendX),hl
    ld hl,(ct_boundary)
    ld (ct_appendY),hl
    ret

;; HL = signed value; returns its unsigned magnitude in HL.
ct_absHL::
    bit 7,h
    ret z
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret

.area _DATA
ct_dstCount:          .ds 1  ;; Number of points in the destination list
ct_prevInside:        .ds 1  ;; Inside status of the previous point
ct_currInside:        .ds 1  ;; Inside status of the current point
ct_overflow:          .ds 1  ;; Internal overflow status
ct_testX:             .ds 2  ;; X coordinate used for a test
ct_testY:             .ds 2  ;; Y coordinate used for a test
ct_appendX:           .ds 2  ;; X coordinate of a point to append
ct_appendY:           .ds 2  ;; Y coordinate of a point to append
ct_prevAxis:          .ds 2  ;; Previous coordinate on the clipping axis
ct_currAxis:          .ds 2  ;; Current coordinate on the clipping axis
ct_boundary:          .ds 2  ;; Current clipping boundary coordinate
ct_prevOther:         .ds 2  ;; Previous coordinate on the other axis
ct_currOther:         .ds 2  ;; Current coordinate on the other axis
ct_tD:                .ds 2  ;; Internal distance value
ct_tE:                .ds 2  ;; Internal distance value
ct_axisIsX:           .ds 1  ;; Axis selection status
ct_intersectionOther: .ds 2  ;; Intersection coordinate on the other axis
ct_bufferA:           .ds 32 ;; Point storage buffer - Used as source and destination alternatively
ct_bufferB:           .ds 32 ;; Point storage buffer - Used as source and destination alternatively
