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
//------------------------------------------------------------------------------

#include <cpctelera.h>

//------------------------------------------------------------------------------
// The goal of this example is to demonstrate the how bayer dithering can be applied 
// to Mode 1 graphisms.
//------------------------------------------------------------------------------

// static void advanceBayerTriangleEdge (i16 *x, i16 dx, i16 dy, i16 xStep, i16 *error)
// {
//     while (dx >= dy - *error)
//     {
//         *x += xStep;
//         dx -= dy - *error;
//         *error = 0;
//     }
//     *error += dx;
// }

// static void drawBayerTriangleLine (i16 x0, i16 x1, i16 y)
// {
//     if (y < 0 || y > 199 || (x0 < 0 && x1 < 0) || (x0 > 319 && x1 > 319))
//         return;

//     if (x0 < 0)
//         x0 = 0;
//     else if (x0 > 319)
//         x0 = 319;
//     if (x1 < 0)
//         x1 = 0;
//     else if (x1 > 319)
//         x1 = 319;

//     // To change into a drawBayerHorizontalLine when available
//     cpct_drawBayerBoxM1 ((u16)x0, (u16)x1, (u8)y, (u8)y);
// }

// void cdrawBayerTriangle (i16 *Points)
// {
//     i16 tmpPts[6];
//     i16 *tmpPtr[3];
//     i16 *swap;
//     i16 topY, middleY, bottomY, visibleBottom, y;
//     i16 longX, longDX, longDY, longStepX;
//     i16 shortX, shortDX, shortDY, shortStepX;
//     i16 longError, shortError;

//     // Work on a local copy and sort vertex pointers by Y, leaving Points unchanged.
//     cpct_memcpy (tmpPts, Points, sizeof(tmpPts));
//     tmpPtr[0] = &tmpPts[0];
//     tmpPtr[1] = &tmpPts[2];
//     tmpPtr[2] = &tmpPts[4];

//     if (tmpPtr[0][1] > tmpPtr[1][1])
//     {
//         swap = tmpPtr[0];
//         tmpPtr[0] = tmpPtr[1];
//         tmpPtr[1] = swap;
//     }
//     if (tmpPtr[1][1] > tmpPtr[2][1])
//     {
//         swap = tmpPtr[1];
//         tmpPtr[1] = tmpPtr[2];
//         tmpPtr[2] = swap;
//     }
//     if (tmpPtr[0][1] > tmpPtr[1][1])
//     {
//         swap = tmpPtr[0];
//         tmpPtr[0] = tmpPtr[1];
//         tmpPtr[1] = swap;
//     }

//     // Check impossible draw first
//     topY = tmpPtr[0][1];
//     middleY = tmpPtr[1][1];
//     bottomY = tmpPtr[2][1];
//     if (topY > 199 || bottomY < 0)
//         return;
//     visibleBottom = bottomY > 199 ? 199 : bottomY;

//     // A flat triangle collapses to one horizontal span. Getting min and max X and draw a line
//     // if (topY == bottomY)
//     // {
//     //     i16 left = tmpPtr[0][0];
//     //     i16 right = tmpPtr[0][0];
// // 
//     //     if (tmpPtr[1][0] < left)
//     //         left = tmpPtr[1][0];
//     //     if (tmpPtr[2][0] < left)
//     //         left = tmpPtr[2][0];
//     //     if (tmpPtr[1][0] > right)
//     //         right = tmpPtr[1][0];
//     //     if (tmpPtr[2][0] > right)
//     //         right = tmpPtr[2][0];
//     //     drawBayerTriangleLine (left, right, topY);
//     //     return;
//     // }

//     // Follow the top-to-bottom edge alongside the current half-edge, then draw
//     // the clipped span on each row.
//     longX = tmpPtr[0][0];
//     longDX = tmpPtr[2][0] - tmpPtr[0][0];
//     longStepX = longDX < 0 ? -1 : 1;
//     if (longDX < 0)
//         longDX = -longDX;
//     longDY = bottomY - topY;
//     longError = 0;

