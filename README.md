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
