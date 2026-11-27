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
.globl geomCurrentPtr           ; Source poinnter
.globl geomNextPtr              ; Destination pointer
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
;; Algorithm:
;; 1. Copy the triangle into an internal polygon buffer.
;; 2. Test every source vertex cyclically against one clipping rectangle edge.
;; 3. Retain vertices inside the current half-plane.
;; 4. When an edge crosses the boundary, compute and append its intersection.
;; 5. Append the entering vertex when the crossing changes from outside to inside.
;; 6. Repeat for the left, right, top, and bottom clipping edges.
;; 7. Swap source and destination buffers after each completed pass.
;; 8. Suppress duplicate points and reject overflow beyond seven output vertices.
;; 9. Copy the final polygon to the caller and return its vertex count.
;;
;; Usage example:
;; (start code)
;;    // Clipping with M1 screen size
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
    ld      (geomOutputPtr),de                  ;; [6] Continue the triangle clipping algorithm.

    ;; No test on empty clipping rectangle.

    ;; Copy the input first so the output may alias it.
    ld      de,#ct_bufferA                      ;; [3] Destination is bufferA
    ld      bc,#12                              ;; [3] Triangle is 3 x 4 Bytes
    ldir                                        ;; [71] Copy (6x11 + 5)

    ld      hl,#ct_bufferA                      ;; [3] Make buffer A the initial source polygon.
    ld      (geomCurrentPtr),hl                 ;; [5] Store the initial source-buffer pointer.
    ld      hl,#ct_bufferB                      ;; [3] Make buffer B the initial destination polygon.
    ld      (geomNextPtr),hl                    ;; [5] Store the initial destination-buffer pointer.
    ld      a,#3                                ;; [2] Initialize the polygon with three triangle vertices.
    ld      (geomNbInput),a                     ;; [4] Record the initial source vertex count.
    xor     a                                   ;; [1] Initialize the pass and overflow state.
    ld      (geomStep),a                        ;; [4] Start with the left clipping edge.
    ld      (ct_overflow),a                     ;; [4] Clear the overflow condition.

ct_pass_loop:
    xor     a                                   ;; [1] Reset the source-vertex index.
    ld      (ct_dstCount),a                     ;; [4] Begin this clipping pass with no output vertices.
    ld      a,(geomNbInput)                     ;; [4] Load the source polygon size.
    or      a                                   ;; [1] Test whether the source polygon is empty.
    jp      z,ct_return_empty                   ;; [3] Return empty if no vertices survive.

    dec     a                                   ;; [1] Select the final vertex as the cyclic previous vertex.
    call    ct_getSrcPoint                      ;; [5] Resolve the previous cyclic source vertex.
    call    ct_loadPrevPoint                    ;; [5] Load the previous vertex coordinates.
    ld      hl,(geomPreviousX)                  ;; [5] Prepare previous X for inside testing.
    ld      (ct_testX),hl                       ;; [5] Set the X coordinate of the initial test point.
    ld      hl,(geomPreviousY)                  ;; [5] Prepare previous Y for inside testing.
    ld      (ct_testY),hl                       ;; [5] Set the Y coordinate of the initial test point.
    call    ct_isInside                         ;; [5] Classify the previous cyclic vertex.
    ld      (ct_prevInside),a                   ;; [4] Remember the previous inside state.

    xor     a                                   ;; [1] Reset the source-vertex index.
    ld      (geomIndex),a                       ;; [4] Start cyclic traversal at vertex zero.

