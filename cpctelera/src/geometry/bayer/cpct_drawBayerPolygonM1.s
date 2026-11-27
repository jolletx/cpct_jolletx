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

.globl cpct_bayerDrawHLineM1_asm
.globl cpct_compareSigned16_asm
.globl cpct_compScreenLine_asm
.globl cpct_incScreenLine_asm
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Function: cpct_drawBayerPolygonM1_asm
;;
;; Draw an ordered convex list of on-screen (u16 x, u16 y) points.
;;    
;;
;; C Definition:
;;    void <cpct_drawBayerPolygonM1>(const u16 *PtArray, u16 nbPoints);
;;
;; Input Parameters:
;;    (2B HL)     PtArray - Adress of 3 i16 Points defining a triangle to draw
;;    (2B DE)     nbPoints - Only E (low byte) is used
;;
;; Details:
;;   1. Reject polygons with less than three vertices.
;;   2. Preserve the input pointer and vertex count in the geometry workspace.
;;   3. Scan every vertex to find geomTopY, geomBottomY,  topIndex, topMinX,
;;      and topMaxX.
;;   4. Select geomTopY as the initial scanline and position it in the Bayer
;;      screen-line lookup.
;;   5. Draw the topmost horizontal interval from topMinX through topMaxX.
;;   6. If the top and bottom rows are the same, terminate; otherwise initialize
;;      one forward edge and one reverse-order edge.
;;   7. Advance both initialized edges once to place their X coordinates on the
;;      row immediately below the topmost row.
;;   8. Set geomCurrentY to that first row below the top row.
;;   9. At the start of each row, replace either chain edge that has reached its
;;      end by the next non-horizontal polygon edge.
;;   10. Copy the forward-edge X coordinate into spanX0 and the backward-edge X
;;       coordinate into spanX1.
;;   11. Draw the current horizontal span, including the Bayer row correction.
;;   12. If geomCurrentY is geomBottomY, terminate without advancing further.
;;   13. Advance every active edge from the current row to the next row.
;;   14. Increment geomCurrentY and repeat from step 9.
;;   15. Restore IX/IY and return when the row loop or the initial validation
;;       exits.
;; 
;; Destroyed Register values:
;;    AF, BC, DE, HL
;;
;; Required memory:
;;
;;
;; Time Measures: (does not include 35 us call to cpct_getScreenPtr_asm)
;; (start code)
;;    Case / Coordinates                       | Pixels | microSecs (us) | CPU Cycles
;;   ---------------------------------------------------------------------------------
;;    Box x0=0 x1=319 y0=0 y1=199              | 101    | ~94375         | ~
;;   ---------------------------------------------------------------------------------
;; (end code)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


.area _CODE
_cpct_drawBayerPolygonM1::
cpct_drawBayerPolygonM1_asm::
    push    ix                                  ;; [5] Preserve caller IX.
    push    iy                                  ;; [5] Preserve caller IY.

    ld      (geomInputPtr),hl                   ;; [5] Save the ordered vertex-list pointer.
    ld      a,e                                 ;; [1] Get the byte-sized vertex count.
    ld      (geomNbInput),a                     ;; [4] Store the vertex count in workspace.
    cp      #3                                  ;; [2] A polygon needs at least three vertices.
    jp      c,polygon_exit                      ;; [3] Exit for an invalid polygon.

    call    findVerticalBounds                  ;; [5] Find vertical limits and top-row X limits.

    ld      a,(geomTopY)                        ;; [4] Load the first row to draw.
    ld      (geomCurrentY),a                    ;; [4] Initialize the current scanline.
    ld      b,a                                 ;; [1] Pass Y to the screen-line helper.
    call    cpct_compScreenLine_asm             ;; [5] Calculate the top screen row address.

    ld      hl,(topMinX)                        ;; [5] Load the left top-row endpoint.
    ld      (spanX0),hl                         ;; [5] Set the span left endpoint.
    ld      hl,(topMaxX)                        ;; [5] Load the right top-row endpoint.
    ld      (spanX1),hl                         ;; [5] Set the span right endpoint.
    call    drawSpan                            ;; [5] Draw the top horizontal span.

    ld      a,(geomTopY)                        ;; [4] Check whether there are lower rows.
    ld      b,a                                 ;; [1] Keep top Y for the comparison.
    ld      a,(geomBottomY)                     ;; [4] Load the bottom Y.
    cp      b                                   ;; [1] Compare bottom Y with top Y.
    jp      z,polygon_exit                      ;; [3] Exit if the polygon is a flat segment.

    call    setupForwardChain                   ;; [5] Build the forward contour edge.
    call    setupBackwardChain                  ;; [5] Build the reverse contour edge.

    ld      hl,#edgeForward                     ;; [3] Select the forward edge state.
    ld      a,(forwardActive)                   ;; [4] Check whether a forward edge exists.
    or      a                                   ;; [1] Set flags from the active-state byte.
    call    nz,polygonAdvanceEdge               ;; [3/5] Advance the forward edge to the next row.
    ld      hl,#edgeBackward                    ;; [3] Select the backward edge state.
    ld      a,(backwardActive)                  ;; [4] Check whether a backward edge exists.
    or      a                                   ;; [1] Set flags from the active-state byte.
    call    nz,polygonAdvanceEdge               ;; [3/5] Advance the backward edge to the next row.

    ld      a,(geomTopY)                        ;; [4] Start below the already-drawn top row.
    inc     a                                   ;; [1] Increment to the next scanline.
    ld      (geomCurrentY),a                    ;; [4] Store the first lower row.
    call    cpct_incScreenLine_asm              ;; [5] Advance the shared Bayer screen row.

