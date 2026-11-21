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
.module cpct_clipTriangle

.globl clip_xmin
.globl clip_ymin
.globl clip_xend
.globl clip_yend
.globl cpct_clipLine_intersect

.area _CODE

;; Clip three ordered signed (x,y) vertices against the shared inclusive rectangle.
;; HL = input points, DE = output point buffer.
;; Input coordinates must satisfy cpct_clipLine's [-16384,16383] range.
;; Output is an ordered, non-closed list of at most seven signed (x,y) pairs.
_cpct_clipTriangle::
    push ix
    push iy

    ld (ct_input),hl
    ld (ct_output),de

    ;; An empty rectangle has no clipped polygon.
    ld hl,(clip_xmin)
    ld de,(clip_xend)
    or a
    sbc hl,de
    jp p,ct_return_empty
    ld hl,(clip_ymin)
    ld de,(clip_yend)
    or a
    sbc hl,de
    jp p,ct_return_empty

    ;; Copy the input first so the output may alias it.
    ld hl,(ct_input)
    ld de,#ct_bufferA
    ld b,#12
ct_copy_input:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz ct_copy_input

    ld hl,#ct_bufferA
    ld (ct_src),hl
    ld hl,#ct_bufferB
    ld (ct_dst),hl
    ld a,#3
    ld (ct_srcCount),a
    xor a
    ld (ct_pass),a
    ld (ct_overflow),a

ct_pass_loop:
    xor a
    ld (ct_dstCount),a
    ld a,(ct_srcCount)
    or a
    jp z,ct_return_empty

    dec a
    call ct_getSrcPoint
    call ct_loadPrevPoint
    ld hl,(ct_prevX)
    ld (ct_testX),hl
    ld hl,(ct_prevY)
    ld (ct_testY),hl
    call ct_isInside
    ld (ct_prevInside),a

    xor a
    ld (ct_index),a

ct_vertex_loop:
    ld a,(ct_index)
    ld b,a
    ld a,(ct_srcCount)
    cp b
    jp z,ct_pass_done

    ld a,b
    call ct_getSrcPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_currX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_currY),de

    ld hl,(ct_currX)
    ld (ct_testX),hl
    ld hl,(ct_currY)
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
    ld hl,(ct_currX)
    ld (ct_prevX),hl
    ld hl,(ct_currY)
    ld (ct_prevY),hl
    ld a,(ct_currInside)
    ld (ct_prevInside),a
    ld a,(ct_index)
    inc a
    ld (ct_index),a
    jp ct_vertex_loop

ct_pass_done:
    call ct_removeClosingDuplicate
    ld a,(ct_overflow)
    or a
    jp nz,ct_return_empty

    ld a,(ct_dstCount)
    ld (ct_srcCount),a
    or a
    jp z,ct_return_empty

    ld hl,(ct_src)
    ld de,(ct_dst)
    ld (ct_src),de
    ld (ct_dst),hl

    ld a,(ct_pass)
    inc a
    ld (ct_pass),a
    cp #4
    jp nz,ct_pass_loop

    ;; Copy the final cyclic point list to the caller's output buffer.
    ld a,(ct_srcCount)
    add a,a
    add a,a
    ld b,a
    ld hl,(ct_src)
    ld de,(ct_output)
ct_copy_output:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz ct_copy_output
    ld a,(ct_srcCount)
    jp ct_return

ct_return_empty:
    xor a
ct_return:
    pop iy
    pop ix
    ret

;; A = point index; returns HL = source point address.
ct_getSrcPoint::
    ld l,a
    ld h,#0
    add hl,hl
    add hl,hl
    ld de,(ct_src)
    add hl,de
    ret

;; A = point index; returns HL = destination point address.
ct_getDstPoint::
    ld l,a
    ld h,#0
    add hl,hl
    add hl,hl
    ld de,(ct_dst)
    add hl,de
    ret

ct_loadPrevPoint::
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_prevX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_prevY),de
    ret