ct_vertex_loop:
    ld      a,(geomIndex)                       ;; [4] Read the current source-vertex index.
    ld      b,a                                 ;; [1] Keep the previous state for edge-crossing comparison.
    ld      a,(geomNbInput)                     ;; [4] Read the active source-polygon size.
    cp      b                                   ;; [1] Determine whether the edge crosses the clip boundary.
    jp      z,ct_pass_done                      ;; [3] Finish the pass after processing every vertex.

    ld      a,b                                 ;; [1] Select the current source vertex.
    call    ct_getSrcPoint                      ;; [5] Resolve the current vertex in the source buffer.
    ld      e,(hl)                              ;; [2] Read current vertex Y low byte.
    inc     hl                                  ;; [2] Move to the current vertex X high byte.
    ld      d,(hl)                              ;; [2] Read current vertex Y high byte.
    ld      (geomCurrentX),de                   ;; [6] Store the current vertex X.
    inc     hl                                  ;; [2] Move to the current vertex X high byte.
    ld      e,(hl)                              ;; [2] Read current vertex Y low byte.
    inc     hl                                  ;; [2] Move to the current vertex X high byte.
    ld      d,(hl)                              ;; [2] Read current vertex Y high byte.
    ld      (geomCurrentY),de                   ;; [6] Store the current vertex Y.

    ld      hl,(geomCurrentX)                   ;; [5] Prepare current X for half-plane testing.
    ld      (ct_testX),hl                       ;; [5] Set the X coordinate of the current test point.
    ld      hl,(geomCurrentY)                   ;; [5] Prepare current Y for half-plane testing.
    ld      (ct_testY),hl                       ;; [5] Set the Y coordinate of the current test point.
    call    ct_isInside                         ;; [5] Classify the current vertex against the active edge.
    ld      (ct_currInside),a                   ;; [4] Remember the current inside state.

    ld      a,(ct_prevInside)                   ;; [4] Load the previous inside state.
    ld      b,a                                 ;; [1] Keep the previous state for edge-crossing comparison.
    ld      a,(ct_currInside)                   ;; [4] Load the current inside state.
    cp      b                                   ;; [1] Determine whether the edge crosses the clip boundary.
    jr      z,ct_sameSide                       ;; [2/3] Handle two vertices on the same side.

    call    ct_intersection                     ;; [5] Compute the crossing with the active boundary.
    call    ct_appendPoint                      ;; [5] Append the crossing point.
    ld      a,(ct_currInside)                   ;; [4] Load the current inside state.
    or      a                                   ;; [1] Test whether the current vertex is inside.
    jr      z,ct_updatePrev                     ;; [2/3] Leave outside-only crossings out of the result.
    call    ct_setAppendCurrent                 ;; [5] Prepare the entering current vertex.
    call    ct_appendPoint                      ;; [5] Append the crossing point.
    jr      ct_updatePrev                       ;; [3] Advance the previous-vertex state.

ct_sameSide:
    ld      a,(ct_currInside)                   ;; [4] Load the current inside state.
    or      a                                   ;; [1] Test whether both vertices are inside.
    jr      z,ct_updatePrev                     ;; [2/3] Append nothing for two outside vertices.
    call    ct_setAppendCurrent                 ;; [5] Prepare the inside current vertex.
    call    ct_appendPoint                      ;; [5] Append the inside vertex.

ct_updatePrev:
    ld      hl,(geomCurrentX)                   ;; [5] Carry the current vertex into previous X.
    ld      (geomPreviousX),hl                  ;; [5] Update the previous vertex X.
    ld      hl,(geomCurrentY)                   ;; [5] Carry the current vertex into previous Y.
    ld      (geomPreviousY),hl                  ;; [5] Update the previous vertex Y.
    ld      a,(ct_currInside)                   ;; [4] Carry the current classification forward.
    ld      (ct_prevInside),a                   ;; [4] Update the previous inside state.
    ld      a,(geomIndex)                       ;; [4] Read the completed source index.
    inc     a                                   ;; [1] Advance cyclic traversal.
    ld      (geomIndex),a                       ;; [4] Record the next source index.
    jp      ct_vertex_loop                      ;; [3] Process the next source vertex.