row_loop:
    call    updateForwardChain                  ;; [5] Switch forward chain at a reached vertex.
    call    updateBackwardChain                 ;; [5] Switch backward chain at a reached vertex.

    ld      hl,(edgeForward)                    ;; [5] Read the forward edge X coordinate.
    ld      (spanX0),hl                         ;; [5] Use it as the left span endpoint.
    ld      hl,(edgeBackward)                   ;; [5] Read the backward edge X coordinate.
    ld      (spanX1),hl                         ;; [5] Use it as the right span endpoint.
    call    drawSpan                            ;; [5] Fill the horizontal row span.

    ld      a,(geomCurrentY)                    ;; [4] Load the row just drawn.
    ld      b,a                                 ;; [1] Keep current Y for comparison.
    ld      a,(geomBottomY)                     ;; [4] Load the final scanline.
    cp      b                                   ;; [1] Compare current Y with bottom Y.
    jp      z,polygon_exit                      ;; [3] Stop after drawing the bottom row.

    ld      hl,#edgeForward                     ;; [3] Select the forward edge state.
    ld      a,(forwardActive)                   ;; [4] Check whether it is active.
    or      a                                   ;; [1] Set flags from the active-state byte.
    call    nz,polygonAdvanceEdge               ;; [3/5] Advance the active forward edge.
    ld      hl,#edgeBackward                    ;; [3] Select the backward edge state.
    ld      a,(backwardActive)                  ;; [4] Check whether it is active.
    or      a                                   ;; [1] Set flags from the active-state byte.
    call    nz,polygonAdvanceEdge               ;; [3/5] Advance the active backward edge.

    ld      a,(geomCurrentY)                    ;; [4] Load the row whose next line follows.
    inc     a                                   ;; [1] Move to the next scanline.
    ld      (geomCurrentY),a                    ;; [4] Store the next current Y.
    call    cpct_incScreenLine_asm              ;; [5] Advance the shared Bayer screen row.
    jp      row_loop                            ;; [3] Process the next polygon row.

polygon_exit:
    pop    iy                                   ;; [5] Restore caller's IY.
    pop    ix                                   ;; [5] Restore caller's IX.
    ret                                         ;; [3] Return from the polygon renderer.

;; Find the top and bottom rows and the horizontal extent of the top row.
findVerticalBounds:
    ;; Initialize both bounds and the top-row span from vertex zero.
    ld      hl,(geomInputPtr)                   ;; [5] Point to the first vertex.
    ld      e,(hl)                              ;; [2] Load first vertex X low byte.
    inc     hl                                  ;; [2] Advance to X high byte.
    ld      d,(hl)                              ;; [2] Load first vertex X high byte.
    ld      (topMinX),de                        ;; [6] Initialize top-row minimum X.
    ld      (topMaxX),de                        ;; [6] Initialize top-row maximum X.
    inc     hl                                  ;; [2] Advance to first vertex Y.
    ld      a,(hl)                              ;; [2] Load first vertex Y.
    ld      (geomTopY),a                        ;; [4] Initialize the top bound.
    ld      (geomBottomY),a                     ;; [4] Initialize the bottom bound.
    xor     a                                   ;; [1] Select vertex index zero.
    ld      (topIndex),a                        ;; [4] Initialize the top vertex index.
    ld      a,#1                                ;; [2] Begin scanning at vertex one.
    ld      (geomIndex),a                       ;; [4] Store the first remaining index.

find_bounds_loop:
    ;; Stop once every vertex has been inspected.
    ld      a,(geomIndex)                       ;; [4] Load current vertex index.
    ld      b,a                                 ;; [1] Preserve it for getPoint.
    ld      a,(geomNbInput)                     ;; [4] Load the vertex count.
    cp      b                                   ;; [1] Compare count with current index.
    ret     z                                   ;; [2/4] Finish when all vertices are inspected.

    ld      a,b                                 ;; [1] Select the indexed vertex.
    call    getPoint                            ;; [5] Resolve vertex address in HL.
    ;; Extract this vertex's signed X and Y coordinates.
    ld      e,(hl)                              ;; [2] Load vertex X low byte.
    inc     hl                                  ;; [2] Advance to X high byte.
    ld      d,(hl)                              ;; [2] Load vertex X high byte.
    ld      (geomCurrentX),de                   ;; [6] Preserve this vertex X.
    inc     hl                                  ;; [2] Advance to Y low byte.
    ld      a,(hl)                              ;; [2] Load vertex Y.
    ld      (scanY),a                           ;; [4] Preserve Y for bottom check.

    ld      b,a                                 ;; [1] Keep current Y in B.
    ld      a,(geomTopY)                        ;; [4] Load the current top Y.
    cp      b                                   ;; [1] Compare top Y with current Y.
    ;; A new lower Y belongs below top; skip top handling for an existing row.
    jr      c,find_bounds_check_bottom          ;; [2/3] Current Y is below the top.
    ;; A matching Y extends the horizontal top-row interval.
    jr      z,find_bounds_not_new_top           ;; [2/3] Current Y equals the top.
    ;; This vertex is above every previous vertex, so replace all top values.
    ld      a,b                                 ;; [1] Select the new top Y.
    ld      (geomTopY),a                        ;; [4] Lower the top bound.
    ld      a,(geomIndex)                       ;; [4] Load the new top vertex index.
    ld      (topIndex),a                        ;; [4] Preserve the top vertex.
    ld      hl,(geomCurrentX)                   ;; [5] Load this vertex X.
    ld      (topMinX),hl                        ;; [5] Reset top-row minimum X.
    ld      (topMaxX),hl                        ;; [5] Reset top-row maximum X.
    jr      find_bounds_check_bottom            ;; [3] Continue with bottom-Y check.

