#include <stdio.h>

#include "m_argv.h"

#include "doomgeneric.h"
#include "w_wad.h"
#include "z_zone.h"

pixel_t* DG_ScreenBuffer = NULL;
static int doomgeneric_running = 0;

void M_FindResponseFile(void);
void D_DoomMain (void);


void doomgeneric_Create(int argc, char **argv)
{
    doomgeneric_Shutdown();

	// save arguments
    myargc = argc;
    myargv = argv;

	M_FindResponseFile();

	DG_ScreenBuffer = malloc(DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4);
    doomgeneric_running = 1;

	DG_Init();

	D_DoomMain ();
}

void doomgeneric_Shutdown(void)
{
    if (!doomgeneric_running)
    {
        return;
    }

    W_Shutdown();
    Z_Shutdown();

    free(DG_ScreenBuffer);
    DG_ScreenBuffer = NULL;
    doomgeneric_running = 0;
}

