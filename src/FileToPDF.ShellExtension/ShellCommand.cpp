#include "Launch.h"
#include <shobjidl.h>
#include <wrl/client.h>
#include <atomic>
#include <memory>
#include <new>

using Microsoft::WRL::ComPtr;
using namespace FileToPDFShell;
static std::atomic<long> objects{0};
struct CoTaskDeleter { void operator()(wchar_t* p) const { CoTaskMemFree(p); } };

// Only inspect Shell metadata here: never start Office, read documents, or contact a server.
static HRESULT Selection(IShellItemArray* items, std::vector<std::wstring>& paths) {
    if (!items) return E_INVALIDARG;
    DWORD count = 0;
    HRESULT hr = items->GetCount(&count);
    if (FAILED(hr)) return hr;
    if (!count) return E_INVALIDARG;
    for (DWORD index = 0; index < count; ++index) {
        ComPtr<IShellItem> item;
        hr = items->GetItemAt(index, &item);
        if (FAILED(hr)) return hr;
        SFGAOF attributes = 0;
        hr = item->GetAttributes(SFGAO_FILESYSTEM | SFGAO_FOLDER, &attributes);
        if (FAILED(hr)) return hr;
        if (!(attributes & SFGAO_FILESYSTEM) || (attributes & SFGAO_FOLDER)) return E_INVALIDARG;
        PWSTR raw = nullptr;
        hr = item->GetDisplayName(SIGDN_FILESYSPATH, &raw);
        std::unique_ptr<wchar_t, CoTaskDeleter> path(raw);
        if (FAILED(hr)) return hr;
        const auto ext = PathFindExtensionW(path.get());
        bool supported = false;
        for (const auto candidate : {L".doc", L".docx", L".ppt", L".pptx", L".jpg", L".jpeg", L".png"})
            if (_wcsicmp(ext, candidate) == 0) { supported = true; break; }
        if (!supported) return E_INVALIDARG;
        paths.emplace_back(path.get());
    }
    return S_OK;
}

class ShellCommand final : public IExplorerCommand {
    std::atomic<ULONG> refs{1};
public:
    ShellCommand() { ++objects; }
    ~ShellCommand() { --objects; }
    IFACEMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (iid == IID_IUnknown || iid == __uuidof(IExplorerCommand)) {
            *result = static_cast<IExplorerCommand*>(this); AddRef(); return S_OK;
        }
        return E_NOINTERFACE;
    }
    IFACEMETHODIMP_(ULONG) AddRef() override { return ++refs; }
    IFACEMETHODIMP_(ULONG) Release() override { auto n = --refs; if (!n) delete this; return n; }
    IFACEMETHODIMP GetTitle(IShellItemArray*, PWSTR* title) override {
        if (!title) return E_POINTER;
        return SHStrDupW(L"Convert to PDF", title);
    }
    IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) override {
        if (!icon) return E_POINTER;
        *icon = nullptr;
        try {
            auto exe = ReadExePath();
            auto ico = exe.substr(0, exe.find_last_of(L"\\/")) + L"\\FileToPDF.ico";
            const DWORD attributes = GetFileAttributesW(ico.c_str());
            // Optional sidecar icon. Without it, use the executable's icon resource.
            auto location = attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY)
                ? ico : exe + L",0";
            return SHStrDupW(location.c_str(), icon);
        } catch (...) { return E_NOTIMPL; }
    }
    IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* tip) override {
        if (!tip) return E_POINTER;
        *tip = nullptr; return E_NOTIMPL;
    }
    IFACEMETHODIMP GetCanonicalName(GUID* guid) override {
        if (!guid) return E_POINTER;
        *guid = CommandId; return S_OK;
    }
    IFACEMETHODIMP GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {
        if (!state) return E_POINTER;
        *state = ECS_HIDDEN;
        try {
            std::vector<std::wstring> paths;
            if (SUCCEEDED(Selection(items, paths))) *state = ECS_ENABLED;
            return S_OK;
        } catch (...) { return E_OUTOFMEMORY; }
    }
    IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) override {
        try {
            std::vector<std::wstring> paths;
            HRESULT hr = Selection(items, paths);
            if (SUCCEEDED(hr)) hr = Launch(paths); // Exactly one process for the whole selection.
            if (FAILED(hr)) MessageBoxW(nullptr,
                L"Unable to start FileToPDF. Check its installed path, or select fewer files if the command line is too long.",
                L"FileToPDF", MB_OK | MB_ICONERROR);
            return hr;
        } catch (...) { return E_OUTOFMEMORY; }
    }
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override {
        if (!flags) return E_POINTER;
        *flags = ECF_DEFAULT; return S_OK;
    }
    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** commands) override {
        if (!commands) return E_POINTER;
        *commands = nullptr; return E_NOTIMPL;
    }
};

class Factory final : public IClassFactory {
    std::atomic<ULONG> refs{1};
public:
    Factory() { ++objects; }
    ~Factory() { --objects; }
    IFACEMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (iid == IID_IUnknown || iid == IID_IClassFactory) {
            *result = static_cast<IClassFactory*>(this); AddRef(); return S_OK;
        }
        return E_NOINTERFACE;
    }
    IFACEMETHODIMP_(ULONG) AddRef() override { return ++refs; }
    IFACEMETHODIMP_(ULONG) Release() override { auto n = --refs; if (!n) delete this; return n; }
    IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto command = new (std::nothrow) ShellCommand;
        if (!command) return E_OUTOFMEMORY;
        auto hr = command->QueryInterface(iid, result);
        command->Release();
        return hr;
    }
    IFACEMETHODIMP LockServer(BOOL lock) override { if (lock) ++objects; else --objects; return S_OK; }
};
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid, void** result) {
    if (!result) return E_POINTER;
    *result = nullptr;
    if (clsid != CommandId) return CLASS_E_CLASSNOTAVAILABLE;
    auto factory = new (std::nothrow) Factory;
    if (!factory) return E_OUTOFMEMORY;
    auto hr = factory->QueryInterface(iid, result);
    factory->Release();
    return hr;
}
extern "C" HRESULT __stdcall DllCanUnloadNow() { return objects == 0 ? S_OK : S_FALSE; }