find_bounds_not_new_top:
    jr      nz,find_bounds_check_bottom         ;; [2/3] Skip equal-top handling if Y differs.

    ;; Compare the current X against the top-row minimum.
    ld      hl,(topMinX)                        ;; [5] Load top-row minimum X.
    ld      de,(geomCurrentX)                   ;; [6] Load current X.
    call    cpct_compareSigned16_asm            ;; [5] Compare the signed X values.
    jr      c,find_bounds_check_top_max         ;; [2/3] Current X is not lower.
    jr      z,find_bounds_check_top_max         ;; [2/3] Current X equals the minimum.
    ld      hl,(geomCurrentX)                   ;; [5] Load the lower X.
    ld      (topMinX),hl                        ;; [5] Replace top-row minimum X.

find_bounds_check_top_max:
    ;; Compare the current X against the top-row maximum.
    ld      hl,(topMaxX)                        ;; [5] Load top-row maximum X.
    ld      de,(geomCurrentX)                   ;; [6] Load current X.
    call    cpct_compareSigned16_asm            ;; [5] Compare the signed X values.
    jr      nc,find_bounds_check_bottom         ;; [2/3] Current X is not higher.
    ld      hl,(geomCurrentX)                   ;; [5] Load the higher X.
    ld      (topMaxX),hl                        ;; [5] Replace top-row maximum X.

find_bounds_check_bottom:
    ;; Update the bottom Y only when this vertex is lower.
    ld      a,(scanY)                           ;; [4] Reload current Y.
    ld      b,a                                 ;; [1] Preserve current Y.
    ld      a,(geomBottomY)                     ;; [4] Load current bottom Y.
    cp      b                                   ;; [1] Compare bottom Y with current Y.
    jr      nc,find_bounds_next                 ;; [2/3] Current Y is not below bottom.
    ld      a,b                                 ;; [1] Select the new bottom Y.
    ld      (geomBottomY),a                     ;; [4] Raise the bottom bound.

find_bounds_next:
    ;; Continue scanning with the next vertex index.
    ld      a,(geomIndex)                       ;; [4] Load current vertex index.
    inc     a                                   ;; [1] Advance to the next vertex.
    ld      (geomIndex),a                       ;; [4] Store the next vertex index.
    jp      find_bounds_loop                    ;; [3] Inspect the next vertex.

;; Initialize each contour chain by skipping the horizontal top edge.
setupForwardChain:
    ;; Start from the top vertex and seek clockwise to a non-horizontal edge.
    ld      a,(topIndex)                        ;; [4] Load the top vertex index.
    ld      (forwardVertex),a                   ;; [4] Initialize forward chain position.
setup_forward_seek:
    ld      a,(forwardVertex)                   ;; [4] Load forward chain position.
    call    nextForwardIndex                    ;; [5] Get next clockwise vertex.
    ld      (candidateIndex),a                  ;; [4] Preserve the candidate index.
    call    getPoint                            ;; [5] Resolve candidate vertex address.
    inc     hl                                  ;; [2] Advance to candidate X high byte.
    inc     hl                                  ;; [2] Advance to candidate Y low byte.
    ld      a,(hl)                              ;; [2] Load candidate Y.
    ld      b,a                                 ;; [1] Preserve candidate Y.
    ld      a,(geomTopY)                        ;; [4] Load top Y.
    cp      b                                   ;; [1] Compare candidate Y with top Y.
    ;; Skip vertices that continue a horizontal top edge.
    jr      z,setup_forward_skip                ;; [2/3] This candidate continues the top row.

    ;; The first candidate that leaves the top row defines the initial edge.
    ld      a,(forwardVertex)                   ;; [4] Load forward edge start index.
    ld      (chainStart),a                      ;; [4] Set shared edge start.
    ld      a,(candidateIndex)                  ;; [4] Load forward edge end index.
    ld      (chainEnd),a                        ;; [4] Set shared edge end.
    ld      (forwardVertex),a                   ;; [4] Advance forward chain position.
    ld      hl,#edgeForward                     ;; [3] Select forward edge state.
    ld      (setupState),hl                     ;; [5] Pass state pointer to setup.
    ld      hl,#forwardEndY                     ;; [3] Select forward end-Y field.
    ld      (setupEndY),hl                      ;; [5] Pass end-Y pointer to setup.
    call    polygonSetupEdge                    ;; [5] Initialize forward edge geometry.
    ld      a,#1                                ;; [2] Select active edge state.
    ld      (forwardActive),a                   ;; [4] Mark forward edge active.
    ret                                         ;; [3] Return to the main routine.

