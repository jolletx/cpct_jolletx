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

////////////////////////////////////////
// Main demo
void main(void) 
{   
   // Initialisations
   cpct_disableFirmware();
   cpct_memset_f64(CPCT_VMEM_START, 0x00, 0x4000);  // Clear Mode 1 pattern before switching mode

   do
   {
    u8 baseIntensity = 0, basePen1 = 1, basePen2 = 2;;
    do
    {
            u8 intensity = baseIntensity, pen1 = basePen1, pen2 = basePen2;   
            u8 yCoord = 0;
            while (yCoord < 200)
            {
                cpct_setBayerMatrixM1 ((u8*)0xC000,intensity,pen1,pen2);
                cpct_drawBayerBoxM1 (  0, 319, yCoord, yCoord + 9);
                rotateIntensityAndPens (&intensity,&pen1,&pen2);
                yCoord+=10;
            }
            rotateIntensityAndPens (&baseIntensity,&basePen1,&basePen2);
            cpct_scanKeyboard_f();
    } 
    while (!cpct_isAnyKeyPressed());
    do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
    do
    {
        u16 x0, x1;
        u8  y0, y1, intensity, pen1, pen2;

        x0 = cpct_getRandom_mxor_u16() & 0x1FF;
        if (x0 > 319) x0 -= 320;
        x1 = cpct_getRandom_mxor_u16() & 0x1FF;
        if (x1 > 319) x1 -= 320;
        y0 = cpct_getRandom_mxor_u8();
        if (y0 > 199) y0 -= 200;
        y1 = cpct_getRandom_mxor_u8();
        if (y1 > 199) y1 -= 200;
        intensity = cpct_getRandom_mxor_u8() & 0x0F;
        pen1 = cpct_getRandom_mxor_u8() & 0x03;
        do 
        {
            pen2 = cpct_getRandom_mxor_u8() & 0x03;
        } while (pen2 == pen1);
        cpct_setBayerMatrixM1 ((u8*)0xC000,intensity,pen1,pen2);
        cpct_drawBayerBoxM1 (  x0, x1, y0, y1);
        cpct_scanKeyboard_f();
    } 
    while (!cpct_isAnyKeyPressed());
    do { cpct_scanKeyboard_f(); }while (cpct_isAnyKeyPressed());
    }while (1);
}