//     shortX = tmpPtr[0][0];
//     shortDX = tmpPtr[1][0] - tmpPtr[0][0];
//     shortStepX = shortDX < 0 ? -1 : 1;
//     if (shortDX < 0)
//         shortDX = -shortDX;
//     shortDY = middleY - topY;
//     shortError = 0;

//     for (y = topY; y <= visibleBottom; ++y)
//     {
//         if (y == middleY)
//         {
//             shortX = tmpPtr[1][0];
//             shortDX = tmpPtr[2][0] - tmpPtr[1][0];
//             shortStepX = shortDX < 0 ? -1 : 1;
//             if (shortDX < 0)
//                 shortDX = -shortDX;
//             shortDY = bottomY - middleY;
//             shortError = 0;
//         }

//         drawBayerTriangleLine (longX, shortX, y);
//         if (y == bottomY)
//             break;

//         advanceBayerTriangleEdge (&longX, longDX, longDY, longStepX, &longError);
//         advanceBayerTriangleEdge (&shortX, shortDX, shortDY, shortStepX, &shortError);
//     }
// }


void rotateIntensityAndPens (u8 *intensity, u8 *pen1, u8 *pen2)
{
    (*intensity) ++;
    (*intensity) &= 0x0F;
    if (! *intensity)
    {
        (*pen1)++;
        (*pen1) &= 0x03;
        (*pen2)++;
        (*pen2) &= 0x03;
    }
}

void loopScreen (u8 intensity, u8 pen1, u8 pen2)
{
    u8 y0 = 0;
    while (y0 < 200)
    {
        cpct_setBayerMatrixM1 ((u8*)0xC000,intensity,pen1,pen2);
        cpct_drawBayerBoxM1 (  0, 319, y0, y0 + 9);
        rotateIntensityAndPens (&intensity,&pen1,&pen2);
        y0+=10;
    }
}

void randomBox (void)
{
    u16 x0, x1;
    u8  y0, y1;

    x0 = cpct_getRandom_mxor_u16() & 0x1FF;
    if (x0 > 319) x0 -= 320;
    x1 = cpct_getRandom_mxor_u16() & 0x1FF;
    if (x1 > 319) x1 -= 320;
    y0 = cpct_getRandom_mxor_u8();
    if (y0 > 199) y0 -= 200;
    y1 = cpct_getRandom_mxor_u8();
    if (y1 > 199) y1 -= 200;

    cpct_drawBayerBoxM1 (  x0, x1, y0, y1);
}

void randomTriangle (void)
{
    i16  Points [6];
    i16 * curPt = &Points [0]; 
                        
    for (int i=0 ; i<3; i++)
    {
        *curPt = (i16) (cpct_getRandom_mxor_u16() & 0x1FF) - 96;
        curPt++;
        *curPt = (i16) (cpct_getRandom_mxor_u16() & 0xFF) - 28;
        curPt++;
    }
    cpct_drawBayerTriangleM1 ( Points );
}

// void fixedTriangle (void)
// {
//     i16  Points [6];
//     i16 * curPt = &Points [0]; 
//     *curPt++ = -10;
//     *curPt++ = 20;
//     *curPt++ = 150;
//     *curPt++ = -50;
//     *curPt++ = 50;
//     *curPt = 230;
//     cpct_drawBayerTriangleM1 (Points);
// }


////////////////////////////////////////
// Main demo
void main(void) 
{   
   // Initialisations
   cpct_disableFirmware();
   cpct_setVideoMode(1);
   cpct_setBorder(HW_GREEN);
   cpct_memset_f64(CPCT_VMEM_START, 0x00, 0x4000);  // Clear Mode 1 pattern before switching mode

   u8 baseIntensity = 0, basePen1 = 1, basePen2 = 2;


   do
   {
        do
        {
            loopScreen (baseIntensity, basePen1, basePen2);
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        } 
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        do
        {
            cpct_setBayerMatrixM1 ((u8*)0xC000,baseIntensity,basePen1,basePen2);
            randomBox();
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        } 
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        do
        {
            cpct_setBayerMatrixM1 ((u8*)0xC000,baseIntensity,basePen1,basePen2);
            randomTriangle();
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        }
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
    }while (1);
}
