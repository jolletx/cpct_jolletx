;; Common implementation for cpct_drawPolygonM0/M1 variants.
;; Define macro CallLineMethod to select compact or fast line routine
;; before including this file.

.area _CODE

;; HL = video memory, DE = point list, C = point count.
;; Each point is stored as (u16 x, u16 y). Draws the closing edge.
    ld (vmem),hl
    ld (pointsBase),de
    ld (currentPoint),de
    ld a,c
    ld (pointCount),a
    cp #3
    jr c,polygon_exit
    ld (polygonRemaining),a

polygon_loop:
    ld hl,(currentPoint)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (x0),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (y0),de

    ld a,(polygonRemaining)
    cp #1
    jr z,nextPointBase
    ld hl,(currentPoint)
    ld bc,#4
    add hl,bc
    jr nextPointStore

nextPointBase:
    ld hl,(pointsBase)

nextPointStore:
    ld (nextPoint),hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (x1),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (y1),de

    ld hl,(y1)
    ld a,l
    ld b,#1
    ld c,a
    push bc
    ld hl,(x1)
    push hl
    ld hl,(y0)
    push hl
    ld hl,(vmem)
    ld de,(x0)
    CallLineMethod

    ld a,(polygonRemaining)
    dec a
    ld (polygonRemaining),a
    jr z,polygon_exit

    ld hl,(nextPoint)
    ld (currentPoint),hl
    jp polygon_loop

polygon_exit:
    ret

.area _DATA
vmem:             .ds 2
pointsBase:       .ds 2
currentPoint:     .ds 2
nextPoint:        .ds 2
pointCount:       .ds 1
polygonRemaining: .ds 1
x0:               .ds 2
y0:               .ds 2
x1:               .ds 2
y1:               .ds 2