setup_forward_skip:
    ;; Move the forward search past this top-row vertex.
    ld      a,(candidateIndex)                  ;; [4] Load horizontal-edge candidate.
    ld      (forwardVertex),a                   ;; [4] Move forward chain past it.
    jr      setup_forward_seek                  ;; [3] Seek the next candidate.

setupBackwardChain:
    ;; Start from the top vertex and seek counter-clockwise to an edge.
    ld      a,(topIndex)                        ;; [4] Load the top vertex index.
    ld      (backwardVertex),a                  ;; [4] Initialize backward chain position.
setup_backward_seek:
    ld      a,(backwardVertex)                  ;; [4] Load backward chain position.
    call    nextBackwardIndex                   ;; [5] Get next counter-clockwise vertex.
    ld      (candidateIndex),a                  ;; [4] Preserve candidate index.
    call    getPoint                            ;; [5] Resolve candidate vertex address.
    inc     hl                                  ;; [2] Advance to candidate X high byte.
    inc     hl                                  ;; [2] Advance to candidate Y low byte.
    ld      a,(hl)                              ;; [2] Load candidate Y.
    ld      b,a                                 ;; [1] Preserve candidate Y.
    ld      a,(geomTopY)                        ;; [4] Load top Y.
    cp      b                                   ;; [1] Compare candidate Y with top Y.
    ;; Skip vertices that continue a horizontal top edge.
    jr      z,setup_backward_skip               ;; [2/3] This candidate continues the top row.

    ;; The first candidate that leaves the top row defines the initial edge.
    ld      a,(backwardVertex)                  ;; [4] Load backward edge start index.
    ld      (chainStart),a                      ;; [4] Set shared edge start.
    ld      a,(candidateIndex)                  ;; [4] Load backward edge end index.
    ld      (chainEnd),a                        ;; [4] Set shared edge end.
    ld      (backwardVertex),a                  ;; [4] Advance backward chain position.
    ld      hl,#edgeBackward                    ;; [3] Select backward edge state.
    ld      (setupState),hl                     ;; [5] Pass state pointer to setup.
    ld      hl,#backwardEndY                    ;; [3] Select backward end-Y field.
    ld      (setupEndY),hl                      ;; [5] Pass end-Y pointer to setup.
    call    polygonSetupEdge                    ;; [5] Initialize backward edge geometry.
    ld      a,#1                                ;; [2] Select active edge state.
    ld      (backwardActive),a                  ;; [4] Mark backward edge active.
    ret                                         ;; [3] Return to the main routine.

setup_backward_skip:
    ;; Move the backward search past this top-row vertex.
    ld      a,(candidateIndex)                  ;; [4] Load horizontal-edge candidate.
    ld      (backwardVertex),a                  ;; [4] Move backward chain past it.
    jr      setup_backward_seek                 ;; [3] Seek the next candidate.

;; Switch to the next non-horizontal edge when this chain reaches a vertex.
updateForwardChain:
    ;; No action is needed if this chain already ended.
    ld      a,(forwardActive)                   ;; [4] Load forward active state.
    or      a                                   ;; [1] Test whether it is zero.
    ret     z                                   ;; [2/4] Return if the chain is inactive.
    ld      a,(forwardEndY)                     ;; [4] Load forward edge end Y.
    ld      b,a                                 ;; [1] Preserve end Y.
    ld      a,(geomCurrentY)                    ;; [4] Load current scanline.
    cp      b                                   ;; [1] Compare current Y with edge end Y.
    ;; Keep the existing edge until the current row reaches its end Y.
    ret     nz                                  ;; [2/4] Keep the edge until current Y reaches end Y.

update_forward_seek:
    ld      a,(forwardVertex)                   ;; [4] Load reached forward vertex.
    call    nextForwardIndex                    ;; [5] Get next clockwise candidate.
    ld      (candidateIndex),a                  ;; [4] Preserve candidate index.
    call    getPoint                            ;; [5] Resolve candidate vertex address.
    inc     hl                                  ;; [2] Advance to candidate X high byte.
    inc     hl                                  ;; [2] Advance to candidate Y low byte.
    ld      a,(hl)                              ;; [2] Load candidate Y.
    ld      b,a                                 ;; [1] Preserve candidate Y.
    ld      a,(geomCurrentY)                    ;; [4] Load current Y.
    cp      b                                   ;; [1] Compare current Y with candidate Y.
    ;; Cross a horizontal segment at the vertex by updating its X coordinate.
    jr      z,update_forward_horizontal         ;; [2/3] Candidate is on this horizontal segment.
    ;; Candidate Y is below the current row, so it starts the next edge.
    jr      c,update_forward_next_edge          ;; [2/3] Candidate starts the next forward edge.

    ;; Candidate Y is beyond bottom Y, therefore this chain becomes inactive.
    xor     a                                   ;; [1] Select inactive chain state.
    ld      (forwardActive),a                   ;; [4] Mark forward chain inactive.
    ret                                         ;; [3] Finish forward-chain update.

