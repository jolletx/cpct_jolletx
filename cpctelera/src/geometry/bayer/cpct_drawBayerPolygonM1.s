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
.globl bayer_screenY
.globl geomBottomY
.globl geomTopY
.globl geomCurrentY
.globl geomCurrentX
.globl geomDeltaX
.globl geomDeltaY
.globl geomInputPtr
.globl geomNbInput
.globl geomIndex
.globl geomEndX
.globl geomStartY
.globl geomEndY
.globl geomStep
.globl geomError
.globl geomThreshold

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
;;     geomTopY = first vertex Y
;;     geomBottomY = first vertex Y
;;     for each other vertex:
;;         if vertexY < geomTopY:
;;             geomTopY = vertexY
;;             topIndex = vertex index
;;         else if vertexY == geomTopY:
;;             update topMinX/topMaxX
;;         if vertexY > geomBottomY:
;;             geomBottomY = vertexY
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
;;         if geomCurrentY == geomBottomY:
;;             exit loop
;;     
;;         advance both active edges one row
;;         geomCurrentY++

_cpct_drawBayerPolygonM1::
    push ix
    push iy

    ld (geomInputPtr),hl
    ld a,e
    ld (geomNbInput),a
    cp #3
    jp c,polygon_exit

    call findVerticalBounds

    ld a,(geomTopY)
    ld (geomCurrentY),a
    ld l,a
    ld h,#0
    call cpct_compScreenLine

    ld hl,(topMinX)
    ld (spanX0),hl
    ld hl,(topMaxX)
    ld (spanX1),hl
    call drawSpan

    ld a,(geomTopY)
    ld b,a
    ld a,(geomBottomY)
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

    ld a,(geomTopY)
    inc a
    ld (geomCurrentY),a

row_loop:
    call updateForwardChain
    call updateBackwardChain

    ld hl,(edgeForward)
    ld (spanX0),hl
    ld hl,(edgeBackward)
    ld (spanX1),hl
    call drawSpan

    ld a,(geomCurrentY)
    ld b,a
    ld a,(geomBottomY)
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

    ld a,(geomCurrentY)
    inc a
    ld (geomCurrentY),a
    jp row_loop

polygon_exit:
    pop iy
    pop ix
    ret

;; Find the top and bottom rows and the horizontal extent of the top row.
findVerticalBounds:
    ld hl,(geomInputPtr)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (topMinX),de
    ld (topMaxX),de
    inc hl
    ld a,(hl)
    ld (geomTopY),a
    ld (geomBottomY),a
    xor a
    ld (topIndex),a
    ld a,#1
    ld (geomIndex),a

find_bounds_loop:
    ld a,(geomIndex)
    ld b,a
    ld a,(geomNbInput)
    cp b
    ret z

    ld a,b
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomCurrentX),de
    inc hl
    ld a,(hl)
    ld (scanY),a

    ld b,a
    ld a,(geomTopY)
    cp b
    jr c,find_bounds_check_bottom
    jr z,find_bounds_not_new_top
    ld a,b
    ld (geomTopY),a
    ld a,(geomIndex)
    ld (topIndex),a
    ld hl,(geomCurrentX)
    ld (topMinX),hl
    ld (topMaxX),hl
    jr find_bounds_check_bottom

find_bounds_not_new_top:
    jr nz,find_bounds_check_bottom

    ld hl,(topMinX)
    ld de,(geomCurrentX)
    call cpct_compareSigned16
    jr c,find_bounds_check_top_max
    jr z,find_bounds_check_top_max
    ld hl,(geomCurrentX)
    ld (topMinX),hl

find_bounds_check_top_max:
    ld hl,(topMaxX)
    ld de,(geomCurrentX)
    call cpct_compareSigned16
    jr nc,find_bounds_check_bottom
    ld hl,(geomCurrentX)
    ld (topMaxX),hl

find_bounds_check_bottom:
    ld a,(scanY)
    ld b,a
    ld a,(geomBottomY)
    cp b
    jr nc,find_bounds_next
    ld a,b
    ld (geomBottomY),a