ct_pass_done:
    call    ct_removeClosingDuplicate           ;; [5] Remove the duplicate closing vertex.
    ld      a,(ct_overflow)                     ;; [4] Check whether the pass overflowed.
    or      a                                   ;; [1] Test whether the polygon became empty.
    jp      nz,ct_return_empty                  ;; [3] Reject an oversized clipped polygon.

    ld      a,(ct_dstCount)                     ;; [4] Load this pass result count.
    ld      (geomNbInput),a                     ;; [4] Promote this result to the next source polygon.
    or      a                                   ;; [1] Test whether the polygon became empty.
    jp      z,ct_return_empty                   ;; [3] Return immediately when this pass removed all vertices.

    ld      hl,(geomCurrentPtr)                 ;; [5] Load the final cyclic polygon buffer.
    ld      de,(geomNextPtr)                    ;; [6] Retrieve the old destination buffer.
    ld      (geomCurrentPtr),de                 ;; [6] Use the completed pass result as next source.
    ld      (geomNextPtr),hl                    ;; [5] Reuse the old source buffer for the next pass.

    ld      a,(geomStep)                        ;; [4] Load the completed edge index.
    inc     a                                   ;; [1] Advance to the next clipping edge.
    ld      (geomStep),a                        ;; [4] Record the next clipping edge.
    cp      #4                                  ;; [2] Check whether left/right/top/bottom passes are complete.
    jp      nz,ct_pass_loop                     ;; [3] Start the next rectangle-edge pass.

    ;; Copy the final cyclic point list to the caller's output buffer.
    ld      a,(geomNbInput)                     ;; [4] Restore the final vertex count for return.
    add     a,a                                 ;; [1] Multiply by four bytes per vertex.
    add     a,a                                 ;; [1] Multiply by four bytes per vertex.
    ld      b,a                                 ;; [1] Set the final copy byte count.
    ld      hl,(geomCurrentPtr)                 ;; [5] Load the final cyclic polygon buffer.
    ld      de,(geomOutputPtr)                  ;; [6] Load the caller output polygon.
ct_copy_output:
    ld      a,(hl)                              ;; [2] Continue the clipping subroutine's polygon transform.
    ld      (de),a                              ;; [2] Continue the clipping subroutine's polygon transform.
    inc     hl                                  ;; [2] Continue the clipping subroutine's polygon transform.
    inc     de                                  ;; [2] Continue the clipping subroutine's polygon transform.
    djnz    ct_copy_output                      ;; [3/4] Continue the clipping subroutine's polygon transform.
    ld      a,(geomNbInput)                     ;; [4] Continue the clipping subroutine's polygon transform.
    jp      ct_return                           ;; [3] Continue the clipping subroutine's polygon transform.

ct_return_empty:
    xor     a                                   ;; [1] Return zero vertices.
ct_return:
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

;; A = point index; returns HL = source point address.
ct_getSrcPoint::
    ld      l,a                                 ;; [1] Place source index in HL low byte.
    ld      h,#0                                ;; [2] Clear HL high byte.
    add     hl,hl                               ;; [3] Multiply the index by four bytes per point.
    add     hl,hl                               ;; [3] Multiply the index by four bytes per point.
    ld      de,(geomCurrentPtr)                 ;; [6] Load the active source-buffer base.
    add     hl,de                               ;; [3] Resolve the source vertex address.
    ret                                         ;; [3] Return the source vertex pointer.

;; A = point index; returns HL = destination point address.
ct_getDstPoint::
    ld      l,a                                 ;; [1] Place destination index in HL low byte.
    ld      h,#0                                ;; [2] Clear HL high byte.
    add     hl,hl                               ;; [3] Multiply the index by four bytes per point.
    add     hl,hl                               ;; [3] Multiply the index by four bytes per point.
    ld      de,(geomNextPtr)                    ;; [6] Load the active destination-buffer base.
    add     hl,de                               ;; [3] Resolve the destination vertex address.
    ret                                         ;; [3] Return the destination vertex pointer.

