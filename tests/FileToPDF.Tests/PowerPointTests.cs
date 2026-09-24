using FileToPDF.Converters;
using FileToPDF.Utilities;
using PdfSharp.Pdf.IO;
internal static class PowerPointTests
{
    public static void Run(string dir)
    {
        dynamic app = ComSupport.Create("PowerPoint.Application");
        dynamic presentations = app.Presentations;
        dynamic presentation = presentations.Add(0);
        dynamic setup = presentation.PageSetup;
        dynamic slides = presentation.Slides;
        dynamic slide = slides.Add(1, 12);
        dynamic shapes = slide.Shapes;
        dynamic box = shapes.AddTextbox(1, 80f, 80f, 600f, 100f);
        dynamic frame = box.TextFrame;
        dynamic range = frame.TextRange;
        try
        {
            setup.SlideWidth = 960f; setup.SlideHeight = 540f;
            range.Text = "FileToPDF PowerPoint 16:9 中文測試";
            dynamic picture = shapes.AddPicture(Path.Combine(dir, "photo.jpg"), 0, -1, 80f, 220f, 400f, 200f);
            dynamic rectangle = shapes.AddShape(1, 560f, 250f, 220f, 120f);
            ComSupport.Release((object)rectangle); ComSupport.Release((object)picture);
            presentation.SaveAs(Path.Combine(dir, "slides.pptx"), 24);
            presentation.SaveAs(Path.Combine(dir, "slides.ppt"), 1);
        }
        finally
        {
            presentation.Close(); if (presentations.Count == 0) app.Quit();
            foreach (object item in new object[] { range, frame, box, shapes, slide, slides, setup, presentation, presentations, app }) ComSupport.Release(item);
        }
        foreach (string ext in new[] { ".pptx", ".ppt" })
        {
            string output = Path.Combine(dir, "slides" + ext + ".pdf");
            new PowerPointToPdfConverter().Convert(Path.Combine(dir, "slides" + ext), output);
            using var pdf = PdfReader.Open(output, PdfDocumentOpenMode.Import);
            if (pdf.PageCount != 1 || Math.Abs(pdf.Pages[0].Width.Point / pdf.Pages[0].Height.Point - 16d / 9) > .001)
                throw new Exception("PowerPoint page ratio");
        }
        Console.WriteLine("PASS: PowerPoint .pptx and .ppt native export, 16:9 ratio");
    }
}
