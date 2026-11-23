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

.globl cpct_bayerDrawHLineM1_worker_asm
.globl cpct_compareSigned16
.globl cpct_compScreenLine
.globl cpct_incScreenLine
.globl b_screenY

.area _CODE

;; Draw an ordered convex list of on-screen (u16 x, u16 y) points.
;; HL = point list, E = byte-sized point count.

;; Algorithm
;;     Purpose is to follow the polygon definition but display lines from 
;;     top scan line to bottom one.
;;     Generate a forward chain (input points order) and backward chain (reverse order) 
;;     from topvertex to bottom. 
;;     So first thing first, finds index of Top/Bottom vertices with their Y value
;;
;;     topY = first vertex Y
;;     bottomY = first vertex Y
;;     for each other vertex:
;;         if vertexY < topY:
;;             topY = vertexY
;;             topIndex = vertex index
;;         else if vertexY == topY:
;;             update topMinX/topMaxX
;;         if vertexY > bottomY:
;;             bottomY = vertexY
;; 
;;     draw the top row from topMinX to topMaxX
;;     advance to the next row
;;     do:
;;         update forward chain
;;         update backward chain
;;     
;;         spanX0 = forward edge X
;;         spanX1 = backward edge X
;;         draw horizontal span
;;     
;;         if rowY == bottomY:
;;             exit loop
;;     
;;         advance both active edges one row
;;         rowY++

_cpct_drawBayerPolygonM1::
    push ix
    push iy

    ld (pointsBase),hl
    ld a,e
    ld (pointCount),a
    cp #3
    jp c,polygon_exit

    call findVerticalBounds

    ld a,(topY)
    ld (rowY),a
    ld l,a
    ld h,#0
    call cpct_compScreenLine

    ld hl,(topMinX)
    ld (spanX0),hl
    ld hl,(topMaxX)
    ld (spanX1),hl
    call drawSpan

    ld a,(topY)
    ld b,a
    ld a,(bottomY)
    cp b
    jp z,polygon_exit

    call setupForwardChain
    call setupBackwardChain

    ld hl,#edgeForward
    ld a,(forwardActive)
    or a
    call nz,polygonAdvanceEdge
    ld hl,#edgeBackward
    ld a,(backwardActive)
    or a
    call nz,polygonAdvanceEdge

    ld a,(topY)
    inc a
    ld (rowY),a

row_loop:
    call updateForwardChain
    call updateBackwardChain

    ld hl,(edgeForward)
    ld (spanX0),hl
    ld hl,(edgeBackward)
    ld (spanX1),hl
    call drawSpan

    ld a,(rowY)
    ld b,a
    ld a,(bottomY)
    cp b
    jp z,polygon_exit

    ld hl,#edgeForward
    ld a,(forwardActive)
    or a
    call nz,polygonAdvanceEdge
    ld hl,#edgeBackward
    ld a,(backwardActive)
    or a
    call nz,polygonAdvanceEdge

    ld a,(rowY)
    inc a
    ld (rowY),a
    jp row_loop

polygon_exit:
    pop iy
    pop ix
    ret

;; Find the top and bottom rows and the horizontal extent of the top row.
findVerticalBounds:
    ld hl,(pointsBase)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (topMinX),de
    ld (topMaxX),de
    inc hl
    ld a,(hl)
    ld (topY),a
    ld (bottomY),a
    xor a
    ld (topIndex),a
    ld a,#1
    ld (scanIndex),a

find_bounds_loop:
    ld a,(scanIndex)
    ld b,a
    ld a,(pointCount)
    cp b
    ret z

    ld a,b
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (workX),de
    inc hl
    ld a,(hl)
    ld (scanY),a

    ld b,a
    ld a,(topY)
    cp b
    jr c,find_bounds_check_bottom
    jr z,find_bounds_not_new_top
    ld a,b
    ld (topY),a
    ld a,(scanIndex)
    ld (topIndex),a
    ld hl,(workX)
    ld (topMinX),hl
    ld (topMaxX),hl
    jr find_bounds_check_bottom

find_bounds_not_new_top:
    jr nz,find_bounds_check_bottom

    ld hl,(topMinX)
    ld de,(workX)
    call cpct_compareSigned16
    jr c,find_bounds_check_top_max
    jr z,find_bounds_check_top_max
    ld hl,(workX)
    ld (topMinX),hl

find_bounds_check_top_max:
    ld hl,(topMaxX)
    ld de,(workX)
    call cpct_compareSigned16
    jr nc,find_bounds_check_bottom
    ld hl,(workX)
    ld (topMaxX),hl