ct_loadPrevPoint::
    ld      e,(hl)                              ;; [2] Read previous vertex Y low byte.
    inc     hl                                  ;; [2] Move to previous vertex Y high byte.
    ld      d,(hl)                              ;; [2] Read previous vertex Y high byte.
    ld      (geomPreviousX),de                  ;; [6] Store the cyclic previous vertex X.
    inc     hl                                  ;; [2] Move to previous vertex Y high byte.
    ld      e,(hl)                              ;; [2] Read previous vertex Y low byte.
    inc     hl                                  ;; [2] Move to previous vertex Y high byte.
    ld      d,(hl)                              ;; [2] Read previous vertex Y high byte.
    ld      (geomPreviousY),de                  ;; [6] Store the cyclic previous vertex Y.
    ret                                         ;; [3] Return with the previous vertex loaded.

;; Returns A=1 when (ct_testX,ct_testY) is within the current inclusive edge.
ct_isInside::
    ld      a,(geomStep)                        ;; [4] Select the active clipping edge.
    or      a                                   ;; [1] Clear carry before boundary comparison.
    jr      z,ct_insideLeft                     ;; [2/3] Use the left half-plane rule.
    cp      #1                                  ;; [2] Test whether this is the right-edge pass.
    jr      z,ct_insideRight                    ;; [2/3] Use the right half-plane rule.
    cp      #2                                  ;; [2] Test whether this is the top-edge pass.
    jr      z,ct_insideTop                      ;; [2/3] Use the top half-plane rule.

ct_insideBottom:
    ld      hl,(ct_testY)                       ;; [5] Continue the clipping subroutine's polygon transform.
    ld      de,(clip_yend)                      ;; [6] Continue the clipping subroutine's polygon transform.
    or      a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    sbc     hl,de                               ;; [4] Continue the clipping subroutine's polygon transform.
    jp      m,ct_insideYes                      ;; [3] Continue the clipping subroutine's polygon transform.
    xor     a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_insideLeft:
    ld      hl,(ct_testX)                       ;; [5] Continue the clipping subroutine's polygon transform.
    ld      de,(clip_xmin)                      ;; [6] Continue the clipping subroutine's polygon transform.
    or      a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    sbc     hl,de                               ;; [4] Continue the clipping subroutine's polygon transform.
    jp      p,ct_insideYes                      ;; [3] Continue the clipping subroutine's polygon transform.
    xor     a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_insideRight:
    ld      hl,(ct_testX)                       ;; [5] Continue the clipping subroutine's polygon transform.
    ld      de,(clip_xend)                      ;; [6] Continue the clipping subroutine's polygon transform.
    or      a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    sbc     hl,de                               ;; [4] Continue the clipping subroutine's polygon transform.
    jp      m,ct_insideYes                      ;; [3] Continue the clipping subroutine's polygon transform.
    xor     a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_insideTop:
    ld      hl,(ct_testY)                       ;; [5] Continue the clipping subroutine's polygon transform.
    ld      de,(clip_ymin)                      ;; [6] Continue the clipping subroutine's polygon transform.
    or      a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    sbc     hl,de                               ;; [4] Continue the clipping subroutine's polygon transform.
    jp      p,ct_insideYes                      ;; [3] Continue the clipping subroutine's polygon transform.
    xor     a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_insideYes:
    ld      a,#1                                ;; [2] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_setAppendCurrent::
    ld      hl,(geomCurrentX)                   ;; [5] Prepare the current vertex X for append.
    ld      (ct_appendX),hl                     ;; [5] Set the candidate append X.
    ld      hl,(geomCurrentY)                   ;; [5] Prepare the current vertex Y for append.
    ld      (ct_appendY),hl                     ;; [5] Set the candidate append Y.
    ret                                         ;; [3] Return with the current point selected.

