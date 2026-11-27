;; Common implementation for cpct_drawPolygonM0/M1 variants.
;; Define macro CallLineMethod to select compact or fast line routine
;; before including this file.

.globl geomStartScreen
.globl geomInputPtr
.globl geomInputColor
.globl geomStep
.globl geomX0
.globl geomY0

.area _CODE

;; HL = video memory, DE = point list, B = pen, C = point count.
;; Each point is stored as (u16 x, u16 y). Draws the closing edge.

    ld      (geomStartScreen),hl                ;; [5] Stores Starting Screen adress
    ld      (geomInputPtr),de                   ;; [6] Stores input Point array adress
    ld      a,b                                 ;; [1] A = Pen
    ld      (geomInputColor),a                  ;; [4] Stores pen value
    ld      a,c                                 ;; [1] A = nbPoints
    ld      (geomStep),a                        ;; [4] Stores last point as step iteration
    cp      #3                                  ;; [2] Checks that polygon has at least 3 points
    jr      c,polygon_exit                      ;; [2/3] Exits if not
    ex      de,hl                               ;; [1] HL = CurrentPtr

polygon_loop:
    ; get current point
    ld      e,(hl)                              ;; [2] Retrieve X value
    inc     hl                                  ;; [2] |
    ld      d,(hl)                              ;; [2] |
    ld      (geomX0),de                         ;; [6] Store start X
    inc     hl                                  ;; [2] Retrieve Y value
    ld      e,(hl)                              ;; [2] |
    inc     hl                                  ;; [2] |
    ld      d,(hl)                              ;; [2] |
    inc     hl                                  ;; [2] Set HL = CurrentPtr + 4 = Next point adress
    ld      (geomY0),de                         ;; [6] Store start Y

    ; get next point
    ld      a,(geomStep)                        ;; [4] Retrieve nbInput 
    cp      #1                                  ;; [2] is it last iteration?
    jr      nz,nextPointStore                   ;; [2/3] No: use next point adress

nextPointBase:
    ld      hl,(geomInputPtr)                   ;; [5] Use First point when current point = last

nextPointStore:
    push    hl                                  ;; [5] Preserve Next point adress
    ld      e,(hl)                              ;; [2] Retrieve X value
    inc     hl                                  ;; [2] |
    ld      d,(hl)                              ;; [2] DE = X1
    inc     hl                                  ;; [2] Retrieve Y value
    ld      c,(hl)                              ;; [2] C = Y1

; Prepare line call
    ld      a,(geomInputColor)                  ;; [4] A = Pen color
    ld      b,a                                 ;; [1] B = Color
    push    bc                                  ;; [4] Push color and Y1
    push    de                                  ;; [4] Push X1
    ld      hl,(geomY0)                         ;; [5] Retrieve Y0
    push    hl                                  ;; [4] Push Y0
    ld      hl,(geomStartScreen)                ;; [5] HL = Screen start adress
    ld      de,(geomX0)                         ;; [6] DE = X0
    CallLineMethod                              ;; [5] Use marco to call correct line API

; Increase step and stop if needed
    pop     hl                                  ;; [5] Retrieve Next point adress
    ld      a,(geomStep)                        ;; [4] A = Iteration
    dec     a                                   ;; [1] A = A - 1
    jr      z,polygon_exit                      ;; [2/3] Stops if finished
    ld      (geomStep),a                        ;; [4] Store new iteration

    jp      polygon_loop                        ;; [3] Continue loop

polygon_exit:
    ret                                         ;; [3] Return