find_bounds_check_bottom:
    ld a,(scanY)
    ld b,a
    ld a,(bottomY)
    cp b
    jr nc,find_bounds_next
    ld a,b
    ld (bottomY),a

find_bounds_next:
    ld a,(scanIndex)
    inc a
    ld (scanIndex),a
    jp find_bounds_loop

;; Initialize each contour chain by skipping the horizontal top edge.
setupForwardChain:
    ld a,(topIndex)
    ld (forwardVertex),a
setup_forward_seek:
    ld a,(forwardVertex)
    call nextForwardIndex
    ld (candidateIndex),a
    call getPoint
    inc hl
    inc hl
    ld a,(hl)
    ld b,a
    ld a,(topY)
    cp b
    jr z,setup_forward_skip

    ld a,(forwardVertex)
    ld (chainStart),a
    ld a,(candidateIndex)
    ld (chainEnd),a
    ld (forwardVertex),a
    ld hl,#edgeForward
    ld (setupState),hl
    ld hl,#forwardEndY
    ld (setupEndY),hl
    call polygonSetupEdge
    ld a,#1
    ld (forwardActive),a
    ret

setup_forward_skip:
    ld a,(candidateIndex)
    ld (forwardVertex),a
    jr setup_forward_seek

setupBackwardChain:
    ld a,(topIndex)
    ld (backwardVertex),a
setup_backward_seek:
    ld a,(backwardVertex)
    call nextBackwardIndex
    ld (candidateIndex),a
    call getPoint
    inc hl
    inc hl
    ld a,(hl)
    ld b,a
    ld a,(topY)
    cp b
    jr z,setup_backward_skip

    ld a,(backwardVertex)
    ld (chainStart),a
    ld a,(candidateIndex)
    ld (chainEnd),a
    ld (backwardVertex),a
    ld hl,#edgeBackward
    ld (setupState),hl
    ld hl,#backwardEndY
    ld (setupEndY),hl
    call polygonSetupEdge
    ld a,#1
    ld (backwardActive),a
    ret

setup_backward_skip:
    ld a,(candidateIndex)
    ld (backwardVertex),a
    jr setup_backward_seek

;; Switch to the next non-horizontal edge when this chain reaches a vertex.
updateForwardChain:
    ld a,(forwardActive)
    or a
    ret z
    ld a,(forwardEndY)
    ld b,a
    ld a,(rowY)
    cp b
    ret nz

update_forward_seek:
    ld a,(forwardVertex)
    call nextForwardIndex
    ld (candidateIndex),a
    call getPoint
    inc hl
    inc hl
    ld a,(hl)
    ld b,a
    ld a,(rowY)
    cp b
    jr z,update_forward_horizontal
    jr c,update_forward_next_edge

    xor a
    ld (forwardActive),a
    ret

update_forward_horizontal:
    ld a,(candidateIndex)
    ld (forwardVertex),a
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (edgeForward),de
    jr update_forward_seek

update_forward_next_edge:
    ld a,(forwardVertex)
    ld (chainStart),a
    ld a,(candidateIndex)
    ld (chainEnd),a
    ld (forwardVertex),a
    ld hl,#edgeForward
    ld (setupState),hl
    ld hl,#forwardEndY
    ld (setupEndY),hl
    jp polygonSetupEdge

updateBackwardChain:
    ld a,(backwardActive)
    or a
    ret z
    ld a,(backwardEndY)
    ld b,a
    ld a,(rowY)
    cp b
    ret nz

update_backward_seek:
    ld a,(backwardVertex)
    call nextBackwardIndex
    ld (candidateIndex),a
    call getPoint
    inc hl
    inc hl
    ld a,(hl)
    ld b,a
    ld a,(rowY)
    cp b
    jr z,update_backward_horizontal
    jr c,update_backward_next_edge

    xor a
    ld (backwardActive),a
    ret

update_backward_horizontal:
    ld a,(candidateIndex)
    ld (backwardVertex),a
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (edgeBackward),de
    jr update_backward_seek

update_backward_next_edge:
    ld a,(backwardVertex)
    ld (chainStart),a
    ld a,(candidateIndex)
    ld (chainEnd),a
    ld (backwardVertex),a
    ld hl,#edgeBackward
    ld (setupState),hl
    ld hl,#backwardEndY
    ld (setupEndY),hl
    jp polygonSetupEdge