;; Append a point, suppressing consecutive duplicates.
ct_appendPoint::
    ld      a,(ct_dstCount)                     ;; [4] Read the old destination count.
    or      a                                   ;; [1] Clear carry before coordinate comparison.
    jr      z,ct_appendCapacity                 ;; [2/3] Reserve the first destination slot.
    dec     a                                   ;; [1] Select the most recently appended point.
    call    ct_getDstPoint                      ;; [5] Resolve the new destination slot.
    ld      e,(hl)                              ;; [2] Read previous destination Y low byte.
    inc     hl                                  ;; [2] Move to candidate Y high byte.
    ld      d,(hl)                              ;; [2] Read previous destination Y high byte.
    ld      (geomX1),de                         ;; [6] Store the previous destination X.
    inc     hl                                  ;; [2] Move to candidate Y high byte.
    ld      e,(hl)                              ;; [2] Read previous destination Y low byte.
    inc     hl                                  ;; [2] Move to candidate Y high byte.
    ld      d,(hl)                              ;; [2] Read previous destination Y high byte.
    ld      (geomY1),de                         ;; [6] Store the previous destination Y.
    ld      hl,(ct_appendX)                     ;; [5] Load the candidate point X.
    ld      de,(geomX1)                         ;; [6] Load the previous destination X.
    or      a                                   ;; [1] Clear carry before coordinate comparison.
    sbc     hl,de                               ;; [4] Compare candidate and previous Y.
    jr      nz,ct_appendCapacity                ;; [2/3] Append because the X coordinates differ.
    ld      hl,(ct_appendY)                     ;; [5] Load the candidate point Y.
    ld      de,(geomY1)                         ;; [6] Load the previous destination Y.
    or      a                                   ;; [1] Clear carry before coordinate comparison.
    sbc     hl,de                               ;; [4] Compare candidate and previous Y.
    ret     z                                   ;; [2/4] Suppress the consecutive duplicate.

ct_appendCapacity:
    ld      a,(ct_dstCount)                     ;; [4] Continue the clipping subroutine's polygon transform.
    cp      #8                                  ;; [2] Continue the clipping subroutine's polygon transform.
    jr      nc,ct_appendOverflow                ;; [2/3] Continue the clipping subroutine's polygon transform.
    call    ct_getDstPoint                      ;; [5] Continue the clipping subroutine's polygon transform.
    ld      de,(ct_appendX)                     ;; [6] Continue the clipping subroutine's polygon transform.
    ld      (hl),e                              ;; [2] Continue the clipping subroutine's polygon transform.
    inc     hl                                  ;; [2] Continue the clipping subroutine's polygon transform.
    ld      (hl),d                              ;; [2] Continue the clipping subroutine's polygon transform.
    inc     hl                                  ;; [2] Continue the clipping subroutine's polygon transform.
    ld      de,(ct_appendY)                     ;; [6] Continue the clipping subroutine's polygon transform.
    ld      (hl),e                              ;; [2] Continue the clipping subroutine's polygon transform.
    inc     hl                                  ;; [2] Continue the clipping subroutine's polygon transform.
    ld      (hl),d                              ;; [2] Continue the clipping subroutine's polygon transform.
    ld      a,(ct_dstCount)                     ;; [4] Continue the clipping subroutine's polygon transform.
    inc     a                                   ;; [1] Continue the clipping subroutine's polygon transform.
    ld      (ct_dstCount),a                     ;; [4] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_appendOverflow:
    ld      a,#1                                ;; [2] Continue the clipping subroutine's polygon transform.
    ld      (ct_overflow),a                     ;; [4] Continue the clipping subroutine's polygon transform.
    ret                                         ;; [3] Continue the clipping subroutine's polygon transform.

