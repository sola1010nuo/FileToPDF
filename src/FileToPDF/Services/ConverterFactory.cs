using FileToPDF.Converters;
namespace FileToPDF.Services;
public sealed class ConverterFactory
{
    private readonly IFileConverter[] converters =
        [new ImageToPdfConverter(), new WordToPdfConverter(), new PowerPointToPdfConverter()];
    public IFileConverter Get(string path) => converters.FirstOrDefault(c => c.CanConvert(Path.GetExtension(path)))
        ?? throw new NotSupportedException($"不支援的副檔名：{Path.GetExtension(path)}");
}
