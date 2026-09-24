namespace FileToPDF.Services;
public sealed record ConversionResult(string Input, string? Output, string? Error);
public sealed class BatchConversionService(OutputPathService output, Action<string, string> convert)
{
    public IReadOnlyList<ConversionResult> Run(IEnumerable<string> files)
    {
        var results = new List<ConversionResult>();
        foreach (string file in files)
        {
            string? staging = null;
            try
            {
                string input = Path.GetFullPath(file);
                if (!File.Exists(input)) throw new FileNotFoundException("檔案不存在或無法存取。", input);
                _ = new ConverterFactory().Get(input);
                staging = output.CreateStagingPath();
                // Probe write access before launching Office.
                using (new FileStream(staging, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { }
                convert(input, staging);
                using (var stream = File.OpenRead(staging))
                {
                    Span<byte> header = new byte[5];
                    if (stream.Read(header) != 5 || !header.SequenceEqual("%PDF-"u8))
                        throw new IOException("轉換器沒有產生有效的 PDF。");
                }
                results.Add(new(file, output.Commit(staging, input), null));
            }
            catch (Exception ex) { results.Add(new(file, null, $"{ex.Message} (0x{ex.HResult:X8})")); }
            finally
            {
                if (staging is not null) Utilities.ComSupport.Try(() => File.Delete(staging));
            }
        }
        return results;
    }
}
