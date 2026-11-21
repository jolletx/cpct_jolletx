//-----------------------------LICENSE NOTICE------------------------------------
//  This file is part of CPCtelera: An Amstrad CPC Game Engine
//  Copyright (C) 2026 Xavier Jollet (@SagaDS)
//  Copyright (C) 2026 ronaldo / Fremos / Cheesetea / ByteRealms (@FranGallegoBR)
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//-------------------------------------------------------------------------------

//#####################################################################
//### MODULE: bayer                                                 ###
//#####################################################################
//### This module contains several functions and routines to manage ###
//### bayer dithering primitives                                    ###
//#####################################################################
//

#ifndef cpct_bayer_H
#define cpct_bayer_H

// Building bayer matrice for draw routines
extern void cpct_setBayerMatrixM1(u8* vmem, u16 intensity, u8 pen1, u8 pen2 ) __z88dk_callee;

// Draw routines
extern void cpct_drawBayerBoxM1 (u16 x0, u16 x1, u8 y0,  u8 y1) __z88dk_callee;
// Clip a signed triangle against cpct_setClipRect's bounds, then fill it.
// Input coordinates must satisfy cpct_clipTriangle's [-16384,16383] range.
extern void cpct_drawBayerClippedTriangleM1 (const i16 *PtArray);
// Draw 3 or more ordered convex vertices, each as an (x, y) u16 pair inside Mode 1.
// Register ABI: HL = PtArray, E = numPoints.
extern void cpct_drawBayerConvexM1 (u16 *PtArray, u16 numPoints) __sdcccall(1);

#endif