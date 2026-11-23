;; Common implementation for cpct_drawPolygonM0/M1 variants.
;; Define macro CallLineMethod to select compact or fast line routine
;; before including this file.

.globl geomInputPtr
.globl geomNbInput
.globl geomInputColor
.globl geomStartScreen
.globl geomX0
.globl geomY0
.globl geomX1
.globl geomY1
.globl geomCurrentPtr
.globl geomNextPtr

.area _CODE

;; HL = video memory, DE = point list, B = color, C = point count.
;; Each point is stored as (u16 x, u16 y). Draws the closing edge.
    ld (geomStartScreen),hl
    ld (geomInputPtr),de
    ld (geomCurrentPtr),de
    ld a,b
    ld (geomInputColor),a
    ld a,c
    ld (geomNbInput),a
    cp #3
    jr c,polygon_exit

polygon_loop:
    ld hl,(geomCurrentPtr)
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomX0),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomY0),de

    ld a,(geomNbInput)
    cp #1
    jr z,nextPointBase
    ld hl,(geomCurrentPtr)
    ld bc,#4
    add hl,bc
    jr nextPointStore

nextPointBase:
    ld hl,(geomInputPtr)

nextPointStore:
    ld (geomNextPtr),hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomX1),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (geomY1),de

    ld hl,(geomY1)
    ld c,l
    ld a,(geomInputColor)
    ld b,a
    push bc
    ld hl,(geomX1)
    push hl
    ld hl,(geomY0)
    push hl
    ld hl,(geomStartScreen)
    ld de,(geomX0)
    CallLineMethod

    ld a,(geomNbInput)
    dec a
    ld (geomNbInput),a
    jr z,polygon_exit

    ld hl,(geomNextPtr)
    ld (geomCurrentPtr),hl
    jp polygon_loop

polygon_exit:
    ret