;; Returns A=1 when (ct_testX,ct_testY) is within the current inclusive edge.
ct_isInside::
    ld a,(ct_pass)
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
    ld hl,(ct_currX)
    ld (ct_appendX),hl
    ld hl,(ct_currY)
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
    ld (ct_lastX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_lastY),de
    ld hl,(ct_appendX)
    ld de,(ct_lastX)
    or a
    sbc hl,de
    jr nz,ct_appendCapacity
    ld hl,(ct_appendY)
    ld de,(ct_lastY)
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

    ld hl,(ct_dst)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_firstX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_firstY),de

    ld a,(ct_dstCount)
    dec a
    call ct_getDstPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_lastX),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ct_lastY),de
    ld hl,(ct_firstX)
    ld de,(ct_lastX)
    or a
    sbc hl,de
    ret nz
    ld hl,(ct_firstY)
    ld de,(ct_lastY)
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
    ld a,(ct_pass)
    or a
    jr z,ct_intersectLeft
    cp #1
    jr z,ct_intersectRight
    cp #2
    jr z,ct_intersectTop

ct_intersectBottom:
    ld hl,(ct_prevY)
    ld (ct_prevAxis),hl
    ld hl,(ct_currY)
    ld (ct_currAxis),hl
    ld hl,(clip_yend)
    dec hl
    ld (ct_boundary),hl
    ld hl,(ct_prevX)
    ld (ct_prevOther),hl
    ld hl,(ct_currX)
    ld (ct_currOther),hl
    xor a
    ld (ct_axisIsX),a
    jr ct_intersectionReady

ct_intersectLeft:
    ld hl,(ct_prevX)
    ld (ct_prevAxis),hl
    ld hl,(ct_currX)
    ld (ct_currAxis),hl
    ld hl,(clip_xmin)
    ld (ct_boundary),hl
    ld hl,(ct_prevY)
    ld (ct_prevOther),hl
    ld hl,(ct_currY)
    ld (ct_currOther),hl
    ld a,#1
    ld (ct_axisIsX),a
    jr ct_intersectionReady

ct_intersectRight:
    ld hl,(ct_prevX)
    ld (ct_prevAxis),hl
    ld hl,(ct_currX)
    ld (ct_currAxis),hl
    ld hl,(clip_xend)
    dec hl
    ld (ct_boundary),hl
    ld hl,(ct_prevY)
    ld (ct_prevOther),hl
    ld hl,(ct_currY)
    ld (ct_currOther),hl
    ld a,#1
    ld (ct_axisIsX),a
    jr ct_intersectionReady

ct_intersectTop:
    ld hl,(ct_prevY)
    ld (ct_prevAxis),hl
    ld hl,(ct_currY)
    ld (ct_currAxis),hl
    ld hl,(clip_ymin)
    ld (ct_boundary),hl
    ld hl,(ct_prevX)
    ld (ct_prevOther),hl
    ld hl,(ct_currX)
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
ct_input:             .ds 2
ct_output:            .ds 2
ct_src:               .ds 2
ct_dst:               .ds 2
ct_srcCount:          .ds 1
ct_dstCount:          .ds 1
ct_pass:              .ds 1
ct_index:             .ds 1
ct_prevInside:        .ds 1
ct_currInside:        .ds 1
ct_overflow:          .ds 1
ct_prevX:             .ds 2
ct_prevY:             .ds 2
ct_currX:             .ds 2
ct_currY:             .ds 2
ct_testX:             .ds 2
ct_testY:             .ds 2
ct_appendX:           .ds 2
ct_appendY:           .ds 2
ct_lastX:             .ds 2
ct_lastY:             .ds 2
ct_firstX:            .ds 2
ct_firstY:            .ds 2
ct_prevAxis:          .ds 2
ct_currAxis:          .ds 2
ct_boundary:          .ds 2
ct_prevOther:         .ds 2
ct_currOther:         .ds 2
ct_tD:                .ds 2
ct_tE:                .ds 2
ct_axisIsX:           .ds 1
ct_intersectionOther: .ds 2
ct_bufferA:           .ds 32
ct_bufferB:           .ds 32