;; Set up a Bresenham-style X edge from chainStart to chainEnd.
polygonSetupEdge:
    ld hl,(setupState)
    ld (edgeOut),hl

    ld a,(chainStart)
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (workX),de
    inc hl
    ld a,(hl)
    ld (workStartY),a

    ld a,(chainEnd)
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (workEndX),de
    inc hl
    ld a,(hl)
    ld (workEndY),a

    ld hl,(workEndX)
    ld de,(workX)
    or a
    sbc hl,de
    ld a,h
    and #0x80
    jr z,setup_positive_x
    ld a,#0xFF
    ld (workStep),a
    xor a
    sub l
    ld l,a
    ld a,#0
    sbc a,h
    ld h,a
    jr setup_store_dx
setup_positive_x:
    ld a,#1
    ld (workStep),a
setup_store_dx:
    ld (workDX),hl

    ld a,(workEndY)
    ld l,a
    ld h,#0
    ld a,(workStartY)
    ld e,a
    ld d,#0
    or a
    sbc hl,de
    ld (workDY),hl

    ld hl,#0
    ld (workError),hl
    ld hl,(edgeOut)
    ld de,(workX)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld de,(workDX)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld de,(workDY)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,(workStep)
    ld (hl),a
    inc hl
    ld de,(workError)
    ld (hl),e
    inc hl
    ld (hl),d
    ld hl,(setupEndY)
    ld a,(workEndY)
    ld (hl),a
    ret

;; A = point index; returns HL = pointer to its (x,y) words.
getPoint:
    ld l,a
    ld h,#0
    add hl,hl
    add hl,hl
    ld de,(pointsBase)
    add hl,de
    ret

;; A = index; returns the next/previous wrapped vertex index.
nextForwardIndex:
    inc a
    ld b,a
    ld a,(pointCount)
    cp b
    ld a,b
    ret nz
    xor a
    ret

nextBackwardIndex:
    or a
    jr z,next_backward_wrap
    dec a
    ret
next_backward_wrap:
    ld a,(pointCount)
    dec a
    ret

;; Advance the current edge by one scanline.
polygonAdvanceEdge:
    ld (edgeOut),hl
    inc hl
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld (workDX),bc
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (workDY),de
    inc hl
    inc hl
    ld a,(hl)
    ld (workError),a
    inc hl
    ld a,(hl)
    ld (workError+1),a

advance_edge_loop:
    ld hl,(workDY)
    ld de,(workError)
    or a
    sbc hl,de
    ld (workThreshold),hl
    ld hl,(workDX)
    ld de,(workThreshold)
    or a
    sbc hl,de
    jr c,advance_error_only

    ld (workDX),hl
    ld hl,(edgeOut)
    ld a,(hl)
    ld e,a
    inc hl
    ld a,(hl)
    ld d,a
    ;; The signed X-step field is at offset 6 in the edge state.
    inc hl
    inc hl
    inc hl
    inc hl
    inc hl
    ld a,(hl)
    cp #1
    jr z,advance_x_right
    dec de
    jr advance_x_store
advance_x_right:
    inc de
advance_x_store:
    ld hl,(edgeOut)
    ld (hl),e
    inc hl
    ld (hl),d
    ld hl,#0
    ld (workError),hl
    jp advance_edge_loop

advance_error_only:
    ld hl,(workError)
    ld de,(workDX)
    add hl,de
    ld (workError),hl
    ld hl,(edgeOut)
    ld de,#7
    add hl,de
    ld de,(workError)
    ld (hl),e
    inc hl
    ld (hl),d
    ret

drawSpan:
    ld hl,(spanX0)
    ld de,(spanX1)
    ld a,(rowY)
    ld bc,(b_screenY)
    call cpct_bayerDrawHLineM1_worker_asm
    ld a,(rowY)
    call cpct_incScreenLine
    ret

.area _DATA
pointsBase:       .ds 2
pointCount:       .ds 1
scanIndex:        .ds 1
scanY:            .ds 1
topIndex:         .ds 1
topY:             .ds 1
bottomY:          .ds 1
topMinX:          .ds 2
topMaxX:          .ds 2
rowY:             .ds 1
spanX0:           .ds 2
spanX1:           .ds 2
forwardVertex:    .ds 1
backwardVertex:   .ds 1
candidateIndex:   .ds 1
chainStart:       .ds 1
chainEnd:         .ds 1
forwardActive:    .ds 1
backwardActive:   .ds 1
forwardEndY:      .ds 1
backwardEndY:     .ds 1
setupState:       .ds 2
setupEndY:        .ds 2
edgeForward:      .ds 9
edgeBackward:     .ds 9
edgeOut:          .ds 2
workX:            .ds 2
workEndX:         .ds 2
workStartY:       .ds 1
workEndY:         .ds 1
workDX:           .ds 2
workDY:           .ds 2
workStep:         .ds 1
workError:        .ds 2
workThreshold:    .ds 2