update_forward_horizontal:
    ;; Set this vertex as the new chain position.
    ld      a,(candidateIndex)                  ;; [4] Load horizontal candidate index.
    ld      (forwardVertex),a                   ;; [4] Move forward vertex past it.
    call    getPoint                            ;; [5] Resolve candidate vertex address.
    ld      e,(hl)                              ;; [2] Load candidate X low byte.
    inc     hl                                  ;; [2] Advance to X high byte.
    ld      d,(hl)                              ;; [2] Load candidate X high byte.
    ld      (edgeForward),de                    ;; [6] Set current forward edge X.
    ;; Continue seeking until a non-horizontal edge is found.
    jr      update_forward_seek                 ;; [3] Continue searching for a non-horizontal edge.

update_forward_next_edge:
    ;; Initialize the forward edge from the reached vertex to the candidate.
    ld      a,(forwardVertex)                   ;; [4] Load reached forward vertex.
    ld      (chainStart),a                      ;; [4] Set shared edge start.
    ld      a,(candidateIndex)                  ;; [4] Load next forward vertex.
    ld      (chainEnd),a                        ;; [4] Set shared edge end.
    ld      (forwardVertex),a                   ;; [4] Advance forward chain position.
    ld      hl,#edgeForward                     ;; [3] Select forward edge state.
    ld      (setupState),hl                     ;; [5] Pass state pointer to setup.
    ld      hl,#forwardEndY                     ;; [3] Select forward end-Y field.
    ld      (setupEndY),hl                      ;; [5] Pass end-Y pointer to setup.
    jp      polygonSetupEdge                    ;; [3] Initialize the next forward edge.

updateBackwardChain:
    ;; No action is needed if this chain already ended.
    ld      a,(backwardActive)                  ;; [4] Load backward active state.
    or      a                                   ;; [1] Test whether it is zero.
    ret     z                                   ;; [2/4] Return if the chain is inactive.
    ld      a,(backwardEndY)                    ;; [4] Load backward edge end Y.
    ld      b,a                                 ;; [1] Preserve end Y.
    ld      a,(geomCurrentY)                    ;; [4] Load current scanline.
    cp      b                                   ;; [1] Compare current Y with edge end Y.
    ;; Keep the existing edge until the current row reaches its end Y.
    ret     nz                                  ;; [2/4] Keep edge until current Y reaches end Y.

update_backward_seek:
    ld      a,(backwardVertex)                  ;; [4] Load reached backward vertex.
    call    nextBackwardIndex                   ;; [5] Get next counter-clockwise candidate.
    ld      (candidateIndex),a                  ;; [4] Preserve candidate index.
    call    getPoint                            ;; [5] Resolve candidate vertex address.
    inc     hl                                  ;; [2] Advance to candidate X high byte.
    inc     hl                                  ;; [2] Advance to candidate Y low byte.
    ld      a,(hl)                              ;; [2] Load candidate Y.
    ld      b,a                                 ;; [1] Preserve candidate Y.
    ld      a,(geomCurrentY)                    ;; [4] Load current Y.
    cp      b                                   ;; [1] Compare current Y with candidate Y.
    ;; Cross a horizontal segment at the vertex by updating its X coordinate.
    jr      z,update_backward_horizontal        ;; [2/3] Candidate is on this horizontal segment.
    ;; Candidate Y is below the current row, so it starts the next edge.
    jr      c,update_backward_next_edge         ;; [2/3] Candidate starts the next backward edge.

    ;; Candidate Y is beyond bottom Y, therefore this chain becomes inactive.
    xor     a                                   ;; [1] Select inactive chain state.
    ld      (backwardActive),a                  ;; [4] Mark backward chain inactive.
    ret                                         ;; [3] Finish backward-chain update.

update_backward_horizontal:
    ;; Set this vertex as the new chain position.
    ld      a,(candidateIndex)                  ;; [4] Load horizontal candidate index.
    ld      (backwardVertex),a                  ;; [4] Move backward vertex past it.
    call    getPoint                            ;; [5] Resolve candidate vertex address.
    ld      e,(hl)                              ;; [2] Load candidate X low byte.
    inc     hl                                  ;; [2] Advance to X high byte.
    ld      d,(hl)                              ;; [2] Load candidate X high byte.
    ld      (edgeBackward),de                   ;; [6] Set current backward edge X.
    ;; Continue seeking until a non-horizontal edge is found.
    jr      update_backward_seek                ;; [3] Continue searching for a non-horizontal edge.

update_backward_next_edge:
    ;; Initialize the backward edge from the reached vertex to the candidate.
    ld      a,(backwardVertex)                  ;; [4] Load reached backward vertex.
    ld      (chainStart),a                      ;; [4] Set shared edge start.
    ld      a,(candidateIndex)                  ;; [4] Load next backward vertex.
    ld      (chainEnd),a                        ;; [4] Set shared edge end.
    ld      (backwardVertex),a                  ;; [4] Advance backward chain position.
    ld      hl,#edgeBackward                    ;; [3] Select backward edge state.
    ld      (setupState),hl                     ;; [5] Pass state pointer to setup.
    ld      hl,#backwardEndY                    ;; [3] Select backward end-Y field.
    ld      (setupEndY),hl                      ;; [5] Pass end-Y pointer to setup.
    jp      polygonSetupEdge                    ;; [3] Initialize the next backward edge.

