#pragma once
#include <windows.h>
#include <shlwapi.h>
#include <string>
#include <vector>
#include <stdexcept>

namespace FileToPDFShell {
inline constexpr GUID CommandId = {0x5d62fc80, 0xdf75, 0x4807, {0xae, 0x2b, 0x7e, 0x4a, 0x25, 0x97, 0xdb, 0x5c}};
inline constexpr wchar_t SettingsKey[] = L"Software\\FileToPDF\\ShellIntegration";

// Windows argv escaping, not shell escaping. No cmd.exe or PowerShell is involved.
inline std::wstring Quote(const std::wstring& value) {
    std::wstring result = L"\"";
    size_t slashes = 0;
    for (wchar_t ch : value) {
        if (ch == L'\\') { ++slashes; continue; }
        result.append(ch == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        result += ch;
        slashes = 0;
    }
    result.append(slashes * 2, L'\\');
    return result + L'"';
}
inline std::wstring ReadExePath() {
    DWORD bytes = 0;
    if (RegGetValueW(HKEY_CURRENT_USER, SettingsKey, L"ExePath", RRF_RT_REG_SZ, nullptr, nullptr, &bytes) != ERROR_SUCCESS)
        throw std::runtime_error("FileToPDF is not configured");
    std::vector<wchar_t> value(bytes / sizeof(wchar_t) + 1);
    if (RegGetValueW(HKEY_CURRENT_USER, SettingsKey, L"ExePath", RRF_RT_REG_SZ, nullptr, value.data(), &bytes) != ERROR_SUCCESS)
        throw std::runtime_error("Cannot read FileToPDF path");
    std::wstring path(value.data());
    if (path.empty() || PathIsRelativeW(path.c_str())) throw std::runtime_error("Expected absolute EXE path");
    return path;
}
inline HRESULT Launch(const std::vector<std::wstring>& paths) noexcept {
    try {
        if (paths.empty()) return E_INVALIDARG;
        auto exe = ReadExePath();
        auto command = Quote(exe);
        for (const auto& path : paths) command += L" " + Quote(path);
        // CreateProcess's documented limit includes the terminating null.
        if (command.size() >= 32767) return HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
        STARTUPINFOW startup{sizeof(startup)};
        PROCESS_INFORMATION process{};
        if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr,
            nullptr, &startup, &process)) return HRESULT_FROM_WIN32(GetLastError());
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        return S_OK;
    } catch (const std::bad_alloc&) { return E_OUTOFMEMORY; }
      catch (...) { return HRESULT_FROM_WIN32(ERROR_BAD_CONFIGURATION); }
}
}
