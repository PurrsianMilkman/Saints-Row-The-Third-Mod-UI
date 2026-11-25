// SR3ModUI.asi - a native-menu UI API for Saints Row: The Third mods (SaintsRowTheThird_DX11.exe).
//
// How it gets in. Every Lua script the game runs (each UI document's script, and the gameplay
// scripts) is loaded by one of two engine loaders, which call luaL_loadbuffer then lua_pcall. We point
// those four call sites at wrappers:
//   before a script loads: if this Lua state has not seen us yet, "boot" it - register the native
//     helper table __modui_c, run SR3ModUI\modui.lua (the API) and then the mod scripts;
//   after a script ran: call ModUI._after_load(name), so the API can re-apply its hooks onto the
//     functions that script just (re)defined, before the engine calls the document's init.
// No game file is modified. C mods talk to the API through SR3ModUI_GetApi (include/sr3modui.h).
#define NOMINMAX
#define SR3MODUI_NO_LOADER
#define SR3MODUI_RELEASE "0.2.0"   // shown in SR3ModUI.log; keep in step with the release tag
#include "../../include/sr3modui.h"
#include "lua.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdarg>
#include <string>
#include <vector>
#include <algorithm>

namespace {

char g_dir[MAX_PATH], g_log[MAX_PATH], g_ini[MAX_PATH];
CRITICAL_SECTION g_cs;

void logf(const char* fmt, ...) {
    EnterCriticalSection(&g_cs);
    FILE* f = fopen(g_log, "a");
    if (f) {
        SYSTEMTIME t; GetLocalTime(&t);
        fprintf(f, "%02d:%02d:%02d.%03d ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
        va_list a; va_start(a, fmt); vfprintf(f, fmt, a); va_end(a);
        fputc('\n', f);
        fclose(f);
    }
    LeaveCriticalSection(&g_cs);
}

// ---------------------------------------------------------------------------------------------
// engine hook points (DX11), each checked before it is patched
// ---------------------------------------------------------------------------------------------
const uintptr_t LOADBUFFER = 0x00FCF890, PCALL = 0x00E02CA0;
const uintptr_t SITE_LOAD_FILE = 0x00E7BBDA, SITE_PCALL_FILE = 0x00E7BBED;   // loader 0x00E7BB00
const uintptr_t SITE_LOAD_BUF  = 0x00E7C207, SITE_PCALL_BUF  = 0x00E7C218;   // loader 0x00E7C180

bool patchCall(uintptr_t at, uintptr_t expect, void* to) {
    unsigned char* p = (unsigned char*)at;
    if (IsBadReadPtr(p, 5) || p[0] != 0xE8 || at + 5 + *(int32_t*)(p + 1) != expect) return false;
    DWORD old;
    VirtualProtect(p, 5, PAGE_EXECUTE_READWRITE, &old);
    *(int32_t*)(p + 1) = (int32_t)((uintptr_t)to - (at + 5));
    VirtualProtect(p, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, 5);
    return true;
}

// ---------------------------------------------------------------------------------------------
// C registry: pages and widgets added by ASI mods, mirrored into the UI state by modui.lua
// ---------------------------------------------------------------------------------------------
enum { W_BUTTON, W_TOGGLE, W_SLIDER, W_CHOICE, W_COLOR, W_LABEL };
const char* const W_NAMES[] = { "button", "toggle", "slider", "choice", "color", "label" };

struct Widget {
    int type; std::string page, key, label, options;
    double min = 0, max = 1, step = 1, value = 0;
    bool enabled = true;
    SR3ModUI_Callback cb = nullptr; void* user = nullptr;
};
struct Page { std::string id, title, attach; int flags = 0; };   // attach: game screen (AttachPage)
std::vector<Page> g_pages;
std::vector<Widget> g_widgets;
int g_rev = 1;

struct Handler { std::string name; SR3ModUI_Handler fn; void* user; };
std::vector<Handler> g_handlers;

Widget* findWidget(const char* page, const char* key) {
    for (auto& w : g_widgets) if (w.page == page && w.key == key) return &w;
    return nullptr;
}
bool validId(const char* s) {
    if (!s || !*s || strlen(s) > 64) return false;
    for (; *s; s++) if (!(isalnum((unsigned char)*s) || *s == '_')) return false;
    return true;
}
bool iniLoad(const char* page, const char* key, double* out) {
    char buf[64];
    GetPrivateProfileStringA(page, key, "", buf, sizeof buf, g_ini);
    if (!buf[0]) return false;
    char* end; double v = strtod(buf, &end);
    if (end == buf) return false;
    *out = v; return true;
}
void iniSave(const char* page, const char* key, double v) {
    char buf[64]; snprintf(buf, sizeof buf, "%.9g", v);
    WritePrivateProfileStringA(page, key, buf, g_ini);
}

// ---------------------------------------------------------------------------------------------
// exported C API
// ---------------------------------------------------------------------------------------------
int __cdecl apiVersion() { return SR3MODUI_VERSION; }

int __cdecl apiAddPage(const char* page, const char* title) {
    if (!validId(page)) return 0;
    EnterCriticalSection(&g_cs);
    bool found = false;
    for (auto& p : g_pages) if (p.id == page) { p.title = title ? title : page; found = true; }
    if (!found) { Page p; p.id = page; p.title = title ? title : page; g_pages.push_back(p); }
    g_rev++;
    LeaveCriticalSection(&g_cs);
    return 1;
}

int addWidget(Widget w) {
    if (!validId(w.page.c_str()) || !validId(w.key.c_str())) return 0;
    EnterCriticalSection(&g_cs);
    bool havePage = false;
    for (auto& p : g_pages) if (p.id == w.page) havePage = true;
    if (!havePage) { Page p; p.id = w.page; p.title = w.page; g_pages.push_back(p); }
    double saved;
    if (w.type != W_BUTTON && w.type != W_LABEL && iniLoad(w.page.c_str(), w.key.c_str(), &saved)) w.value = saved;
    Widget* old = findWidget(w.page.c_str(), w.key.c_str());
    if (old) *old = w; else g_widgets.push_back(w);
    g_rev++;
    LeaveCriticalSection(&g_cs);
    return 1;
}
int __cdecl apiAddButton(const char* page, const char* key, const char* label, SR3ModUI_Callback cb, void* user) {
    Widget w; w.type = W_BUTTON; w.page = page ? page : ""; w.key = key ? key : ""; w.label = label ? label : w.key;
    w.cb = cb; w.user = user; return addWidget(w);
}
int __cdecl apiAddToggle(const char* page, const char* key, const char* label, int def, SR3ModUI_Callback cb, void* user) {
    Widget w; w.type = W_TOGGLE; w.page = page ? page : ""; w.key = key ? key : ""; w.label = label ? label : w.key;
    w.value = def ? 1 : 0; w.cb = cb; w.user = user; return addWidget(w);
}
int __cdecl apiAddSlider(const char* page, const char* key, const char* label, double mn, double mx, double step, double def,
                         SR3ModUI_Callback cb, void* user) {
    if (!(mx > mn) || !(step > 0)) return 0;
    Widget w; w.type = W_SLIDER; w.page = page ? page : ""; w.key = key ? key : ""; w.label = label ? label : w.key;
    w.min = mn; w.max = mx; w.step = step; w.value = def; w.cb = cb; w.user = user; return addWidget(w);
}
int __cdecl apiAddChoice(const char* page, const char* key, const char* label, const char* options, int def, SR3ModUI_Callback cb, void* user) {
    if (!options || !*options) return 0;
    Widget w; w.type = W_CHOICE; w.page = page ? page : ""; w.key = key ? key : ""; w.label = label ? label : w.key;
    w.options = options; w.value = def; w.cb = cb; w.user = user; return addWidget(w);
}
int __cdecl apiAddColor(const char* page, const char* key, const char* label, unsigned rgb, SR3ModUI_Callback cb, void* user) {
    Widget w; w.type = W_COLOR; w.page = page ? page : ""; w.key = key ? key : ""; w.label = label ? label : w.key;
    w.value = (double)(rgb & 0xFFFFFF); w.cb = cb; w.user = user; return addWidget(w);
}
int __cdecl apiAddLabel(const char* page, const char* key, const char* text) {
    Widget w; w.type = W_LABEL; w.page = page ? page : ""; w.key = key ? key : ""; w.label = text ? text : "";
    return addWidget(w);
}
double __cdecl apiGetValue(const char* page, const char* key) {
    if (!page || !key) return 0;
    EnterCriticalSection(&g_cs);
    Widget* w = findWidget(page, key);
    double v = w ? w->value : 0;
    LeaveCriticalSection(&g_cs);
    return v;
}
void __cdecl apiSetValue(const char* page, const char* key, double v) {
    if (!page || !key) return;
    EnterCriticalSection(&g_cs);
    Widget* w = findWidget(page, key);
    if (w) { w->value = v; g_rev++; iniSave(page, key, v); }
    LeaveCriticalSection(&g_cs);
}
void __cdecl apiSetLabel(const char* page, const char* key, const char* label) {
    if (!page || !key || !label) return;
    EnterCriticalSection(&g_cs);
    Widget* w = findWidget(page, key);
    if (w) { w->label = label; g_rev++; }
    LeaveCriticalSection(&g_cs);
}
void __cdecl apiSetEnabled(const char* page, const char* key, int en) {
    if (!page || !key) return;
    EnterCriticalSection(&g_cs);
    Widget* w = findWidget(page, key);
    if (w) { w->enabled = en != 0; g_rev++; }
    LeaveCriticalSection(&g_cs);
}
int __cdecl apiAttachPage(const char* page, const char* screen, int flags) {
    if (!validId(page) || !screen || !*screen || strlen(screen) > 64) return 0;
    EnterCriticalSection(&g_cs);
    Page* pp = nullptr;
    for (auto& p : g_pages) if (p.id == page) pp = &p;
    if (!pp) { Page p; p.id = page; p.title = page; g_pages.push_back(p); pp = &g_pages.back(); }
    pp->attach = screen; pp->flags = flags;
    g_rev++;
    LeaveCriticalSection(&g_cs);
    return 1;
}
int __cdecl apiRegisterHandler(const char* name, SR3ModUI_Handler h, void* user) {
    if (!validId(name) || !h) return 0;
    EnterCriticalSection(&g_cs);
    bool found = false;
    for (auto& x : g_handlers) if (x.name == name) { x.fn = h; x.user = user; found = true; }
    if (!found) g_handlers.push_back({ name, h, user });
    LeaveCriticalSection(&g_cs);
    return 1;
}

}  // namespace

struct SR3ModUI_Call { lua_State* L; int base, nargs, nret; };

namespace {

int __cdecl apiArgCount(SR3ModUI_Call* c) { return c ? c->nargs : 0; }
double __cdecl apiArgNumber(SR3ModUI_Call* c, int i) {
    if (!c || i < 1 || i > c->nargs) return 0;
    return lua_tonumber(c->L, c->base + i);
}
const char* __cdecl apiArgString(SR3ModUI_Call* c, int i) {
    if (!c || i < 1 || i > c->nargs) return nullptr;
    int t = lua_type(c->L, c->base + i);
    if (t != LUA_TSTRING && t != LUA_TNUMBER) return nullptr;
    return lua_tostr(c->L, c->base + i);
}
void __cdecl apiReturnNumber(SR3ModUI_Call* c, double v) { if (c) { lua_pushnumber(c->L, v); c->nret++; } }
void __cdecl apiReturnString(SR3ModUI_Call* c, const char* s) { if (c) { lua_pushstring(c->L, s ? s : ""); c->nret++; } }
void __cdecl apiReturnBool(SR3ModUI_Call* c, int b) { if (c) { lua_pushboolean(c->L, b); c->nret++; } }
void __cdecl apiLog(const char* mod, const char* text) { logf("[%s] %s", mod ? mod : "?", text ? text : ""); }

const SR3ModUI_Api g_api = {
    apiVersion, apiAddPage, apiAddButton, apiAddToggle, apiAddSlider, apiAddChoice, apiAddColor, apiAddLabel,
    apiGetValue, apiSetValue, apiSetLabel, apiSetEnabled,
    apiRegisterHandler, apiArgCount, apiArgNumber, apiArgString, apiReturnNumber, apiReturnString, apiReturnBool, apiLog,
    apiAttachPage,
};

// ---------------------------------------------------------------------------------------------
// natives: the table __modui_c in every booted Lua state
// ---------------------------------------------------------------------------------------------
const char* argStr(lua_State* L, int i) {
    int t = lua_type(L, i);
    return (t == LUA_TSTRING || t == LUA_TNUMBER) ? lua_tostr(L, i) : nullptr;
}

int __cdecl n_log(lua_State* L) {
    const char* s = argStr(L, 1);
    logf("lua: %s", s ? s : "(non-string)");
    return 0;
}
// pcall(f, ...) -> true, results... | false, message   (the UI state has no pcall of its own)
int __cdecl n_pcall(lua_State* L) {
    int n = lua_gettop(L);
    if (n < 1) { lua_pushboolean(L, 0); lua_pushstring(L, "pcall: no function"); return 2; }
    int r = lua_pcall(L, n - 1, LUA_MULTRET, 0);
    lua_pushboolean(L, r == 0);
    lua_insert(L, 1);
    return lua_gettop(L);
}
int __cdecl n_load(lua_State* L) {
    const char* p = argStr(L, 1); const char* k = argStr(L, 2); double v;
    if (p && k && iniLoad(p, k, &v)) { lua_pushnumber(L, v); return 1; }
    return 0;
}
int __cdecl n_save(lua_State* L) {
    const char* p = argStr(L, 1); const char* k = argStr(L, 2);
    if (p && k && validId(p) && validId(k) && lua_type(L, 3) == LUA_TNUMBER) iniSave(p, k, lua_tonumber(L, 3));
    return 0;
}
int __cdecl n_rev(lua_State* L) { lua_pushnumber(L, g_rev); return 1; }

void setStr(lua_State* L, const char* k, const std::string& v) { lua_pushstring(L, v.c_str()); lua_setfield(L, -2, k); }
void setNum(lua_State* L, const char* k, double v) { lua_pushnumber(L, v); lua_setfield(L, -2, k); }

// c_pages() -> { {id=, title=, widgets={ {type=, key=, label=, ...}, ... }}, ... }, rev
int __cdecl n_pages(lua_State* L) {
    EnterCriticalSection(&g_cs);
    lua_newtable(L);
    int pi = 0;
    for (auto& p : g_pages) {
        lua_newtable(L);
        setStr(L, "id", p.id); setStr(L, "title", p.title);
        if (!p.attach.empty()) {
            setStr(L, "attach", p.attach);
            lua_pushboolean(L, (p.flags & SR3MODUI_ALSO_IN_MODS) != 0); lua_setfield(L, -2, "listed");
        }
        lua_newtable(L);
        int wi = 0;
        for (auto& w : g_widgets) {
            if (w.page != p.id) continue;
            lua_newtable(L);
            setStr(L, "type", W_NAMES[w.type]); setStr(L, "key", w.key); setStr(L, "label", w.label);
            setNum(L, "min", w.min); setNum(L, "max", w.max); setNum(L, "step", w.step); setNum(L, "value", w.value);
            lua_pushboolean(L, w.enabled); lua_setfield(L, -2, "enabled");
            if (w.type == W_CHOICE) {
                lua_newtable(L);
                int oi = 0; size_t s = 0;
                while (s <= w.options.size()) {
                    size_t e = w.options.find('|', s);
                    if (e == std::string::npos) e = w.options.size();
                    lua_pushstring(L, w.options.substr(s, e - s).c_str());
                    lua_seti(L, -2, ++oi);
                    s = e + 1;
                }
                lua_setfield(L, -2, "options");
            }
            lua_seti(L, -2, ++wi);
        }
        lua_setfield(L, -2, "widgets");
        lua_seti(L, -2, ++pi);
    }
    lua_pushnumber(L, g_rev);
    LeaveCriticalSection(&g_cs);
    return 2;
}
// c_changed(page, key, value): the player changed a C widget (or pressed a C button)
int __cdecl n_changed(lua_State* L) {
    const char* p = argStr(L, 1); const char* k = argStr(L, 2);
    double v = lua_type(L, 3) == LUA_TNUMBER ? lua_tonumber(L, 3) : 0;
    if (!p || !k) return 0;
    SR3ModUI_Callback cb = nullptr; void* user = nullptr; std::string sp = p, sk = k;
    EnterCriticalSection(&g_cs);
    Widget* w = findWidget(p, k);
    if (w) {
        cb = w->cb; user = w->user;
        if (w->type != W_BUTTON && w->type != W_LABEL) { w->value = v; iniSave(p, k, v); }
    }
    LeaveCriticalSection(&g_cs);
    if (cb) cb(sp.c_str(), sk.c_str(), v, user);       // outside the lock: the callback may call the API
    return 0;
}
// call(name, ...) -> whatever the C handler returns
int __cdecl n_call(lua_State* L) {
    const char* name = argStr(L, 1);
    if (!name) return 0;
    SR3ModUI_Handler fn = nullptr; void* user = nullptr;
    EnterCriticalSection(&g_cs);
    for (auto& h : g_handlers) if (h.name == name) { fn = h.fn; user = h.user; }
    LeaveCriticalSection(&g_cs);
    if (!fn) return 0;
    SR3ModUI_Call c{ L, 1, lua_gettop(L) - 1, 0 };
    fn(&c, user);
    return c.nret;
}
// fmt(x, decimals) -> string (the UI state has no string library)
int __cdecl n_fmt(lua_State* L) {
    double x = lua_tonumber(L, 1);
    int d = lua_type(L, 2) == LUA_TNUMBER ? (int)lua_tonumber(L, 2) : 0;
    d = std::max(0, std::min(d, 6));
    char buf[64]; snprintf(buf, sizeof buf, "%.*f", d, x);
    lua_pushstring(L, buf);
    return 1;
}
// hex(n) -> "RRGGBB"
int __cdecl n_hex(lua_State* L) {
    char buf[16]; snprintf(buf, sizeof buf, "%06X", (unsigned)lua_tonumber(L, 1) & 0xFFFFFF);
    lua_pushstring(L, buf);
    return 1;
}
int __cdecl n_band(lua_State* L) {   // bit ops for colour packing: band(a, b), no bit library in 5.1
    lua_pushnumber(L, (double)((unsigned)lua_tonumber(L, 1) & (unsigned)lua_tonumber(L, 2)));
    return 1;
}
int __cdecl n_find(lua_State* L) {   // find(s, sub) -> bool, plain substring (no string library)
    const char* s = argStr(L, 1); const char* sub = argStr(L, 2);
    lua_pushboolean(L, s && sub && strstr(s, sub) != nullptr);
    return 1;
}
int __cdecl n_upper(lua_State* L) {   // upper(s) -> s in capitals (ASCII)
    const char* s = argStr(L, 1);
    std::string u = s ? s : "";
    for (auto& ch : u) if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 32);
    lua_pushstring(L, u.c_str());
    return 1;
}
int __cdecl n_keydown(lua_State* L) {   // keydown(vk) -> bool
    lua_pushboolean(L, (GetAsyncKeyState((int)lua_tonumber(L, 1)) & 0x8000) != 0);
    return 1;
}

// ---------------------------------------------------------------------------------------------
// booting a Lua state
// ---------------------------------------------------------------------------------------------
bool isFunction(lua_State* L, const char* global) {
    rawGetGlobal(L, global);
    bool f = lua_type(L, -1) == LUA_TFUNCTION;
    lua_pop(L, 1);
    return f;
}

// Finds a global the way the game's scripts see it: the raw globals first, then each script's table
// in _DynamicGlobals (system_lib.lua keeps loaded scripts' globals there). Pushes the value (nil if
// absent); if it was found in a dynamic table, that table is pushed below the value. Returns 0 (raw
// global), 1 (dynamic: table + value pushed) or -1 (absent: nil pushed).
int findGlobal(lua_State* L, const char* k) {
    rawGetGlobal(L, k);
    if (lua_type(L, -1) != LUA_TNIL) return 0;
    lua_pop(L, 1);
    rawGetGlobal(L, "_DynamicGlobals");
    if (lua_type(L, -1) == LUA_TTABLE) {
        lua_pushnil(L);
        while (lua_next(L, -2)) {                          // dyn, key, tbl
            if (lua_type(L, -1) == LUA_TTABLE) {
                lua_pushstring(L, k); lua_rawget(L, -2);   // dyn, key, tbl, v
                if (lua_type(L, -1) != LUA_TNIL) {
                    lua_remove(L, -3);                     // dyn, tbl, v
                    lua_remove(L, -3);                     // tbl, v
                    return 1;
                }
                lua_pop(L, 1);
            }
            lua_pop(L, 1);                                 // dyn, key
        }
    }
    lua_pop(L, 1);
    lua_pushnil(L);
    return -1;
}
// gget(name) -> value; never raises (reading an undefined global in the UI state does)
int __cdecl n_gget(lua_State* L) {
    const char* k = argStr(L, 1);
    if (!k) return 0;
    findGlobal(L, k);
    return 1;
}
// gset(name, value): replaces the value where the game keeps it (a script's dynamic table or the raw
// globals); a new name becomes a raw global, so it survives script unloads
int __cdecl n_gset(lua_State* L) {
    const char* k = argStr(L, 1);
    if (!k) return 0;
    lua_settop(L, 2);
    int where = findGlobal(L, k);                          // k, v, [tbl], old
    if (where == 1) {
        lua_pop(L, 1);                                     // k, v, tbl
        lua_pushstring(L, k); lua_pushvalue(L, 2); lua_rawset(L, -3);
    } else {
        lua_pushvalue(L, 2); rawSetGlobal(L, k);
    }
    return 0;
}

// runs a file in L; returns false (and logs) on any error. Leaves the stack as it was.
bool runFile(lua_State* L, const char* path, const char* chunk) {
    FILE* f = fopen(path, "rb");
    if (!f) { logf("cannot open %s", path); return false; }
    std::string buf;
    char tmp[16384]; size_t n;
    while ((n = fread(tmp, 1, sizeof tmp, f)) > 0) buf.append(tmp, n);
    fclose(f);
    int top = lua_gettop(L);
    int r = luaL_loadbuffer(L, buf.data(), buf.size(), chunk);
    if (r == 0) r = lua_pcall(L, 0, 0, 0);
    if (r != 0) {
        const char* msg = lua_tostr(L, -1);
        logf("ERROR in %s: %s", chunk, msg ? msg : "?");
    }
    lua_settop(L, top);
    return r == 0;
}

struct State { lua_State* L; const char* kind; };
std::vector<State> g_states;

const char* stateKind(lua_State* L) {
    for (auto& s : g_states) if (s.L == L) return s.kind;
    return nullptr;
}

void boot(lua_State* L, const char* firstScript, int loader) {
    const char* kind = isFunction(L, "vint_document_find") ? "ui" : isFunction(L, "teleport_to_object") ? "game" : nullptr;
    if (!kind) {   // bindings not registered yet, or a state we don't serve: look again on its next script
        static int n = 0;
        if (n++ < 20) logf("boot: Lua state %p not recognised yet (script %s, loader %d)", (void*)L, firstScript ? firstScript : "?", loader);
        return;
    }
    g_states.push_back({ L, kind });
    int top = lua_gettop(L);
    rawGetGlobal(L, "_DynamicGlobals");
    bool dyn = lua_type(L, -1) == LUA_TTABLE;
    bool mt = lua_getmetatable(L, LUA_GLOBALSINDEX) != 0;
    lua_settop(L, top);
    logf("boot: Lua state %p kind=%s (first script %s, loader %d) dynamic-globals=%d globals-metatable=%d",
         (void*)L, kind, firstScript ? firstScript : "?", loader, dyn, mt);

    static const struct { const char* name; lua_CFunction fn; } natives[] = {
        { "log", n_log }, { "pcall", n_pcall }, { "load", n_load }, { "save", n_save }, { "rev", n_rev },
        { "c_pages", n_pages }, { "c_changed", n_changed }, { "call", n_call }, { "fmt", n_fmt }, { "hex", n_hex },
        { "band", n_band }, { "keydown", n_keydown }, { "gget", n_gget }, { "gset", n_gset }, { "find", n_find }, { "upper", n_upper },
    };
    lua_newtable(L);
    for (auto& n : natives) { lua_pushcclosure(L, n.fn, 0); lua_setfield(L, -2, n.name); }
    lua_pushstring(L, kind); lua_setfield(L, -2, "state");
    rawSetGlobal(L, "__modui_c");

    // Run the API and the mods with the globals' metatable lifted, so whatever they define at top level
    // becomes a plain, permanent global (with it in place, a new global would land in the table of
    // whichever game script is loading right now, and vanish when that script unloads).
    int hadMt = lua_getmetatable(L, LUA_GLOBALSINDEX);          // pushes the metatable if any
    if (hadMt) { lua_pushnil(L); lua_setmetatable(L, LUA_GLOBALSINDEX); }

    char path[MAX_PATH * 2];
    snprintf(path, sizeof path, "%sSR3ModUI\\modui.lua", g_dir);
    if (runFile(L, path, "@SR3ModUI/modui.lua")) {
        // mod scripts: SR3ModUI\mods\*.lua run in the UI state, *.game.lua in the gameplay state
        std::vector<std::string> files;
        snprintf(path, sizeof path, "%sSR3ModUI\\mods\\*.lua", g_dir);
        WIN32_FIND_DATAA fd;
        HANDLE h = FindFirstFileA(path, &fd);
        if (h != INVALID_HANDLE_VALUE) {
            do {
                if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
                std::string n = fd.cFileName;
                bool game = n.size() > 9 && _stricmp(n.c_str() + n.size() - 9, ".game.lua") == 0;
                if (game == (strcmp(kind, "game") == 0)) files.push_back(n);
            } while (FindNextFileA(h, &fd));
            FindClose(h);
        }
        std::sort(files.begin(), files.end());
        for (auto& n : files) {
            snprintf(path, sizeof path, "%sSR3ModUI\\mods\\%s", g_dir, n.c_str());
            std::string chunk = "@SR3ModUI/mods/" + n;
            bool ok = runFile(L, path, chunk.c_str());
            logf("  mod %s: %s", n.c_str(), ok ? "loaded" : "FAILED (see the error above)");
        }
        // let the API finish (sort pages, apply hooks) once every mod has registered
        rawGetGlobal(L, "ModUI");
        if (lua_type(L, -1) == LUA_TTABLE) {
            lua_getfield(L, -1, "_booted");
            if (lua_type(L, -1) == LUA_TFUNCTION && lua_pcall(L, 0, 0, 0) != 0) logf("ERROR in ModUI._booted: %s", lua_tostr(L, -1));
        }
    }
    lua_settop(L, top + (hadMt ? 1 : 0));
    if (hadMt) lua_setmetatable(L, LUA_GLOBALSINDEX);           // pops the metatable
    lua_settop(L, top);
}

// ---------------------------------------------------------------------------------------------
// the loader wrappers
// ---------------------------------------------------------------------------------------------
std::vector<std::string> g_loading;     // names of scripts between load and run (loads can nest)

int loadCommon(lua_State* L, const char* buf, size_t sz, const char* name, int loader) {
    if (!stateKind(L)) boot(L, name, loader);
    int r = luaL_loadbuffer(L, buf, sz, name);
    if (r == 0) g_loading.push_back(name ? name : "");
    else logf("load error %d in %s", r, name ? name : "?");
    return r;
}
int __cdecl hookLoadFile(lua_State* L, const char* buf, size_t sz, const char* name) { return loadCommon(L, buf, sz, name, 1); }
int __cdecl hookLoadBuf(lua_State* L, const char* buf, size_t sz, const char* name) { return loadCommon(L, buf, sz, name, 2); }

int __cdecl hookPcall(lua_State* L, int nargs, int nres, int ef) {
    int r = lua_pcall(L, nargs, nres, ef);
    std::string name;
    if (!g_loading.empty()) { name = g_loading.back(); g_loading.pop_back(); }
    const char* kind = stateKind(L);
    static int logged = 0;
    if (logged < 400) { logged++; logf("script %s [%s]%s", name.c_str(), kind ? kind : "?", r ? " (failed)" : ""); }
    if (kind) {
        int top = lua_gettop(L);
        rawGetGlobal(L, "ModUI");
        if (lua_type(L, -1) == LUA_TTABLE) {
            lua_getfield(L, -1, "_after_load");
            if (lua_type(L, -1) == LUA_TFUNCTION) {
                lua_pushstring(L, name.c_str());
                if (lua_pcall(L, 1, 0, 0) != 0) logf("ERROR in ModUI._after_load(%s): %s", name.c_str(), lua_tostr(L, -1));
            }
        }
        lua_settop(L, top);
    }
    return r;
}

void install() {
    const char* exe = "SaintsRowTheThird_DX11.exe";
    char self[MAX_PATH]; GetModuleFileNameA(nullptr, self, MAX_PATH);
    const char* base = strrchr(self, '\\'); base = base ? base + 1 : self;
    if (_stricmp(base, exe) != 0) { logf("SKIP: %s is not %s", base, exe); return; }
    bool ok = patchCall(SITE_LOAD_FILE, LOADBUFFER, (void*)hookLoadFile) &&
              patchCall(SITE_PCALL_FILE, PCALL, (void*)hookPcall) &&
              patchCall(SITE_LOAD_BUF, LOADBUFFER, (void*)hookLoadBuf) &&
              patchCall(SITE_PCALL_BUF, PCALL, (void*)hookPcall);
    logf(ok ? "OK: script loader hooks installed" : "FAILED: loader call sites differ (not the expected game build); API inactive");
}

}  // namespace

extern "C" __declspec(dllexport) const SR3ModUI_Api* __cdecl SR3ModUI_GetApi(int version) {
    return version >= 1 ? &g_api : nullptr;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        InitializeCriticalSection(&g_cs);
        GetModuleFileNameA(nullptr, g_dir, MAX_PATH);
        char* slash = strrchr(g_dir, '\\');
        if (slash) slash[1] = 0;
        snprintf(g_log, sizeof g_log, "%sSR3ModUI.log", g_dir);
        snprintf(g_ini, sizeof g_ini, "%sSR3ModUI.ini", g_dir);
        DeleteFileA(g_log);
        logf("SR3ModUI release %s (API %d) loaded in %s", SR3MODUI_RELEASE, SR3MODUI_VERSION, g_dir);
        install();
    }
    return TRUE;
}