;; Set up a Bresenham-style X edge from chainStart to chainEnd.
polygonSetupEdge:
    ;; Select whether this state belongs to the forward or backward contour.
    ld      hl,(setupState)                     ;; [5] Load selected edge-state pointer.
    ld      (edgeOut),hl                        ;; [5] Preserve it for setup writes.

    ;; Read the start vertex X/Y pair.
    ld      a,(chainStart)                      ;; [4] Load edge start vertex index.
    call    getPoint                            ;; [5] Resolve start vertex address.
    ld      e,(hl)                              ;; [2] Load start X low byte.
    inc     hl                                  ;; [2] Advance to start X high byte.
    ld      d,(hl)                              ;; [2] Load start X high byte.
    ld      (geomCurrentX),de                   ;; [6] Initialize edge current X.
    inc     hl                                  ;; [2] Advance to start Y low byte.
    ld      a,(hl)                              ;; [2] Load start Y.
    ld      (geomStartY),a                      ;; [4] Store start Y.

    ;; Read the end vertex X/Y pair.
    ld      a,(chainEnd)                        ;; [4] Load edge end vertex index.
    call    getPoint                            ;; [5] Resolve end vertex address.
    ld      e,(hl)                              ;; [2] Load end X low byte.
    inc     hl                                  ;; [2] Advance to end X high byte.
    ld      d,(hl)                              ;; [2] Load end X high byte.
    ld      (geomEndX),de                       ;; [6] Store end X.
    inc     hl                                  ;; [2] Advance to end Y low byte.
    ld      a,(hl)                              ;; [2] Load end Y.
    ld      (geomEndY),a                        ;; [4] Store end Y.

    ;; Calculate signed endX - startX to determine absolute delta and direction.
    ld      hl,(geomEndX)                       ;; [5] Load end X.
    ld      de,(geomCurrentX)                   ;; [6] Load start X.
    or      a                                   ;; [1] Clear carry for signed subtraction.
    sbc     hl,de                               ;; [4] Calculate endX minus startX.
    ld      a,h                                 ;; [1] Inspect the signed result high byte.
    and     #0x80                               ;; [2] Test the sign bit.
    jr      z,setup_positive_x                  ;; [2/3] Edge moves right or is vertical.
    ld      a,#0xFF                             ;; [2] Select leftward X step.
    ld      (geomStep),a                        ;; [4] Store signed step -1.
    xor     a                                   ;; [1] Clear A for 16-bit negation.
    sub     l                                   ;; [1] Negate low byte.
    ld      l,a                                 ;; [1] Store negated low byte.
    ld      a,#0                                ;; [2] Prepare high-byte negation.
    sbc     a,h                                 ;; [1] Negate high byte with carry.
    ld      h,a                                 ;; [1] Store absolute X high byte.
    jr      setup_store_dx                      ;; [3] Store the absolute X delta.
setup_positive_x:
    ;; Positive or zero X delta moves the edge to the right.
    ld      a,#1                                ;; [2] Select rightward X step.
    ld      (geomStep),a                        ;; [4] Store signed step +1.
setup_store_dx:
    ;; Store the absolute X distance used by the Bresenham loop.
    ld      (geomDeltaX),hl                     ;; [5] Store absolute X delta.

    ;; Calculate the positive Y distance to the edge endpoint.
    ld      a,(geomEndY)                        ;; [4] Load end Y.
    ld      l,a                                 ;; [1] Place end Y in HL low byte.
    ld      h,#0                                ;; [2] Clear HL high byte.
    ld      a,(geomStartY)                      ;; [4] Load start Y.
    ld      e,a                                 ;; [1] Place start Y in DE low byte.
    ld      d,#0                                ;; [2] Clear DE high byte.
    or      a                                   ;; [1] Clear carry for unsigned subtraction.
    sbc     hl,de                               ;; [4] Calculate endY minus startY.
    ld      (geomDeltaY),hl                     ;; [5] Store positive Y delta.

    ;; Reset the error accumulator and write the complete edge state.
    ld      hl,#0                               ;; [3] Select zero error.
    ld      (geomError),hl                      ;; [5] Reset Bresenham error.
    ld      hl,(edgeOut)                        ;; [5] Point to edge state offset zero.
    ld      de,(geomCurrentX)                   ;; [6] Load initial current X.
    ld      (hl),e                              ;; [2] Store current X low byte.
    inc     hl                                  ;; [2] Advance to current X high byte.
    ld      (hl),d                              ;; [2] Store current X high byte.
    inc     hl                                  ;; [2] Advance to absolute X delta.
    ld      de,(geomDeltaX)                     ;; [6] Load absolute X delta.
    ld      (hl),e                              ;; [2] Store delta X low byte.
    inc     hl                                  ;; [2] Advance to delta X high byte.
    ld      (hl),d                              ;; [2] Store delta X high byte.
    inc     hl                                  ;; [2] Advance to Y delta.
    ld      de,(geomDeltaY)                     ;; [6] Load Y delta.
    ld      (hl),e                              ;; [2] Store delta Y low byte.
    inc     hl                                  ;; [2] Advance to delta Y high byte.
    ld      (hl),d                              ;; [2] Store delta Y high byte.
    inc     hl                                  ;; [2] Advance to signed X step.
    ld      a,(geomStep)                        ;; [4] Load signed X step.
    ld      (hl),a                              ;; [2] Store X step.
    inc     hl                                  ;; [2] Advance to error low byte.
    ld      de,(geomError)                      ;; [6] Load reset error.
    ld      (hl),e                              ;; [2] Store error low byte.
    inc     hl                                  ;; [2] Advance to error high byte.
    ld      (hl),d                              ;; [2] Store error high byte.
    ld      hl,(setupEndY)                      ;; [5] Point to chain end-Y field.
    ld      a,(geomEndY)                        ;; [4] Load edge end Y.
    ;; Record the endpoint Y so chain update can detect edge completion.
    ld      (hl),a                              ;; [2] Store edge end Y.
    ret                                         ;; [3] Return with the edge fully initialized.

