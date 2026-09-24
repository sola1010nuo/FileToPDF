#include "Launch.h"
#include <shellapi.h>

// Identity anchor for the sparse package. No conversion or resident message loop.
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int count = 0;
    auto argv = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!argv) return 1;
    std::vector<std::wstring> paths;
    for (int i = 1; i < count; ++i) paths.emplace_back(argv[i]);
    LocalFree(argv);
    return paths.empty() ? 0 : (SUCCEEDED(FileToPDFShell::Launch(paths)) ? 0 : 1);
}
