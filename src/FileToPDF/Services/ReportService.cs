using System.Text;
namespace FileToPDF.Services;
public static class ReportService
{
    public static string? Write(IReadOnlyList<ConversionResult> results)
    {
        var text = new StringBuilder($"FileToPDF {DateTime.Now:yyyy-MM-dd HH:mm:ss}\n");
        foreach (var result in results)
            text.AppendLine(result.Error is null ? $"成功：{result.Input} → {result.Output}" : $"失敗：{result.Input}\n{result.Error}");
        foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Path.GetTempPath() })
        {
            try
            {
                string dir = Path.Combine(root, "FileToPDF", "Logs");
                Directory.CreateDirectory(dir);
                string path = Path.Combine(dir, $"{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.log");
                File.WriteAllText(path, text.ToString(), Encoding.UTF8);
                return path;
            }
            catch { }
        }
        return null;
    }
}