;; A = point index; returns HL = pointer to its (x,y) words.
getPoint:
    ;; Four bytes per vertex: two bytes of X followed by two bytes of Y.
    ld      l,a                                 ;; [1] Place index in HL low byte.
    ld      h,#0                                ;; [2] Clear HL high byte.
    add     hl,hl                               ;; [3] Multiply index by 2.
    add     hl,hl                               ;; [3] Multiply again for a 4-byte vertex.
    ld      de,(geomInputPtr)                   ;; [6] Load input-list base address.
    add     hl,de                               ;; [3] Resolve absolute vertex address.
    ret                                         ;; [3] Return HL at vertex X.

;; A = index; returns the next/previous wrapped vertex index.
nextForwardIndex:
    ;; Add one and wrap to vertex zero after the final vertex.
    inc     a                                   ;; [1] Increment clockwise vertex index.
    ld      b,a                                 ;; [1] Preserve incremented index.
    ld      a,(geomNbInput)                     ;; [4] Load the vertex count.
    cp      b                                   ;; [1] Test whether index wrapped.
    ld      a,b                                 ;; [1] Restore incremented index.
    ret     nz                                  ;; [2/4] Return if it is still in range.
    xor     a                                   ;; [1] Select wrapped index zero.
    ret                                         ;; [3] Return wrapped vertex index.

nextBackwardIndex:
    ;; Zero wraps to the final vertex; every other index decrements.
    or      a                                   ;; [1] Test whether index is zero.
    jr      z,next_backward_wrap                ;; [2/3] Wrap to the final vertex.
    dec     a                                   ;; [1] Decrement counter-clockwise index.
    ret                                         ;; [3] Return the previous vertex.
next_backward_wrap:
    ld      a,(geomNbInput)                     ;; [4] Load the vertex count.
    dec     a                                   ;; [1] Calculate final vertex index.
    ret                                         ;; [3] Return the wrapped index.

;; Advance the current edge by one scanline.
polygonAdvanceEdge:
    ;; Save the edge-state pointer and reload its absolute distances.
    ld      (edgeOut),hl                        ;; [5] Preserve edge-state pointer.
    inc     hl                                  ;; [2] Advance past current X low byte.
    inc     hl                                  ;; [2] Advance past current X high byte.
    ld      c,(hl)                              ;; [2] Load delta X low byte.
    inc     hl                                  ;; [2] Advance to delta X high byte.
    ld      b,(hl)                              ;; [2] Load delta X high byte.
    ld      (geomDeltaX),bc                     ;; [6] Store absolute X delta.
    inc     hl                                  ;; [2] Advance to delta Y low byte.
    ld      e,(hl)                              ;; [2] Load delta Y low byte.
    inc     hl                                  ;; [2] Advance to delta Y high byte.
    ld      d,(hl)                              ;; [2] Load delta Y high byte.
    ld      (geomDeltaY),de                     ;; [6] Store Y delta.
    inc     hl                                  ;; [2] Advance past signed X step low byte.
    inc     hl                                  ;; [2] Advance to error low byte.
    ld      a,(hl)                              ;; [2] Load error low byte.
    ld      (geomError),a                       ;; [4] Store error low byte.
    inc     hl                                  ;; [2] Advance to error high byte.
    ld      a,(hl)                              ;; [2] Load error high byte.
    ld      (geomError+1),a                     ;; [4] Store error high byte.

advance_edge_loop:
    ;; threshold = deltaY - error.
    ld      hl,(geomDeltaY)                     ;; [5] Load Y delta.
    ld      de,(geomError)                      ;; [6] Load current Bresenham error.
    or      a                                   ;; [1] Clear carry for subtraction.
    sbc     hl,de                               ;; [4] Calculate threshold minus error.
    ld      (geomThreshold),hl                  ;; [5] Store threshold.
    ld      hl,(geomDeltaX)                     ;; [5] Reload absolute X delta.
    ld      de,(geomThreshold)                  ;; [6] Reload threshold.
    or      a                                   ;; [1] Clear carry for subtraction.
    sbc     hl,de                               ;; [4] Compare remaining X and threshold.
    ;; If deltaX < threshold, only the error accumulator advances.
    jr      c,advance_error_only                ;; [2/3] No X step is required for this row.

    ;; The major-axis threshold is crossed: consume it and adjust X.
    ld      (geomDeltaX),hl                     ;; [5] Store reduced X delta.
    ld      hl,(edgeOut)                        ;; [5] Point to current edge X.
    ld      a,(hl)                              ;; [2] Load current X low byte.
    ld      e,a                                 ;; [1] Preserve X low byte.
    inc     hl                                  ;; [2] Advance to X high byte.
    ld      a,(hl)                              ;; [2] Load current X high byte.
    ld      d,a                                 ;; [1] Preserve X high byte.
    ;; The signed X-step field is at offset 6 in the edge state.
    inc     hl                                  ;; [2] Advance past delta X low byte.
    inc     hl                                  ;; [2] Advance past delta X high byte.
    inc     hl                                  ;; [2] Advance past delta Y low byte.
    inc     hl                                  ;; [2] Advance past delta Y high byte.
    inc     hl                                  ;; [2] Advance to signed X step.
    ld      a,(hl)                              ;; [2] Load signed X step.
    cp      #1                                  ;; [2] Test whether step is right.
    jr      z,advance_x_right                   ;; [2/3] Increment X for rightward edge.
    dec     de                                  ;; [2] Decrement X for leftward edge.
    jr      advance_x_store                     ;; [3] Store adjusted X.
