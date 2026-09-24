# FileToPDF

一個簡單的 Windows 檔案轉 PDF 工具。

不用開啟程式，只要把檔案拖到 `FileToPDF.exe` 上，就會自動轉成 PDF 並輸出到桌面。

## Supported Formats

目前支援：

- Word (`.doc`, `.docx`)
- PowerPoint (`.ppt`, `.pptx`)
- JPEG (`.jpg`, `.jpeg`)
- PNG (`.png`)

支援一次拖入多個檔案，也可以混合不同格式。

> Word 和 PowerPoint 轉換需要電腦有安裝 Microsoft Office。
> JPG / PNG 則不需要 Office。

## Usage

### 1. Build

```powershell
dotnet build src/FileToPDF
```

### 2. Publish

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish.ps1
```

完成後可以在：

```text
publish/win-x64/
```

找到：

```text
FileToPDF.exe
```

`FileToPDF.exe` 是 self-contained 的 Windows x64 執行檔，可以直接使用，不需要另外安裝 .NET。

### 3. Convert

把想轉換的檔案直接拖到 `FileToPDF.exe`：

```text
report.docx ──────┐
slides.pptx ──────┤
photo.jpg ────────┼──> FileToPDF.exe ──> Desktop
screenshot.png ───┘
```

例如：

```text
report.docx
```

轉換完成後桌面會出現：

```text
report.pdf
```

如果同名 PDF 已經存在，會自動改成：

```text
report_1.pdf
report_2.pdf
...
```

不會覆蓋原本的檔案。

## Explorer 右鍵選單

先完成 Publish，再於專案目錄執行（一般使用者 PowerShell 即可）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-ContextMenu.ps1
```

對來源檔案 `.doc`、`.docx`、`.ppt`、`.pptx`、`.jpg`、`.jpeg`、`.png` 按右鍵，選擇 **Convert to PDF**。Windows 11 通常需要先選 **顯示更多選項**。這個選單不會加在 EXE、資料夾或其他副檔名上。

右鍵選單一次處理一個選取的來源檔案；多檔案批次仍可使用原本的拖曳方式。

預設登錄 `publish/win-x64/FileToPDF.exe` 的絕對路徑；若已把 EXE 放在其他位置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-ContextMenu.ps1 -ExePath "D:\My Tools\FileToPDF.exe"
```

EXE 必須先存在，安裝腳本才會修改 Registry。搬移或重新命名 EXE 後，請指定新路徑重新安裝；在相同路徑更新 EXE 不用重裝選單。重複安裝會更新現有設定，不會產生重複選單。

移除選單：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Uninstall-ContextMenu.ps1
```

移除腳本只刪除 FileToPDF 的七個選單項目，不會刪掉 EXE、PDF、其他程式的選單或檔案關聯。重複移除也安全。兩個腳本都支援 `-WhatIf` 預覽，不需系統管理員權限。

### 實作與測試

登錄位置是目前使用者的：

```text
HKCU\Software\Classes\SystemFileAssociations\<副檔名>\shell\FileToPDF.ConvertToPdf
    (Default)       = Convert to PDF
    Icon            = "完整 EXE 路徑",0
    MultiSelectModel = Single
    command\(Default) = "完整 EXE 路徑" "%1"
```

`%1` 由 Windows 替換成被右鍵點擊的來源路徑；EXE 路徑與 `%1` 都加上引號，支援中文、空格等檔名。命令直接啟動 EXE，不經過 `cmd.exe` 或 PowerShell 解譯來源檔名。安裝／移除後用 `SHChangeNotify` 通知 Explorer 更新關聯，不必重新啟動 Explorer。

右鍵和拖曳兩種方式都進入原有 `Program.Main(string[] args)`，共用 `BatchConversionService` 與所有 Converter，這次沒有修改或複製 C# 轉換邏輯。

```powershell
# 建置並產生七種格式測試所需的素材（需要 Office）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test.ps1 -Office
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish.ps1
# 實際暫時登錄 HKCU，透過 Windows Shell 選單呼叫七種格式並驗證桌面 PDF
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-ContextMenu.ps1
```

選單整合測試會保存並還原原本的 FileToPDF 登錄設定，清除本次生成的桌面 PDF；測試素材保留在 `artifacts/tests`。涵蓋重複安裝／移除、無效 EXE 路徑、含空格的 EXE 路徑、中文及特殊字元來源檔名、同名 PDF 遞增，以及保留其他選單項目。

參考：[Microsoft 檔案類型登錄](https://learn.microsoft.com/en-us/windows/win32/shell/fa-file-types)、[Windows 11 傳統選單](https://blogs.windows.com/blog/2021/07/19/extending-the-context-menu-and-share-dialog-in-windows-11/)。

## Command Line

也可以直接從 PowerShell 使用：

```powershell
.\FileToPDF.exe "D:\Documents\report.docx"
```

或一次轉換多個檔案：

```powershell
.\FileToPDF.exe "D:\Documents\report.docx" "D:\Images\photo.png"
```

## Requirements

- Windows 10 / 11 x64
- Word / PowerPoint 轉換需要 Microsoft Office
- 圖片轉換不需要 Office

## Current Limitations

- 目前只支援 Windows
- 不支援資料夾批次轉換
- 不支援多張圖片合併成同一個 PDF
- 受密碼保護的 Office 文件可能無法轉換
- PowerPoint 動畫、影片等互動內容不會保留在 PDF 中
