# FileToPDF

FileToPDF 是一個簡單的 Windows 檔案轉 PDF 工具。

可以直接在檔案總管中使用 **Convert to PDF**，或將檔案拖曳到 `FileToPDF.exe` 進行轉換。

## 支援格式

目前支援：

- Word：DOC、DOCX
- PowerPoint：PPT、PPTX
- 圖片：JPG、JPEG、PNG

支援一次選取多個檔案，也可以混合不同格式一起轉換。

> Word 與 PowerPoint 檔案需要電腦已安裝並啟用 Microsoft Office。

---

## 使用方式

### 方法一：右鍵 Convert to PDF

安裝右鍵選單後：

1. 按滑鼠右鍵。
2. 選擇 **Convert to PDF**。
3. 轉換完成的 PDF 會自動儲存到桌面。

Windows 11 可以直接右鍵選單使用 **Convert to PDF**，可一次選取多個檔案。
選取後按右鍵 → **Convert to PDF**，程式會依序將每個檔案轉換成 PDF。

---

### 方法二：拖曳到 FileToPDF.exe

也可以直接將一個或多個檔案拖曳到：

```text
FileToPDF.exe
```

程式會自動開始轉換。

---

## 輸出位置

轉換完成的 PDF 會儲存在目前使用者的 **桌面**。
如果桌面已經存在相同名稱的 PDF，程式不會覆蓋原本的檔案，而是自動產生：

```text
report.pdf
report_1.pdf
report_2.pdf
```

原始檔案不會被修改或刪除。

---

## 安裝右鍵選單

下載專案後，在專案資料夾開啟 PowerShell，執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-ContextMenu.ps1
```

安裝完成後，即可在支援的檔案上按右鍵使用 **Convert to PDF**。

首次安裝時，Windows 可能會顯示系統管理員權限（UAC）提示，允許後即可繼續安裝。

如果安裝完成後沒有立即看到 **Convert to PDF**，可以先關閉所有檔案總管視窗後重新開啟。

如果仍然沒有出現，可以登出 Windows 後重新登入。

---

## 移除右鍵選單

如果不想再使用右鍵 **Convert to PDF**，在專案資料夾執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Uninstall-ContextMenu.ps1
```

這只會移除 FileToPDF 的右鍵選單整合，不會刪除：

- `FileToPDF.exe`
- 已經轉換完成的 PDF
- 原始檔案

---

## Build

如果要自行編譯 FileToPDF，需要：

- Windows x64
- .NET 9 SDK
- Visual Studio 2022 或 Visual Studio Build Tools
- Desktop development with C++
- Windows 11 SDK

在專案目錄執行：

```powershell
dotnet build src/FileToPDF
```

發布完整版本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish.ps1
```

發布完成後主要檔案位於：

```text
publish/win-x64/FileToPDF.exe
```

右鍵選單相關檔案位於：

```text
publish/shell-integration/
```

如果只需要 `FileToPDF.exe`，可以使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Publish.ps1 -CoreOnly
```

---

## 注意事項

- 目前僅支援 Windows x64。
- 不支援資料夾轉換。
- 不會將多張圖片合併成同一個 PDF。
- DOC、DOCX、PPT、PPTX 需要 Microsoft Office。
- JPG、JPEG、PNG 不需要 Microsoft Office。
- Office 若出現密碼、受保護檢視或啟用提示，需要先自行處理。
- 單一檔案轉換失敗不會影響其他檔案。
- 原始檔案不會被修改。
- FileToPDF 不需要常駐背景，轉換完成後程式會自動結束。

---

## License

請依專案中的 License 文件為準。