ct_removeClosingDuplicate::
    ld      a,(ct_dstCount)                     ;; [4] Read the count containing the duplicate.
    cp      #2                                  ;; [2] Test whether a closing comparison is possible.
    ret     c                                   ;; [2/4] Keep the short list unchanged.

    ld      hl,(geomNextPtr)                    ;; [5] Point to the first destination vertex.
    ld      e,(hl)                              ;; [2] Read final vertex Y low byte.
    inc     hl                                  ;; [2] Move to final vertex Y high byte.
    ld      d,(hl)                              ;; [2] Read final vertex Y high byte.
    ld      (geomX0),de                         ;; [6] Store the first output X.
    inc     hl                                  ;; [2] Move to final vertex Y high byte.
    ld      e,(hl)                              ;; [2] Read final vertex Y low byte.
    inc     hl                                  ;; [2] Move to final vertex Y high byte.
    ld      d,(hl)                              ;; [2] Read final vertex Y high byte.
    ld      (geomY0),de                         ;; [6] Store the first output Y.

    ld      a,(ct_dstCount)                     ;; [4] Read the count containing the duplicate.
    dec     a                                   ;; [1] Remove the cyclic duplicate closing vertex.
    call    ct_getDstPoint                      ;; [5] Resolve the final destination vertex.
    ld      e,(hl)                              ;; [2] Read final vertex Y low byte.
    inc     hl                                  ;; [2] Move to final vertex Y high byte.
    ld      d,(hl)                              ;; [2] Read final vertex Y high byte.
    ld      (geomX1),de                         ;; [6] Store the final output X.
    inc     hl                                  ;; [2] Move to final vertex Y high byte.
    ld      e,(hl)                              ;; [2] Read final vertex Y low byte.
    inc     hl                                  ;; [2] Move to final vertex Y high byte.
    ld      d,(hl)                              ;; [2] Read final vertex Y high byte.
    ld      (geomY1),de                         ;; [6] Store the final output Y.
    ld      hl,(geomX0)                         ;; [5] Load first output X.
    ld      de,(geomX1)                         ;; [6] Load final output X.
    or      a                                   ;; [1] Clear carry for coordinate comparison.
    sbc     hl,de                               ;; [4] Compare first and final Y.
    ret     nz                                  ;; [2/4] Keep the final vertex if Y differs.
    ld      hl,(geomY0)                         ;; [5] Load first output Y.
    ld      de,(geomY1)                         ;; [6] Load final output Y.
    or      a                                   ;; [1] Clear carry for coordinate comparison.
    sbc     hl,de                               ;; [4] Compare first and final Y.
    ret     nz                                  ;; [2/4] Keep the final vertex if Y differs.
    ld      a,(ct_dstCount)                     ;; [4] Read the count containing the duplicate.
    dec     a                                   ;; [1] Remove the cyclic duplicate closing vertex.
    ld      (ct_dstCount),a                     ;; [4] Record the corrected result count.
    ret                                         ;; [3] Finish closing-vertex cleanup.

;; Compute the crossing point for the active half-plane.
;; Uses cpct_clipLine's shared exact rounded multiply/divide helper.
ct_intersection::
    ld      a,(geomStep)                        ;; [4] Select the active clipping edge.
    or      a                                   ;; [1] Test the axis-selection flag.
    jr      z,ct_intersectLeft                  ;; [2/3] Prepare left-boundary intersection inputs.
    cp      #1                                  ;; [2] Test whether this is the right-edge branch.
    jr      z,ct_intersectRight                 ;; [2/3] Prepare right-boundary intersection inputs.
    cp      #2                                  ;; [2] Test whether this is the top-edge branch.
    jr      z,ct_intersectTop                   ;; [2/3] Prepare top-boundary intersection inputs.

ct_intersectBottom:
    ld      hl,(geomPreviousY)                  ;; [5] Load the previous point on the Y axis.
    ld      (ct_prevAxis),hl                    ;; [5] Store the previous Y-axis endpoint.
    ld      hl,(geomCurrentY)                   ;; [5] Load the current point on the Y axis.
    ld      (ct_currAxis),hl                    ;; [5] Store the current Y-axis endpoint.
    ld      hl,(clip_yend)                      ;; [5] Load the bottom clipping boundary.
    dec     hl                                  ;; [2] Convert the exclusive right/bottom limit to inclusive coordinates.
    ld      (ct_boundary),hl                    ;; [5] Store the active bottom boundary.
    ld      hl,(geomPreviousX)                  ;; [5] Load previous X as the perpendicular coordinate.
    ld      (ct_prevOther),hl                   ;; [5] Store previous perpendicular coordinate.
    ld      hl,(geomCurrentX)                   ;; [5] Load current X as the perpendicular coordinate.
    ld      (ct_currOther),hl                   ;; [5] Store current perpendicular coordinate.
    xor     a                                   ;; [1] Mark Y as the intersection axis.
    ld      (ct_axisIsX),a                      ;; [4] Prepare one of the active clipping-edge intersection branches.
    jr      ct_intersectionReady                ;; [3] Prepare one of the active clipping-edge intersection branches.