advance_x_right:
    inc     de                                  ;; [2] Increment X for rightward edge.
advance_x_store:
    ;; Store the new current X and reset the error accumulator.
    ld      hl,(edgeOut)                        ;; [5] Point to edge current X.
    ld      (hl),e                              ;; [2] Store adjusted X low byte.
    inc     hl                                  ;; [2] Advance to X high byte.
    ld      (hl),d                              ;; [2] Store adjusted X high byte.
    ld      hl,#0                               ;; [3] Select reset error.
    ld      (geomError),hl                      ;; [5] Reset Bresenham error.
    ;; Continue until this edge's one-row Bresenham decision is resolved.
    jp      advance_edge_loop                   ;; [3] Continue same-row edge advancement.

advance_error_only:
    ;; Accumulate deltaX as the error for this row.
    ld      hl,(geomError)                      ;; [5] Load current error.
    ld      de,(geomDeltaX)                     ;; [6] Load absolute X delta.
    add     hl,de                               ;; [3] Accumulate X delta into error.
    ld      (geomError),hl                      ;; [5] Store updated error workspace.
    ld      hl,(edgeOut)                        ;; [5] Point to edge state.
    ld      de,#7                               ;; [3] Select error-offset displacement.
    add     hl,de                               ;; [3] Point to edge error field.
    ld      de,(geomError)                      ;; [6] Load updated error.
    ;; Store the updated error accumulator in the edge state.
    ld      (hl),e                              ;; [2] Store error low byte.
    inc     hl                                  ;; [2] Advance to error high byte.
    ld      (hl),d                              ;; [2] Store error high byte.
    ret                                         ;; [3] Finish edge advancement for this row.

drawSpan:
    ;; Pass the unordered horizontal endpoints to the Bayer line renderer.
    ld      hl,(spanX0)                         ;; [5] Load left/right span endpoint X0.
    ld      de,(spanX1)                         ;; [6] Load the opposite span endpoint X1.
    ld      a,(geomCurrentY)                    ;; [4] Load current Bayer Y.
    ld      bc,(bayer_screenY)                  ;; [6] Load current screen-row base.
    call    cpct_bayerDrawHLineM1_asm           ;; [5] Draw this polygon scanline.
    ret                                         ;; [3] Return to the row loop.

.area _DATA
scanY:            .ds 1                         ;; (1) Y coordinate of the vertex being scanned
topIndex:         .ds 1                         ;; (1) Index of the topmost vertex
topMinX:          .ds 2                         ;; (2) Minimum X among vertices on the top scanline
topMaxX:          .ds 2                         ;; (2) Maximum X among vertices on the top scanline
spanX0:           .ds 2                         ;; (2) Left X endpoint of the span being drawn
spanX1:           .ds 2                         ;; (2) Right X endpoint of the span being drawn
forwardVertex:    .ds 1                         ;; (1) Current vertex index on the forward chain
backwardVertex:   .ds 1                         ;; (1) Current vertex index on the backward chain
candidateIndex:   .ds 1                         ;; (1) Candidate vertex index while advancing a chain
chainStart:       .ds 1                         ;; (1) First vertex index to consider on a chain
chainEnd:         .ds 1                         ;; (1) Last vertex index to consider on a chain
forwardActive:    .ds 1                         ;; (1) Nonzero while the forward edge is active
backwardActive:   .ds 1                         ;; (1) Nonzero while the backward edge is active
forwardEndY:      .ds 1                         ;; (1) End scanline of the forward edge
backwardEndY:     .ds 1                         ;; (1) End scanline of the backward edge
setupState:       .ds 2                         ;; (2) Pointer to the edge record currently being set up
setupEndY:        .ds 2                         ;; (2) End Y coordinate for the edge being set up
;; Edge record layout (9 bytes):
;; +0..1  Current X coordinate (i16)
;; +2..3  Absolute X distance (i16)
;; +4..5  Y distance (i16)
;; +6     X step: +1 or -1 (i8)
;; +7..8  Bresenham error accumulator (i16)
edgeForward:      .ds 9                         ;; (9) Forward-edge state using the layout above
edgeBackward:     .ds 9                         ;; (9) Backward-edge state using the layout above
edgeOut:          .ds 2                         ;; (2) Pointer to the edge record being written
