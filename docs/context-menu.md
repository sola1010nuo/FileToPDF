# Shell integration

## Components

- `src/FileToPDF.ShellExtension/FileToPDF.ShellExtension.vcxproj`: native C++17 `IExplorerCommand` DLL; no CLR, NuGet or Office dependencies.
- `FileToPDF.ShellHost.vcxproj`: tiny Win32 identity anchor with an embedded MSIX identity manifest. It is not resident and contains no conversion code.
- `packaging/ContextMenu/AppxManifest.xml`: signed sparse package; `windows.comServer` uses an STA COM surrogate, and `windows.fileExplorerContextMenus` registers one top-level command.
- `scripts/Build-ShellIntegration.ps1`: discovers VS and Windows SDK, builds the native projects, creates assets, packages and signs MSIX. The default local signing key is non-exportable in CurrentUser\My. The bundle contains only its public certificate.
- `Install-ContextMenu.ps1` / `Uninstall-ContextMenu.ps1`: per-user installation and removal. Shared functions are in `ContextMenu.Common.ps1`; only `Set-DevelopmentTrust.ps1` elevates for machine certificate trust.

The existing C# application is unchanged. `Invoke(IShellItemArray*, ...)` gathers the complete selection and calls `CreateProcessW` once, using an explicit executable path and correctly quoted arguments. The existing `Program.Main` → `BatchConversionService` → converters still owns all PDF work, desktop naming and reporting.

## Registration

Windows 11 uses a signed sparse identity package, with native payloads copied into a versioned directory under `%LOCALAPPDATA%\FileToPDF\ShellIntegration`. The converter stays at the user-selected location; `HKCU\Software\FileToPDF\ShellIntegration\ExePath` records its absolute path. The manifest's executable is the native identity host, so the C# converter does not need package identity metadata or altered behavior.

The manifest registers one file command (`Type="*"`) so mixed file extensions share one canonical command. `GetState` checks **every** selected item and hides the command unless all are filesystem files with a supported extension. Folders, virtual items, empty selections and any unsupported member are hidden. Menu construction never opens Office or reads document contents.

Windows 10 uses the same DLL via HKCU `CLSID\{5D62FC80-DF75-4807-AE2B-7E4A2597DB5C}\InprocServer32` and seven `SystemFileAssociations` verbs with `ExplorerCommandHandler` / `MultiSelectModel=Player`. No package or signing trust is needed on this path. `-Mode Legacy` is available for integration testing; normal installation uses automatic OS detection.

No global Windows 11 menu setting is changed. A successful modern install removes FileToPDF's former static verbs to avoid duplicate legacy entries. Removing the integration removes only its known CLSID, verb names, identity package and installed payload files.

## Signing and deployment

For local development, the build script creates a dedicated `CN=FileToPDF` code-signing certificate. MSIX deployment on the tested machine requires the public certificate in **LocalMachine\TrustedPeople**; CurrentUser trust was experimentally insufficient. The installer therefore requests UAC only for a narrowly scoped certificate helper. It does not elevate the per-user package installation and does not enable Developer Mode or bypass signature validation.

The helper records certificates it imports. Uninstall removes that trust only when no remaining users/packages reference the publisher; existing third-party trust is not removed. The developer's signing private key remains in CurrentUser\My for future builds. Do not distribute a private key. For release distribution, supply a trusted code-signing certificate from CurrentUser\My with `Build-ShellIntegration.ps1 -CertificateThumbprint ...` (or the same parameter on `Publish.ps1`).

## Verification

`Test-ContextMenu.ps1` exercises native COM contracts, Windows quoting, real packaged-COM activation, supported/unsupported selection state, a one-process multi-select argument probe, all seven formats to Desktop, custom EXE locations, default script-relative paths, legacy registration and repeated uninstall. It saves the prior integration target/mode and restores it after testing.

`Test.ps1 -Office` validates the unchanged converters. `Smoke-Test.ps1` launches the published executable with the same argument contract used by Explorer drag-and-drop; this is not a physical mouse drag test.

Manual checks (the development environment cannot automate native Explorer UI):

1. Install, open Explorer and right-click each supported extension. On Windows 11, verify **Convert to PDF** in the first-level menu without opening Show more options.
2. Select a DOCX, PPTX and PNG together. Invoke once and check all three PDFs on Desktop. Repeat to verify `_1` names.
3. Right-click an EXE, PDF, TXT, folder, and a mixed selection containing a PDF. The command must not appear.
4. Test a filename and EXE installation path containing spaces and Chinese characters.
5. Put `FileToPDF.ico` beside the EXE and check the icon; remove it and confirm the command still works.
6. Drag multiple supported files onto the converter EXE and verify the original behavior.
7. Uninstall and confirm the entry disappears. If Explorer has cached the handler, sign out/in and verify again. Re-run uninstall if it reported locked payloads.
8. Repeat installation, multi-select and uninstall on an actual Windows 10 x64 machine. Exercising its registry path on Windows 11 does not replace this check.

## Official references

- [Microsoft: packaged desktop Explorer commands](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/integrate-packaged-app-with-file-explorer)
- [Microsoft: sparse packages with external location](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps)
- [Microsoft: IExplorerCommand Invoke and IShellItemArray](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-invoke)
- [Microsoft: ExplorerCommandVerb sample](https://learn.microsoft.com/en-us/windows/win32/shell/samples-explorercommandverb)
- [Microsoft: MSIX certificate trust troubleshooting](https://learn.microsoft.com/en-us/windows/msix/msix-troubleshooting-guide)
