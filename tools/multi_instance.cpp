// SR3MultiInstance.asi - TEST HELPER ONLY (not part of SR3 Mod UI). Lets a second copy of
// SaintsRowTheThird_DX11.exe run while another is open: at start-up the game creates a named mutex and, if
// it already exists (GetLastError 0xB7), brings the other window to the front and exits (0x00DC8881..).
// The "jne skip" at 0x00DC888C becomes "jmp skip".
#include <windows.h>
#include <cstdio>

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(inst);
    unsigned char* p = (unsigned char*)0x00DC888C;
    const unsigned char want[] = { 0x75, 0x29 };            // jne 0xDC88B7
    char path[MAX_PATH]; GetModuleFileNameA(nullptr, path, MAX_PATH);
    char* s = strrchr(path, '\\'); strcpy(s ? s + 1 : path, "SR3MultiInstance.log");
    FILE* f = fopen(path, "w");
    if (!IsBadReadPtr(p, 2) && p[0] == want[0] && p[1] == want[1] && *(unsigned short*)(0x00DC8887 + 1) == 0x00B7) {
        DWORD old; VirtualProtect(p, 1, PAGE_EXECUTE_READWRITE, &old); p[0] = 0xEB; VirtualProtect(p, 1, old, &old);
        if (f) fputs("OK: single-instance exit disabled\n", f);
    } else if (f) fputs("SKIP: bytes differ\n", f);
    if (f) fclose(f);
    return TRUE;
}
