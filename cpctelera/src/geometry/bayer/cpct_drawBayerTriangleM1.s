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
.module cpct_drawBayerTriangleM1    ;; Name this assembly module.

; .globl      _cpct_drawBayerBoxM1       ;; Link the C-callable Bayer box routine.
.globl      cpct_bayerDrawHLineM1_asm
.globl      bayer_startScreen
.globl      cpct_getScreenPtr_asm
.globl      cpct_compareSigned16
.globl      cpct_compScreenLine
.globl      cpct_incScreenLine
.globl      cpct_clipX
.globl      b_screenY

;; Compare and swap two vertices using their signed Y coordinates.
.macro SWAP_VERTEX idx1, idx2, ?lbl    ;; Swap matching bytes in two vertex fields.
PAIR1=idx1*4
PAIR2=idx2*4
    ld hl,(#tmpPt + PAIR1 + 2)           ;; HL = Y[idx1] 
    ld de,(#tmpPt + PAIR2 + 2)           ;; DE = Y[idx2]
    call cpct_compareSigned16            ;; Compare HL with DE
    jr c,lbl                             ;; Keep their order when Y[IDX1] is smaller.
    jr z,lbl                             ;; Keep their order when Y are equal.
    ld (#tmpPt + PAIR1 + 2),de           ;; Set Y[idx1] = de = Y[idx2]
    ld (#tmpPt + PAIR2 + 2),hl           ;; Set Y[idx2] = hl = Y[idx1]
    ld hl,(#tmpPt + PAIR1)               ;; HL = X[idx1]
    ld de,(#tmpPt + PAIR2)               ;; DE = X[idx2]
    ld (#tmpPt + PAIR1),de               ;; Set X[idx1] = de = X[idx2]
    ld (#tmpPt + PAIR2),hl               ;; Set X[idx2] = hl = X[idx1]
lbl:                                     ;; label for skip swap
.endm                                    ;; Finish the vertex-word swap macro.
                      ;; Finish the vertex-word swap macro.

;; Draw a span between the current long- and short-edge X positions.
.macro DRAW_EDGE_SPAN    ?lbl      ;; Draw a span from the two current edge X values.
    ld a,(rowY+1)                  ;; Check MSB RowY
    rlca                           ;; Put msb on Carry (check sign)
    jr c,#lbl
    ld hl,(edgeLong)               ;; Read the long edge's current X.
    ld (lineX0),hl                 ;; Use it as the first span endpoint.
    ld hl,(edgeShortActive)        ;; Point at the active short-edge state.
    ld e,(hl)                      ;; Read its current X low byte.
    inc hl                         ;; Point at the X high byte.
    ld d,(hl)                      ;; Read its current X high byte.
    ld (lineX1),de                 ;; Use it as the second span endpoint.
    call drawLine                  ;; Clip and draw this horizontal span if row visible.
lbl:
.endm                              ;; Finish the span-drawing macro.

.area _CODE                       ;; Place executable code in the code segment.

_cpct_drawBayerTriangleM1:: 
    push ix                        ;; Preserve IX value.
    push iy                        ;; Preserve IY value.

    ;; Store input points in internal array
    ld de,#tmpPt                   ;; HL contains point array, de = copy destination
    ld bc,#12                      ;; 3 points i16 (2 Bytes) x and y
    ldir                           ;; Copy the input vertices from HL to tmpPt.

    ;; Sort the points by signed Y coordinate ascending
    SWAP_VERTEX 0,1                ;; Exchange Pt0 and Pt1 if needed.
    SWAP_VERTEX 1,2                ;; Exchange Pt1 and Pt2 if needed.
    SWAP_VERTEX 0,1                ;; Exchange Pt0 and Pt1 if needed (move Pt2 to top in case of).

    ;; Return when the sorted triangle is entirely outside the screen.
    ld hl,(#tmpPt+2)               ;; HL = TopY
    ld de,#199                     ;; Set the screen's last visible row.
    call cpct_compareSigned16           ;; Compare top Y against the visible bottom.
    jp z,visible_top               ;; Continue when top Y equals row 199.
    jp c,visible_top               ;; Continue when top Y is above row 199.
    jp triangle_exit               ;; Skip a triangle whose top is below the screen.
visible_top:                       ;; The triangle's top is not below the screen.
    ld hl,(#tmpPt+10)              ;; HL = BottomY
    ld de,#0                       ;; Set the first visible row.
    call cpct_compareSigned16           ;; Compare bottom Y with zero.
    jp c,triangle_exit             ;; Skip a triangle entirely above the screen.

    ;; Clamp the bottom row once; all scanline loops use this bound. HL = BottomY
    ld de,#199                     ;; Set the screen's last visible row.
    call cpct_compareSigned16           ;; Compare bottom Y with row 199.
    jr c,bottom_clamped            ;; Keep bottom Y when it is below row 199.
    jr z,bottom_clamped            ;; Keep bottom Y when it equals row 199.
    ld hl,#199                     ;; Otherwise clamp to the last visible row.
bottom_clamped:                    ;; HL now contains the last row to rasterize.
    ld (visibleBottom),hl          ;; Save the clamped scanline limit.

    ;; Initialize all three edges together, then select the upper short edge.
    call setupEdges                ;; Set up top-to-bottom and both short edges.
    ld hl,#edgeShort1              ;; Select the top-to-middle edge initially.
    ld (edgeShortActive),hl        ;; Store the active short-edge state address.
    ld hl,(#tmpPt+2)               ;; Load the top scanline.
    ld (rowY),hl                   ;; Begin at the top vertex.
    call cpct_compScreenLine            ;; Compute and store current screen adress X=0 Y=TopY (or 0 if <0)
row_loop:                          ;; Process rows through the visible bottom.
    ld hl,(rowY)                   ;; Load the current scanline.
    ld de,(#tmpPt+6)                ;; Load the middle vertex's Y coordinate.
    call cpct_compareSigned16           ;; Check whether this is the middle row.
    jp nz,row_draw                 ;; Keep the current short edge on other rows.
    ld hl,#edgeShort2              ;; Select the middle-to-bottom edge.
    ld (edgeShortActive),hl        ;; Store the active short-edge state address.
row_draw:                          ;; Draw this row between the active edges.
    DRAW_EDGE_SPAN                 ;; Clip and render the current horizontal span.
    ld hl,(rowY)                   ;; Load the current scanline.
    ld de,(#tmpPt+10)               ;; Load the bottom vertex's Y coordinate.
    call cpct_compareSigned16           ;; Check whether this is the final triangle row.
    jp z,triangle_exit             ;; Do not advance beyond the bottom row.
    ld hl,#edgeLong                ;; Point at the top-to-bottom edge state.
    call advanceEdge               ;; Advance it by one scanline.
    ld hl,(edgeShortActive)        ;; Point at the active short-edge state.
    call advanceEdge               ;; Advance it by one scanline.
    ld hl,(rowY)                   ;; Select the next scanline.
    inc hl                         ;; Increment Y.
    ld (rowY),hl                   ;; Store the next scanline.
    ld de,(visibleBottom)          ;; Load the last visible scanline.
    call cpct_compareSigned16           ;; Check whether the next row is visible.
    jp c,row_loop                  ;; Continue when row Y is below the limit.
    jp z,row_loop                  ;; Include the last visible row.
    jp triangle_exit               ;; Stop after the visible bottom.

triangle_exit:                     ;; Shared function exit for all drawing paths.
    pop iy                         ;; Restore the caller's IY value.
    pop ix                         ;; Restore the caller's IX value.
    ret                            ;; Return to the C caller.


;; Initialize all three edge state blocks for the sorted vertices.
setupEdges::                       ;; Initialize the long edge and both short edges.
    ld ix,#tmpPt                   ;; Start the long edge at the top vertex.
    ld iy,#tmpPt+8                 ;; End the long edge at the bottom vertex.
    ld hl,#edgeLong                ;; Store the long edge in its state block.
    call setupEdge                 ;; Initialize top-to-bottom.
    ld ix,#tmpPt                   ;; Start the first short edge at the top.
    ld iy,#tmpPt+4                 ;; End it at the middle vertex.
    ld hl,#edgeShort1              ;; Store it in the first short-edge block.
    call setupEdge                 ;; Initialize top-to-middle.
    ld ix,#tmpPt+4                 ;; Start the second short edge at the middle.
    ld iy,#tmpPt+8                 ;; End it at the bottom vertex.
    ld hl,#edgeShort2              ;; Store it in the second short-edge block.
    call setupEdge                 ;; Initialize middle-to-bottom.
    ret                            ;; Return with all three edges initialized.

;; IX and IY point at vertices; HL points to the destination edge state.
setupEdge::                         ;; Initialize X, deltas, step, and error for an edge.
    ld (edgeOut),hl                 ;; Save the output edge address across calculations.
    ld e,0(ix)                      ;; Load the start vertex's X low byte.
    ld d,1(ix)                      ;; Load the start vertex's X high byte.
    ld l,0(iy)                      ;; Load the end vertex's X low byte.
    ld h,1(iy)                      ;; Load the end vertex's X high byte.
    or a                            ;; Clear carry before the 16-bit subtraction.
    sbc hl,de                       ;; Calculate signed DX = endX - startX.
    ld a,h                          ;; Inspect DX's sign bit.
    and #0x80                       ;; Keep only the sign bit.
    jr z,setup_positive_x           ;; Use a positive step when DX is nonnegative.
    ld a,#0xFF                      ;; Encode a negative X step as -1.
    ld (workStep),a                 ;; Save the negative step.
    xor a                           ;; Clear A and carry before negating DX.
    sub l                           ;; Negate the low byte of DX.
    ld l,a                          ;; Save the negated low byte.
    ld a,#0                         ;; Prepare zero for high-byte negation.
    sbc a,h                         ;; Negate the high byte, including borrow.
    ld h,a                          ;; Complete the 16-bit absolute DX.
    jr setup_store_dx               ;; Continue with the absolute horizontal delta.
setup_positive_x:                   ;; DX is zero or positive.
    ld a,#1                          ;; Encode a positive X step as +1.
    ld (workStep),a                 ;; Save the positive step.
setup_store_dx:                     ;; Store the absolute horizontal delta.
    ld (workDX),hl                  ;; Save |endX - startX|.

    ld e,2(ix)                      ;; Load the start vertex's Y low byte.
    ld d,3(ix)                      ;; Load the start vertex's Y high byte.
    ld l,2(iy)                      ;; Load the end vertex's Y low byte.
    ld h,3(iy)                      ;; Load the end vertex's Y high byte.
    or a                            ;; Clear carry before the 16-bit subtraction.
    sbc hl,de                       ;; Calculate DY = endY - startY.
    ld (workDY),hl                 ;; Save the vertical delta.
    ld l,0(ix)                      ;; Load the start vertex's X low byte.
    ld h,1(ix)                      ;; Load the start vertex's X high byte.
    ld (workX),hl                   ;; Set the edge's initial X coordinate.
    ld hl,#0                        ;; Initialize the error accumulator to zero.
    ld (workError),hl               ;; Save the initial error value.

    ld hl,(edgeOut)                 ;; Point HL at the edge-state destination.
    ld de,(workX)                   ;; Load the starting X coordinate.
    ld (hl),e                       ;; Store the X low byte at offset zero.
    inc hl                          ;; Advance to the X high-byte field.
    ld (hl),d                       ;; Store the X high byte at offset one.
    inc hl                          ;; Advance to the DX low-byte field.
    ld de,(workDX)                  ;; Load the absolute horizontal delta.
    ld (hl),e                       ;; Store DX's low byte.
    inc hl                          ;; Advance to the DX high-byte field.
    ld (hl),d                       ;; Store DX's high byte.
    inc hl                          ;; Advance to the DY low-byte field.
    ld de,(workDY)                  ;; Load the vertical delta.
    ld (hl),e                       ;; Store DY's low byte.
    inc hl                          ;; Advance to the DY high-byte field.
    ld (hl),d                       ;; Store DY's high byte.
    inc hl                          ;; Advance to the signed-step field.
    ld a,(workStep)                 ;; Load the edge's +1 or -1 X step.
    ld (hl),a                       ;; Store the signed-step byte.
    inc hl                          ;; Advance to the error low-byte field.
    ld de,(workError)               ;; Load the zeroed error accumulator.
    ld (hl),e                       ;; Store the error low byte.
    inc hl                          ;; Advance to the error high-byte field.
    ld (hl),d                       ;; Store the error high byte.
    ret                             ;; Return with the edge initialized.

;; Advance one edge using the same integer error accumulation as the C version.
advanceEdge::                        ;; HL points to the edge state to advance.
    ld (edgeOut),hl                 ;; Preserve the edge-state pointer.
    inc hl                          ;; Skip the current X low byte.
    inc hl                          ;; Point to the original DX low byte.
    ld c,(hl)                       ;; Load DX's low byte for this scanline.
    inc hl                          ;; Point to the original DX high byte.
    ld b,(hl)                       ;; Load DX's high byte for this scanline.
    ld (workDX),bc                  ;; Make a local copy; the stored edge DX stays constant.
    inc hl                          ;; Point to the DY low byte.
    ld e,(hl)                       ;; Load DY's low byte.
    inc hl                          ;; Point to the DY high byte.
    ld d,(hl)                       ;; Load DY's high byte.
    ld (workDY),de                  ;; Save DY for this scanline's stepping loop.
    inc hl                          ;; Skip the signed-step byte.
    inc hl                          ;; Point to the persistent error low byte.
    ld a,(hl)                       ;; Load the error low byte.
    ld (workError),a                ;; Save it in the local error word.
    inc hl                          ;; Point to the error high byte.
    ld a,(hl)                       ;; Load the error high byte.
    ld (workError+1),a              ;; Complete the local error word.
advance_edge_loop:                  ;; Repeat X steps while the local DX allows.
    ld hl,(workDY)                  ;; Load the vertical delta.
    ld de,(workError)               ;; Load the current local error.
    or a                            ;; Clear carry before subtracting.
    sbc hl,de                       ;; Calculate the threshold DY - error.
    ld (workThreshold),hl            ;; Save the threshold for comparison.
    ld hl,(workDX)                  ;; Load the remaining local DX.
    ld de,(workThreshold)           ;; Load the threshold.
    or a                            ;; Clear carry before comparing by subtraction.
    sbc hl,de                       ;; Calculate DX - (DY - error).
    jr c,advance_error_only         ;; Stop stepping when DX is below the threshold.

    ;; DX -= DY-error; move X by its signed unit step.
    ld (workDX),hl                  ;; Keep the reduced local DX for the next step.
    ld hl,(edgeOut)                 ;; Reload the edge-state base address.
    ld a,(hl)                       ;; Load the current X low byte.
    ld e,a                          ;; Place it in the low byte of DE.
    inc hl                          ;; Point to the current X high byte.
    ld a,(hl)                       ;; Load the current X high byte.
    ld d,a                          ;; Place it in the high byte of DE.
    inc hl                          ;; Advance from X high byte to the DX low byte.
    inc hl                          ;; Skip DX low byte.
    inc hl                          ;; Skip DX high byte.
    inc hl                          ;; Skip DY low byte.
    inc hl                          ;; Point to the signed-step field after DY high.
    ld a,(hl)                       ;; Read the edge's X direction.
    cp #1                           ;; Check for a positive step.
    jr z,advance_x_right            ;; Increment X when the step is +1.
    dec de                          ;; Otherwise decrement X for a -1 step.
    jr advance_x_store              ;; Store the updated X coordinate.
advance_x_right:                    ;; The edge moves toward increasing X.
    inc de                          ;; Increment the current X coordinate.
advance_x_store:                    ;; Store the one-pixel X update.
    ld hl,(edgeOut)                 ;; Reload the edge-state base address.
    ld (hl),e                       ;; Store the updated X low byte.
    inc hl                          ;; Point to the X high-byte field.
    ld (hl),d                       ;; Store the updated X high byte.
    ld hl,#0                        ;; Reset the local error after an X step.
    ld (workError),hl               ;; Keep that reset for the next local step.
    jp advance_edge_loop            ;; Check whether another X step is due.

advance_error_only:                 ;; No more X step is due on this scanline.
    ;; error += remaining local dx; persist only the error for the next row.
    ld hl,(workError)               ;; Load the current local error accumulator.
    ld de,(workDX)                  ;; Load the remaining local horizontal delta.
    add hl,de                       ;; Accumulate the remaining DX into the error.
    ld (workError),hl               ;; Save the updated error locally.
    ld hl,(edgeOut)                 ;; Reload the edge-state base address.
    ld de,#7                        ;; offset to error low byte
    add hl,de                       ;; Move HL to error low byte.
    ld de,(workError)               ;; Load the updated error accumulator.
    ld (hl),e                       ;; Store the error low byte.
    inc hl                          ;; Point to the error high byte.
    ld (hl),d                       ;; Store the error high byte.
    ret                             ;; Finish advancing this edge for the row.

;; Clip X to [0,319] and draw the inclusive single-row span.
drawLine::                           ;; Draw the span currently stored in lineX0/lineX1/RowY.
    ;; Check of Y is already performed (<0 and loop is until VisibleLine which is <=199)
    ld hl,(lineX0)                  ;; Load the first endpoint.
    ld de,#0                        ;; Set the left screen boundary.
    call cpct_compareSigned16            ;; Check whether endpoint zero is negative.
    jp nc,drawLine_check_right      ;; Check the right boundary when it is nonnegative.
    ld hl,(lineX1)                  ;; Load the second endpoint.
    ld de,#0                        ;; Set the left screen boundary.
    call cpct_compareSigned16            ;; Check whether endpoint one is negative too.
    jp c,drawLine_done              ;; Skip spans when both endpoints are left of screen.
drawLine_check_right:               ;; Check whether both endpoints are beyond X=319.
    ld hl,(lineX0)                  ;; Load the first endpoint.
    ld de,#319                      ;; Set the right screen boundary.
    call cpct_compareSigned16            ;; Compare the first endpoint with X=319.
    jp c,drawLine_clip_x            ;; Clip when endpoint zero is on or left of boundary.
    jp z,drawLine_clip_x            ;; Keep the inclusive endpoint at X=319.
    ld hl,(lineX1)                  ;; Load the second endpoint.
    ld de,#319                      ;; Set the right screen boundary.
    call cpct_compareSigned16            ;; Compare the second endpoint with X=319.
    jp c,drawLine_clip_x            ;; Clip when endpoint one is on or left of boundary.
    jp z,drawLine_clip_x            ;; Keep the inclusive endpoint at X=319.
    jp drawLine_done                ;; Skip spans when both endpoints are right of screen.
drawLine_clip_x:                    ;; Clamp both endpoints to the visible horizontal range.
    ld hl,(lineX0)                  ;; Load the first endpoint for clipping.
    call cpct_clipX                      ;; Clamp it to [0,319].
    ex de,hl
    push de
    ld hl,(lineX1)                  ;; Load the second endpoint for clipping.
    call cpct_clipX                      ;; Clamp it to [0,319].
    pop de
    ld a,(rowY)                     ;; Load the visible row's low byte.
    ld bc,(b_screenY)               ;; Get screen Y adress
    call cpct_bayerDrawHLineM1_asm  ;; Draw the inclusive one-row Bayer box.
drawLine_done:                      ;; Shared return path for skipped or drawn rows.
    ld a,(rowY)                     ;; Load the current row's low byte.
    call cpct_incScreenLine         ;; Advance even when this row was horizontally clipped.
    ret                             ;; Return to the triangle rasterizer.


;; Data for triangle draw
.area _DATA                        ;; Triangle state algorithm data.
tmpPt:          .ds 12             ;; Hold the private copy of three 4-byte vertices.
edgeLong:       .ds 2              ;; Current X.
                .ds 2              ;; X delta.
                .ds 2              ;; Y delta.
                .ds 1              ;; X step.
                .ds 2              ;; Error accumulator.
edgeShort1:     .ds 9              ;; Store the top-to-middle short edge.
edgeShort2:     .ds 9              ;; Store the middle-to-bottom short edge.
edgeShortActive: .ds 2             ;; Point to the short edge active on the current row.
lineX0:         .ds 2              ;; Hold the first horizontal-span endpoint.
lineX1:         .ds 2              ;; Hold the second horizontal-span endpoint.
rowY:           .ds 2              ;; Track the current scanline.
visibleBottom:  .ds 2              ;; Store the bottom scanline clipped to 199.
edgeOut:        .ds 2              ;; Temporarily hold an edge-state address.
workX:          .ds 2              ;; Temporarily hold an edge's starting X.
workDX:         .ds 2              ;; Temporarily hold its remaining horizontal delta.
workDY:         .ds 2              ;; Temporarily hold its vertical delta.
workStep:       .ds 1              ;; Store the edge's signed one-pixel X step.
workError:      .ds 2              ;; Temporarily hold its error accumulator.
workThreshold:  .ds 2              ;; Hold DY minus error during edge stepping.