ct_intersectLeft:
    ld      hl,(geomPreviousX)                  ;; [5] Load previous X on the clipping axis.
    ld      (ct_prevAxis),hl                    ;; [5] Store the previous X-axis endpoint.
    ld      hl,(geomCurrentX)                   ;; [5] Load current X on the clipping axis.
    ld      (ct_currAxis),hl                    ;; [5] Store the current X-axis endpoint.
    ld      hl,(clip_xmin)                      ;; [5] Load the left clipping boundary.
    ld      (ct_boundary),hl                    ;; [5] Store the active left boundary.
    ld      hl,(geomPreviousY)                  ;; [5] Load previous Y as the perpendicular coordinate.
    ld      (ct_prevOther),hl                   ;; [5] Store previous perpendicular coordinate.
    ld      hl,(geomCurrentY)                   ;; [5] Load current Y as the perpendicular coordinate.
    ld      (ct_currOther),hl                   ;; [5] Store current perpendicular coordinate.
    ld      a,#1                                ;; [2] Mark X as the intersection axis.
    ld      (ct_axisIsX),a                      ;; [4] Prepare one of the active clipping-edge intersection branches.
    jr      ct_intersectionReady                ;; [3] Prepare one of the active clipping-edge intersection branches.

ct_intersectRight:
    ld      hl,(geomPreviousX)                  ;; [5] Load previous X on the clipping axis.
    ld      (ct_prevAxis),hl                    ;; [5] Store the previous X-axis endpoint.
    ld      hl,(geomCurrentX)                   ;; [5] Load current X on the clipping axis.
    ld      (ct_currAxis),hl                    ;; [5] Store the current X-axis endpoint.
    ld      hl,(clip_xend)                      ;; [5] Load the right clipping boundary.
    dec     hl                                  ;; [2] Convert the right exclusive limit to inclusive coordinates.
    ld      (ct_boundary),hl                    ;; [5] Store the active right boundary.
    ld      hl,(geomPreviousY)                  ;; [5] Load previous Y as the perpendicular coordinate.
    ld      (ct_prevOther),hl                   ;; [5] Store previous perpendicular coordinate.
    ld      hl,(geomCurrentY)                   ;; [5] Load current Y as the perpendicular coordinate.
    ld      (ct_currOther),hl                   ;; [5] Store current perpendicular coordinate.
    ld      a,#1                                ;; [2] Mark X as the intersection axis.
    ld      (ct_axisIsX),a                      ;; [4] Prepare one of the active clipping-edge intersection branches.
    jr      ct_intersectionReady                ;; [3] Prepare one of the active clipping-edge intersection branches.

ct_intersectTop:
    ld      hl,(geomPreviousY)                  ;; [5] Load previous Y on the clipping axis.
    ld      (ct_prevAxis),hl                    ;; [5] Store the previous Y-axis endpoint.
    ld      hl,(geomCurrentY)                   ;; [5] Load current Y on the clipping axis.
    ld      (ct_currAxis),hl                    ;; [5] Store the current Y-axis endpoint.
    ld      hl,(clip_ymin)                      ;; [5] Load the top clipping boundary.
    ld      (ct_boundary),hl                    ;; [5] Store the active top boundary.
    ld      hl,(geomPreviousX)                  ;; [5] Load previous X as the perpendicular coordinate.
    ld      (ct_prevOther),hl                   ;; [5] Store previous perpendicular coordinate.
    ld      hl,(geomCurrentX)                   ;; [5] Load current X as the perpendicular coordinate.
    ld      (ct_currOther),hl                   ;; [5] Store current perpendicular coordinate.
    xor     a                                   ;; [1] Mark Y as the intersection axis.
    ld      (ct_axisIsX),a                      ;; [4] Prepare one of the active clipping-edge intersection branches.

