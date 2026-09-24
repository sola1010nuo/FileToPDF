namespace FileToPDF.Services;
public sealed class OutputPathService
{
    public string DirectoryPath { get; }
    public OutputPathService(string? directory = null)
    {
        DirectoryPath = directory ?? Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        if (string.IsNullOrWhiteSpace(DirectoryPath)) throw new IOException("無法取得目前使用者的 Desktop 路徑。");
        if (!Directory.Exists(DirectoryPath)) throw new DirectoryNotFoundException($"輸出目錄不存在：{DirectoryPath}");
    }
    public string CreateStagingPath() => Path.Combine(DirectoryPath, $".FileToPDF-{Guid.NewGuid():N}.tmp.pdf");
    public string Commit(string stagingPath, string inputPath)
    {
        string stem = Path.GetFileNameWithoutExtension(inputPath);
        for (int index = 0; ; index++)
        {
            string suffix = index == 0 ? "" : $"_{index}";
            string path = Path.Combine(DirectoryPath, $"{stem}{suffix}.pdf");
            try { File.Move(stagingPath, path, overwrite: false); return path; }
            catch (IOException) when (File.Exists(path) || Directory.Exists(path)) { }
        }
    }
}
