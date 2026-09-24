using FileToPDF.Converters;
using FileToPDF.Services;
using FileToPDF.Utilities;
internal static class BatchTests
{
    public static void Run(string dir)
    {
        string output = Path.Combine(dir, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(output);
        var paths = new OutputPathService(output);
        File.WriteAllText(Path.Combine(dir, "unknown.txt"), "unsupported");
        File.WriteAllText(Path.Combine(output, "photo.pdf"), "DO NOT OVERWRITE");
        var service = new BatchConversionService(paths, (input, target) => new ConverterFactory().Get(input).Convert(input, target));
        string[] files = ["photo.jpg", "broken.png", "unknown.txt", "absent.docx", "透明 image.png", "photo.jpg"];
        var results = service.Run(files.Select(f => Path.Combine(dir, f)));
        Check(results.Count == 6 && results.Count(r => r.Error is null) == 3, "batch continues after failures");
        Check(File.ReadAllText(Path.Combine(output, "photo.pdf")) == "DO NOT OVERWRITE", "existing file preserved");
        Check(File.Exists(Path.Combine(output, "photo_1.pdf")) && File.Exists(Path.Combine(output, "photo_2.pdf")), "suffixes");
        Check(!Directory.EnumerateFiles(output, ".FileToPDF-*").Any(), "no partial files");
        var failedExport = new BatchConversionService(paths, (_, target) => { File.WriteAllText(target, "partial"); throw new IOException("export failed"); });
        Check(failedExport.Run([Path.Combine(dir, "photo.jpg")])[0].Error is not null, "export error handled");
        Check(!Directory.EnumerateFiles(output, ".FileToPDF-*").Any(), "partial export removed");
        bool missingOffice = false;
        try { ComSupport.Create("FileToPDF.NonexistentOffice"); } catch (InvalidOperationException) { missingOffice = true; }
        Check(missingOffice, "missing COM registration handled");
        Check(new OutputPathService().DirectoryPath == Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "desktop API");
        Parallel.For(0, 8, i =>
        {
            string stage = paths.CreateStagingPath();
            File.WriteAllText(stage, i.ToString());
            paths.Commit(stage, "parallel.png");
        });
        Check(Directory.GetFiles(output, "parallel*.pdf").Length == 8, "concurrent collision safety");
        Check(new ConverterFactory().Get("PHOTO.JPEG") is ImageToPdfConverter, "case insensitive JPEG extension");
        Console.WriteLine("PASS: mixed batch, missing/corrupt/unsupported inputs, export failure, missing COM, Desktop API, collisions, concurrency, cleanup");
    }
    private static void Check(bool value, string name) { if (!value) throw new Exception(name); }
}
