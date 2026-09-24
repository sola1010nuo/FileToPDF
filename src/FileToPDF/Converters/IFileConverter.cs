namespace FileToPDF.Converters;
public interface IFileConverter
{
    bool CanConvert(string extension);
    void Convert(string inputPath, string outputPath);
}
