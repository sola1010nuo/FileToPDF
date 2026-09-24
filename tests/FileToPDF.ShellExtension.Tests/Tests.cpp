#include "../../src/FileToPDF.ShellExtension/Launch.h"
#include <shobjidl.h>
#include <shlobj.h>
#include <shellapi.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>

using Microsoft::WRL::ComPtr;
using namespace FileToPDFShell;
void Check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void Hr(HRESULT value) {
    if (FAILED(value)) { std::wcerr << L"HRESULT 0x" << std::hex << static_cast<unsigned long>(value) << L'\n'; throw std::runtime_error("COM call failed"); }
}
int wmain(int argc, wchar_t** argv) {
    // Copy this executable as ArgumentProbe.exe to capture the exact argv of ONE launched process.
    auto self = std::filesystem::path(argv[0]);
    if (self.filename() == L"ArgumentProbe.exe") {
        std::ofstream invocations(self.parent_path() / L"invocations.txt", std::ios::app);
        invocations << GetCurrentProcessId() << '\n';
        std::ofstream output(self.parent_path() / L"arguments.bin", std::ios::binary);
        output.write(reinterpret_cast<const char*>(&argc), sizeof(argc));
        for (int i = 1; i < argc; ++i) {
            auto length = static_cast<int>(wcslen(argv[i]));
            output.write(reinterpret_cast<const char*>(&length), sizeof(length));
            output.write(reinterpret_cast<const char*>(argv[i]), length * sizeof(wchar_t));
        }
        return output.good() ? 0 : 1;
    }
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(init)) return 1;
    int result = 0;
    HMODULE module = nullptr;
    try {
        Check(argc >= 3, "Usage: tests --unit|--state|--invoke DLL|registered [files...]");
        ComPtr<IExplorerCommand> command;
        if (std::wstring(argv[2]) == L"registered" || std::wstring(argv[2]) == L"registered-legacy") {
            auto context = std::wstring(argv[2]) == L"registered" ? CLSCTX_LOCAL_SERVER : CLSCTX_INPROC_SERVER;
            Hr(CoCreateInstance(CommandId, nullptr, context, IID_PPV_ARGS(&command)));
        } else {
            module = LoadLibraryW(argv[2]);
            Check(module != nullptr, "LoadLibrary");
            using GetFactory = HRESULT(__stdcall*)(REFCLSID, REFIID, void**);
            auto getFactory = reinterpret_cast<GetFactory>(GetProcAddress(module, "DllGetClassObject"));
            Check(getFactory != nullptr, "DllGetClassObject export");
            ComPtr<IClassFactory> factory;
            Hr(getFactory(CommandId, IID_PPV_ARGS(&factory)));
            Hr(factory->CreateInstance(nullptr, IID_PPV_ARGS(&command)));
        }
        if (std::wstring(argv[1]) == L"--unit") {
            PWSTR title = nullptr;
            Hr(command->GetTitle(nullptr, &title));
            Check(std::wstring(title) == L"Convert to PDF", "title");
            CoTaskMemFree(title);
            GUID name{}; Hr(command->GetCanonicalName(&name)); Check(name == CommandId, "canonical identity");
            EXPCMDSTATE state{}; Hr(command->GetState(nullptr, FALSE, &state)); Check(state == ECS_HIDDEN, "empty selection hidden");
            EXPCMDFLAGS flags{}; Hr(command->GetFlags(&flags)); Check(flags == ECF_DEFAULT, "top-level command without submenu");
            const std::vector<std::wstring> values = {L"C:\\My Tools\\FileToPDF.exe", L"C:\\中文 & (test)\\photo.png", L"C:\\trailing\\", L"a\\\"b", L""};
            std::wstring line;
            for (const auto& value : values) { if (!line.empty()) line += L' '; line += Quote(value); }
            int count = 0; auto parsed = CommandLineToArgvW(line.c_str(), &count);
            Check(parsed && count == static_cast<int>(values.size()), "quoted argument count");
            for (int i = 0; i < count; ++i) Check(values[i] == parsed[i], "quoted argument roundtrip");
            LocalFree(parsed);
            std::cout << "PASS: native COM contract, empty selection, canonical GUID, Windows argv escaping\n";
        } else {
            std::vector<PIDLIST_ABSOLUTE> ids;
            for (int i = 3; i < argc; ++i) {
                PIDLIST_ABSOLUTE id = nullptr;
                Hr(SHParseDisplayName(argv[i], nullptr, &id, 0, nullptr));
                ids.push_back(id);
            }
            ComPtr<IShellItemArray> items;
            auto hr = SHCreateShellItemArrayFromIDLists(static_cast<UINT>(ids.size()), const_cast<PCIDLIST_ABSOLUTE*>(ids.data()), &items);
            for (auto id : ids) CoTaskMemFree(id);
            Hr(hr);
            EXPCMDSTATE state{};
            Hr(command->GetState(items.Get(), TRUE, &state));
            std::cout << (state == ECS_ENABLED ? "ENABLED" : "HIDDEN") << '\n';
            if (std::wstring(argv[1]) == L"--invoke") {
                Check(state == ECS_ENABLED, "selection must be enabled before Invoke");
                Hr(command->Invoke(items.Get(), nullptr));
                std::cout << "PASS: Invoke\n";
            }
        }
    } catch (const std::exception& ex) { std::cerr << ex.what() << '\n'; result = 1; }
    if (module) FreeLibrary(module);
    CoUninitialize();
    return result;
}
