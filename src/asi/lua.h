// Lua 5.1 C API inside SaintsRowTheThird_DX11.exe (addresses found by disassembly, see docs/ENGINE.md).
#pragma once
#include <cstddef>

typedef struct lua_State lua_State;
typedef int (__cdecl *lua_CFunction)(lua_State*);

#define LUA_REGISTRYINDEX (-10000)
#define LUA_GLOBALSINDEX  (-10002)
#define LUA_MULTRET       (-1)
#define LUA_TNONE     (-1)
#define LUA_TNIL       0
#define LUA_TBOOLEAN   1
#define LUA_TNUMBER    3
#define LUA_TSTRING    4
#define LUA_TTABLE     5
#define LUA_TFUNCTION  6

#define LFN(ret, name, addr, ...) static ret (__cdecl* const name)(__VA_ARGS__) = (ret (__cdecl*)(__VA_ARGS__))(addr)
LFN(int,         lua_gettop,       0x00E02050, lua_State*);
LFN(void,        lua_settop,       0x00E02060, lua_State*, int);
LFN(void,        lua_remove,       0x00E020B0, lua_State*, int);
LFN(void,        lua_insert,       0x00E02100, lua_State*, int);
LFN(void,        lua_pushvalue,    0x00E02210, lua_State*, int);
LFN(int,         lua_type,         0x00E02240, lua_State*, int);
LFN(double,      lua_tonumber,     0x00E02360, lua_State*, int);
LFN(int,         lua_toboolean,    0x00E023E0, lua_State*, int);
LFN(const char*, lua_tolstring,    0x00E02410, lua_State*, int, size_t*);
LFN(size_t,      lua_objlen,       0x00E02480, lua_State*, int);
LFN(void,        lua_pushnil,      0x00E02580, lua_State*);
LFN(void,        lua_pushnumber,   0x00E025A0, lua_State*, double);
LFN(void,        lua_pushlstring,  0x00E025E0, lua_State*, const char*, size_t);
LFN(void,        lua_pushstring,   0x00E02620, lua_State*, const char*);
LFN(void,        lua_pushcclosure, 0x00E026F0, lua_State*, lua_CFunction, int);
LFN(void,        lua_pushboolean,  0x00E02790, lua_State*, int);
LFN(void,        lua_gettable,     0x00E027E0, lua_State*, int);
LFN(void,        lua_getfield,     0x00E02810, lua_State*, int, const char*);
LFN(void,        lua_rawget,       0x00E02870, lua_State*, int);
LFN(void,        lua_rawgeti,      0x00E028B0, lua_State*, int, int);
LFN(void,        lua_createtable,  0x00E028F0, lua_State*, int, int);
LFN(int,         lua_getmetatable, 0x00E02930, lua_State*, int);
LFN(int,         lua_setmetatable, 0x00E02B00, lua_State*, int);
LFN(int,         lua_rawequal,     0x00E02320, lua_State*, int, int);
LFN(void,        lua_settable,     0x00E02A00, lua_State*, int);
LFN(void,        lua_setfield,     0x00E02A30, lua_State*, int, const char*);
LFN(void,        lua_rawset,       0x00E02A90, lua_State*, int);
LFN(void,        lua_call,         0x00E02C40, lua_State*, int, int);
LFN(int,         lua_pcall,        0x00E02CA0, lua_State*, int, int, int);
LFN(int,         lua_next,         0x00E02E70, lua_State*, int);
LFN(int,         luaL_loadbuffer,  0x00FCF890, lua_State*, const char*, size_t, const char*);
#undef LFN

inline const char* lua_tostr(lua_State* L, int i) { return lua_tolstring(L, i, nullptr); }
inline void lua_pop(lua_State* L, int n) { lua_settop(L, -(n)-1); }
inline void lua_newtable(lua_State* L) { lua_createtable(L, 0, 0); }
// Globals are read and written RAW: the UI state's globals carry a metatable (system_lib.lua) whose
// __index/__newindex raise errors for undefined names, and a Lua error inside our C code would crash.
inline void rawGetGlobal(lua_State* L, const char* k) { lua_pushstring(L, k); lua_rawget(L, LUA_GLOBALSINDEX); }
inline void rawSetGlobal(lua_State* L, const char* k) {   // pops the value
    lua_pushstring(L, k); lua_insert(L, -2); lua_rawset(L, LUA_GLOBALSINDEX);
}
// t[i] = top (pops); no lua_rawseti in this build
inline void lua_seti(lua_State* L, int t, int i) {
    if (t < 0 && t > LUA_REGISTRYINDEX) t--;          // the number we push shifts relative indices
    lua_pushnumber(L, i); lua_insert(L, -2); lua_rawset(L, t);
}
