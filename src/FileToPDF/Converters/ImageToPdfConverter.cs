using PdfSharp.Drawing;
using PdfSharp.Pdf;
namespace FileToPDF.Converters;
public sealed class ImageToPdfConverter : IFileConverter
{
    public bool CanConvert(string extension) => new[] { ".jpg", ".jpeg", ".png" }.Contains(extension, StringComparer.OrdinalIgnoreCase);
    public void Convert(string inputPath, string outputPath)
    {
        using var image = XImage.FromFile(inputPath);
        using var document = new PdfDocument();
        var page = document.AddPage();
        // Square pixels preserve aspect ratio even when DPI metadata is inconsistent.
        double scale = Math.Min(0.75, 14400d / Math.Max(image.PixelWidth, image.PixelHeight));
        double width = image.PixelWidth * scale, height = image.PixelHeight * scale;
        page.Width = XUnit.FromPoint(width);
        page.Height = XUnit.FromPoint(height);
        using (var graphics = XGraphics.FromPdfPage(page))
        {
            graphics.DrawRectangle(XBrushes.White, 0, 0, width, height);
            graphics.DrawImage(image, 0, 0, width, height);
        }
        document.Save(outputPath);
    }
}
