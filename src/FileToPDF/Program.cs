using FileToPDF.Services;
namespace FileToPDF;
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--internal-worker") return WorkerRunner.Run(args[1]);
        if (args.Length == 0)
        {
            Notify("請將 DOC、DOCX、PPT、PPTX、JPG、JPEG 或 PNG 檔案拖到 FileToPDF.exe。\nPDF 會自動出現在桌面。", 10);
            return 0;
        }
        try
        {
            var results = new BatchConversionService(new OutputPathService(), new WorkerRunner().Convert).Run(args);
            string? log = ReportService.Write(results);
            int failures = results.Count(r => r.Error is not null);
            if (failures > 0) Notify($"已完成 {results.Count - failures} 個，失敗 {failures} 個。\n{results.First(r => r.Error is not null).Error}\n紀錄：{log ?? "無法寫入紀錄"}", 15);
            return failures == 0 ? 0 : 1;
        }
        catch (Exception ex)
        {
            string? log = ReportService.Write([new(string.Join("; ", args), null, ex.Message)]);
            Notify($"FileToPDF 無法完成：{ex.Message}\n紀錄：{log}", 15);
            return 1;
        }
    }
    private static void Notify(string message, int seconds)
    {
        // Standard timed Windows notification; no permanent UI or background service.
        object? shell = null;
        try
        {
            shell = Utilities.ComSupport.Create("WScript.Shell");
            ((dynamic)shell).Popup(message, seconds, "FileToPDF", 64);
        }
        catch { }
        finally { Utilities.ComSupport.Release(shell); }
    }
}
