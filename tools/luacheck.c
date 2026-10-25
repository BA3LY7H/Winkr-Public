/* Syntax-check Lua files against the exact 5.1 VM the client embeds.
 *
 * luaL_loadfile PARSES only -- nothing is executed -- so this is safe to run on
 * mod sources and catches the class of error that otherwise only shows up as an
 * "Execution error" line in game after a /reload.
 *
 * Build:
 *   g++ -O1 -w -I Winkr/vendor/lua/src -o build/luacheck.exe tools/luacheck.c \
 *       $(ls Winkr/vendor/lua/src/*.c | grep -v "lua.c\|luac.c\|print.c") -lm
 */
#include <stdio.h>
#include "lua.h"
#include "lauxlib.h"

int main(int argc, char** argv)
{
    int bad = 0;
    lua_State* L = luaL_newstate();
    for (int i = 1; i < argc; ++i)
    {
        if (luaL_loadfile(L, argv[i]) != 0)
        {
            printf("FAIL %s\n  %s\n", argv[i], lua_tostring(L, -1));
            lua_pop(L, 1);
            bad = 1;
        }
        else
        {
            printf("OK   %s\n", argv[i]);
            lua_pop(L, 1);
        }
    }
    lua_close(L);
    return bad;
}