ct_intersectionReady:
    ld      hl,(ct_currAxis)                    ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      de,(ct_prevAxis)                    ;; [6] Prepare one of the active clipping-edge intersection branches.
    or      a                                   ;; [1] Prepare one of the active clipping-edge intersection branches.
    sbc     hl,de                               ;; [4] Prepare one of the active clipping-edge intersection branches.
    call    ct_absHL                            ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_tD),hl                          ;; [5] Prepare one of the active clipping-edge intersection branches.

    ld      hl,(ct_boundary)                    ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      de,(ct_prevAxis)                    ;; [6] Prepare one of the active clipping-edge intersection branches.
    or      a                                   ;; [1] Prepare one of the active clipping-edge intersection branches.
    sbc     hl,de                               ;; [4] Prepare one of the active clipping-edge intersection branches.
    call    ct_absHL                            ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_tE),hl                          ;; [5] Prepare one of the active clipping-edge intersection branches.

    ld      hl,(ct_currOther)                   ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      de,(ct_prevOther)                   ;; [6] Prepare one of the active clipping-edge intersection branches.
    or      a                                   ;; [1] Prepare one of the active clipping-edge intersection branches.
    sbc     hl,de                               ;; [4] Prepare one of the active clipping-edge intersection branches.
    ld      de,(ct_tE)                          ;; [6] Prepare one of the active clipping-edge intersection branches.
    ld      bc,(ct_tD)                          ;; [6] Prepare one of the active clipping-edge intersection branches.
    call    cpct_clipLine_intersect             ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      de,(ct_prevOther)                   ;; [6] Prepare one of the active clipping-edge intersection branches.
    add     hl,de                               ;; [3] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_intersectionOther),hl           ;; [5] Prepare one of the active clipping-edge intersection branches.

    ld      a,(ct_axisIsX)                      ;; [4] Prepare one of the active clipping-edge intersection branches.
    or      a                                   ;; [1] Prepare one of the active clipping-edge intersection branches.
    jr      z,ct_intersectionOnY                ;; [2/3] Prepare one of the active clipping-edge intersection branches.
    ld      hl,(ct_boundary)                    ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_appendX),hl                     ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      hl,(ct_intersectionOther)           ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_appendY),hl                     ;; [5] Prepare one of the active clipping-edge intersection branches.
    ret                                         ;; [3] Prepare one of the active clipping-edge intersection branches.

ct_intersectionOnY:
    ld      hl,(ct_intersectionOther)           ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_appendX),hl                     ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      hl,(ct_boundary)                    ;; [5] Prepare one of the active clipping-edge intersection branches.
    ld      (ct_appendY),hl                     ;; [5] Prepare one of the active clipping-edge intersection branches.
    ret                                         ;; [3] Prepare one of the active clipping-edge intersection branches.

;; HL = signed value; returns its unsigned magnitude in HL.
ct_absHL::
    bit     7,h                                 ;; [2] Test whether the axis distance is negative.
    ret     z                                   ;; [2/4] Keep the positive magnitude.
    xor     a                                   ;; [1] Prepare signed-distance negation.
    sub     l                                   ;; [1] Negate the low byte.
    ld      l,a                                 ;; [1] Store the negated low byte.
    sbc     a,a                                 ;; [1] Propagate the sign into A.
    sub     h                                   ;; [1] Negate the high byte.
    ld      h,a                                 ;; [1] Store the unsigned magnitude high byte.
    ret                                         ;; [3] Return the absolute axis distance.

.area _DATA
ct_dstCount:          .ds 1  ;; (1) Number of points in the destination list
ct_prevInside:        .ds 1  ;; (1) Inside status of the previous point
ct_currInside:        .ds 1  ;; (1) Inside status of the current point
ct_overflow:          .ds 1  ;; (1) Internal overflow status
ct_testX:             .ds 2  ;; (2) X coordinate used for a test
ct_testY:             .ds 2  ;; (2) Y coordinate used for a test
ct_appendX:           .ds 2  ;; (2) X coordinate of a point to append
ct_appendY:           .ds 2  ;; (2) Y coordinate of a point to append
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