find_bounds_next:
    ld a,(geomIndex)
    inc a
    ld (geomIndex),a
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
    ld a,(geomTopY)
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
    ld a,(geomTopY)
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
    ld a,(geomCurrentY)
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
    ld a,(geomCurrentY)
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
    ld a,(geomCurrentY)
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
    ld a,(geomCurrentY)
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
    ld (geomCurrentX),de
    inc hl
    ld a,(hl)
    ld (geomStartY),a

    ld a,(chainEnd)
    call getPoint
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomEndX),de
    inc hl
    ld a,(hl)
    ld (geomEndY),a

    ld hl,(geomEndX)
    ld de,(geomCurrentX)
    or a
    sbc hl,de
    ld a,h
    and #0x80
    jr z,setup_positive_x
    ld a,#0xFF
    ld (geomStep),a
    xor a
    sub l
    ld l,a
    ld a,#0
    sbc a,h
    ld h,a
    jr setup_store_dx
setup_positive_x:
    ld a,#1
    ld (geomStep),a
setup_store_dx:
    ld (geomDeltaX),hl

    ld a,(geomEndY)
    ld l,a
    ld h,#0
    ld a,(geomStartY)
    ld e,a
    ld d,#0
    or a
    sbc hl,de
    ld (geomDeltaY),hl

    ld hl,#0
    ld (geomError),hl
    ld hl,(edgeOut)
    ld de,(geomCurrentX)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld de,(geomDeltaX)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld de,(geomDeltaY)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,(geomStep)
    ld (hl),a
    inc hl
    ld de,(geomError)
    ld (hl),e
    inc hl
    ld (hl),d
    ld hl,(setupEndY)
    ld a,(geomEndY)
    ld (hl),a
    ret

;; A = point index; returns HL = pointer to its (x,y) words.
getPoint:
    ld l,a
    ld h,#0
    add hl,hl
    add hl,hl
    ld de,(geomInputPtr)
    add hl,de
    ret

;; A = index; returns the next/previous wrapped vertex index.
nextForwardIndex:
    inc a
    ld b,a
    ld a,(geomNbInput)
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
    ld a,(geomNbInput)
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
    ld (geomDeltaX),bc
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomDeltaY),de
    inc hl
    inc hl
    ld a,(hl)
    ld (geomError),a
    inc hl
    ld a,(hl)
    ld (geomError+1),a

advance_edge_loop:
    ld hl,(geomDeltaY)
    ld de,(geomError)
    or a
    sbc hl,de
    ld (geomThreshold),hl
    ld hl,(geomDeltaX)
    ld de,(geomThreshold)
    or a
    sbc hl,de
    jr c,advance_error_only

    ld (geomDeltaX),hl
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
    ld (geomError),hl
    jp advance_edge_loop

advance_error_only:
    ld hl,(geomError)
    ld de,(geomDeltaX)
    add hl,de
    ld (geomError),hl
    ld hl,(edgeOut)
    ld de,#7
    add hl,de
    ld de,(geomError)
    ld (hl),e
    inc hl
    ld (hl),d
    ret

drawSpan:
    ld hl,(spanX0)
    ld de,(spanX1)
    ld a,(geomCurrentY)
    ld bc,(bayer_screenY)
    call cpct_bayerDrawHLineM1_worker_asm
    ld a,(geomCurrentY)
    call cpct_incScreenLine
    ret

.area _DATA
scanY:            .ds 1  ;; Y coordinate of the vertex being scanned
topIndex:         .ds 1  ;; Index of the topmost vertex
topMinX:          .ds 2  ;; Minimum X among vertices on the top scanline
topMaxX:          .ds 2  ;; Maximum X among vertices on the top scanline
spanX0:           .ds 2  ;; Left X endpoint of the span being drawn
spanX1:           .ds 2  ;; Right X endpoint of the span being drawn
forwardVertex:    .ds 1  ;; Current vertex index on the forward chain
backwardVertex:   .ds 1  ;; Current vertex index on the backward chain
candidateIndex:   .ds 1  ;; Candidate vertex index while advancing a chain
chainStart:       .ds 1  ;; First vertex index to consider on a chain
chainEnd:         .ds 1  ;; Last vertex index to consider on a chain
forwardActive:    .ds 1  ;; Nonzero while the forward edge is active
backwardActive:   .ds 1  ;; Nonzero while the backward edge is active
forwardEndY:      .ds 1  ;; End scanline of the forward edge
backwardEndY:     .ds 1  ;; End scanline of the backward edge
setupState:       .ds 2  ;; Pointer to the edge record currently being set up
setupEndY:        .ds 2  ;; End Y coordinate for the edge being set up
edgeForward:      .ds 9  ;; Forward edge state
edgeBackward:     .ds 9  ;; Backward edge state
edgeOut:          .ds 2  ;; Pointer to the edge record being written
