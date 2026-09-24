using FileToPDF.Converters;
using PdfSharp.Pdf.IO;
using System.Drawing;
using System.Drawing.Imaging;

internal static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir = Path.GetFullPath("artifacts/tests");
        Directory.CreateDirectory(dir);
        using (var bitmap = new Bitmap(400, 200))
        {
            using var g = Graphics.FromImage(bitmap);
            g.Clear(Color.Transparent);
            using var brush = new SolidBrush(Color.FromArgb(128, 255, 0, 0));
            g.FillRectangle(brush, 100, 50, 200, 100);
            bitmap.Save(Path.Combine(dir, "透明 image.png"), ImageFormat.Png);
            g.Clear(Color.White);
            g.FillEllipse(Brushes.Blue, 50, 25, 300, 150);
            bitmap.Save(Path.Combine(dir, "photo.jpg"), ImageFormat.Jpeg);
        }
        var converter = new ImageToPdfConverter();
        foreach (string name in new[] { "透明 image.png", "photo.jpg" })
        {
            string pdf = Path.Combine(dir, name + ".pdf");
            converter.Convert(Path.Combine(dir, name), pdf);
            using var doc = PdfReader.Open(pdf, PdfDocumentOpenMode.Import);
            Check(doc.PageCount == 1, "one page");
            Check(Math.Abs(doc.Pages[0].Width.Point / doc.Pages[0].Height.Point - 2) < .001, "aspect ratio");
        }
        File.WriteAllText(Path.Combine(dir, "broken.png"), "not an image");
        bool rejected = false;
        try { converter.Convert(Path.Combine(dir, "broken.png"), Path.Combine(dir, "broken.pdf")); }
        catch { rejected = true; }
        Check(rejected, "corrupt image rejected");
        Console.WriteLine("PASS: image conversion, transparency fixture, aspect ratio, corrupt image");
        if (args.Contains("--word")) OfficeTests.Word(dir); if (args.Contains("--powerpoint")) PowerPointTests.Run(dir); BatchTests.Run(dir); return 0;
    }
    static void Check(bool value, string name) { if (!value) throw new Exception(name); }
}



