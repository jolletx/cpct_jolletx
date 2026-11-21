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
// The goal of this example is to demonstrate how bayer dithering can be applied 
// to Mode 1 graphisms.
//------------------------------------------------------------------------------

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

void randomTriangle (u8 rectClip)
{
    i16  Points [6];
    i16 * curPt = &Points [0]; 

    if (!rectClip)
        cpct_setClipRect (0,0,319,199);
    else
        cpct_setClipRect (40,20,279,179);

    for (int i=0 ; i<3; i++)
    {
        *curPt = (i16) (cpct_getRandom_mxor_u16() & 0x1FF) - 96;
        curPt++;
        *curPt = (i16) (cpct_getRandom_mxor_u16() & 0xFF) - 28;
        curPt++;
    }
    cpct_drawBayerClippedTriangleM1 ( Points );
}

typedef struct
{
    u16 x;
    u16 y;
} BayerPoint;

static i32 crossProduct (const BayerPoint *a, const BayerPoint *b, const BayerPoint *c)
{
    return ((i32)b->x - (i32)a->x) * ((i32)c->y - (i32)a->y)
         - ((i32)b->y - (i32)a->y) * ((i32)c->x - (i32)a->x);
}

void randomConvexGeometry (void)
{
    BayerPoint points[8], hull[16], key;
    u8 pointCount, hullCount, lowerCount, i, j;
    u16 coordinate;

    do
    {
        pointCount = 3 + (cpct_getRandom_mxor_u16() % 6);
        for (i = 0; i < pointCount; ++i)
        {
            coordinate = cpct_getRandom_mxor_u16() & 0x1FF;
            if (coordinate >= 320) coordinate -= 320;
            points[i].x = coordinate;

            coordinate = cpct_getRandom_mxor_u16() & 0xFF;
            if (coordinate >= 200) coordinate -= 200;
            points[i].y = coordinate;
        }

        for (i = 1; i < pointCount; ++i)
        {
            key = points[i];
            j = i;
            while (j > 0 &&
                   (points[j - 1].x > key.x ||
                    (points[j - 1].x == key.x && points[j - 1].y > key.y)))
            {
                points[j] = points[j - 1];
                --j;
            }
            points[j] = key;
        }

        hullCount = 0;
        for (i = 0; i < pointCount; ++i)
        {
            while (hullCount >= 2 &&
                   crossProduct(&hull[hullCount - 2], &hull[hullCount - 1], &points[i]) <= 0)
                --hullCount;
            hull[hullCount++] = points[i];
        }

        lowerCount = hullCount;
        for (i = pointCount - 1; i > 0; --i)
        {
            while (hullCount > lowerCount &&
                   crossProduct(&hull[hullCount - 2], &hull[hullCount - 1], &points[i - 1]) <= 0)
                --hullCount;
            hull[hullCount++] = points[i - 1];
        }
        --hullCount;
    }
    while (hullCount < 3);

    cpct_drawBayerConvexM1 ((u16*)hull, hullCount);
}

////////////////////////////////////////
// Main demo
void main(void) 
{   
   // Initialisations
   cpct_disableFirmware();
   cpct_setVideoMode(1);


   u8 baseIntensity = 0, basePen1 = 1, basePen2 = 2;

   do
   {
        cpct_setBorder(HW_BLUE);
        do
        {
            loopScreen (baseIntensity, basePen1, basePen2);
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        } 
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        cpct_setBorder(HW_MAGENTA);
        do
        {
            cpct_setBayerMatrixM1 ((u8*)0xC000,baseIntensity,basePen1,basePen2);
            randomBox();
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        } 
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        cpct_setBorder(HW_GREEN);
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        do
        {
            cpct_setBayerMatrixM1 ((u8*)0xC000,baseIntensity,basePen1,basePen2);
            randomTriangle(0);
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        }
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        cpct_setBorder(HW_RED);
        do
        {
            cpct_setBayerMatrixM1 ((u8*)0xC000,baseIntensity,basePen1,basePen2);
            randomTriangle(1);
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        }
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
        cpct_setBorder(HW_WHITE);
        do
        {
            cpct_setBayerMatrixM1 ((u8*)0xC000,baseIntensity,basePen1,basePen2);
            randomConvexGeometry();
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
        }
        while (!cpct_isAnyKeyPressed());
        do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
    }while (1);
}
