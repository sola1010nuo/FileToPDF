using System.Diagnostics;
using System.Text.Json;
namespace FileToPDF.Services;
public sealed record WorkerRequest(string Input, string Output, string ErrorFile);
public sealed class WorkerRunner
{
    public void Convert(string input, string output)
    {
        string requestPath = Path.Combine(Path.GetTempPath(), $"FileToPDF-{Guid.NewGuid():N}.json");
        string errorPath = requestPath + ".error";
        try
        {
            File.WriteAllText(requestPath, JsonSerializer.Serialize(new WorkerRequest(input, output, errorPath)));
            string exe = Environment.ProcessPath ?? throw new IOException("無法取得程式路徑。");
            var start = new ProcessStartInfo(exe) { UseShellExecute = false, CreateNoWindow = true };
            if (Path.GetFileNameWithoutExtension(exe).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(Path.Combine(AppContext.BaseDirectory, "FileToPDF.dll"));
            start.ArgumentList.Add("--internal-worker");
            start.ArgumentList.Add(requestPath);
            using var process = Process.Start(start) ?? throw new IOException("無法啟動轉換程序。");
            if (!process.WaitForExit(180_000))
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5000);
                throw new TimeoutException("轉換超過 180 秒，已跳過此檔案；請檢查 Office 是否等待密碼或其他對話方塊。");
            }
            if (process.ExitCode != 0)
                throw new IOException(File.Exists(errorPath) ? File.ReadAllText(errorPath) : $"轉換程序失敗（代碼 {process.ExitCode}）。");
        }
        finally
        {
            Utilities.ComSupport.Try(() => File.Delete(requestPath));
            Utilities.ComSupport.Try(() => File.Delete(errorPath));
        }
    }
    public static int Run(string requestPath)
    {
        WorkerRequest? request = null;
        try
        {
            request = JsonSerializer.Deserialize<WorkerRequest>(File.ReadAllText(requestPath))
                ?? throw new IOException("無效的轉換要求。");
            new ConverterFactory().Get(request.Input).Convert(request.Input, request.Output);
            return 0;
        }
        catch (Exception ex)
        {
            if (request is not null) Utilities.ComSupport.Try(() => File.WriteAllText(request.ErrorFile,
                $"無法轉換：{ex.Message}\n請確認檔案未損壞，Office 已安裝並啟用，且輸出目錄可以寫入。"));
            return 1;
        }
    }
}
