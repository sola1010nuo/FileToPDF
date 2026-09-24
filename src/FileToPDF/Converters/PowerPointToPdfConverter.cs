using FileToPDF.Utilities;
namespace FileToPDF.Converters;
public sealed class PowerPointToPdfConverter : IFileConverter
{
    public bool CanConvert(string extension) => new[] { ".ppt", ".pptx" }.Contains(extension, StringComparer.OrdinalIgnoreCase);
    public void Convert(string inputPath, string outputPath)
    {
        dynamic? app = null, presentations = null, presentation = null;
        dynamic? options = null, ranges = null, range = null, slides = null;
        int oldSecurity = 1, oldAlerts = 2;
        bool configured = false;
        try
        {
            app = ComSupport.Create("PowerPoint.Application");
            oldSecurity = app.AutomationSecurity;
            oldAlerts = app.DisplayAlerts;
            configured = true;
            app.AutomationSecurity = 3;
            app.DisplayAlerts = 1; // ppAlertsNone
            presentations = app.Presentations;
            presentation = presentations.Open(inputPath, -1, -1, 0); // read-only copy, no window
            options = presentation.PrintOptions;
            ranges = options.Ranges;
            slides = presentation.Slides;
            range = ranges.Add(1, slides.Count);
            // Supply a real COM PrintRange: dynamic null is not an IDispatch pointer.
            presentation.ExportAsFixedFormat(outputPath, 2, 2, 0, 1, 1, -1,
                range, 1, "", true, true, true, true, false, Type.Missing);
        }
        finally
        {
            ComSupport.Release((object?)range);
            ComSupport.Release((object?)ranges);
            ComSupport.Release((object?)options);
            ComSupport.Release((object?)slides);
            if (presentation is not null) ComSupport.Try(() => presentation.Close());
            if (app is not null && configured)
                ComSupport.Try(() => { app.AutomationSecurity = oldSecurity; app.DisplayAlerts = oldAlerts; });
            // PowerPoint may reuse an interactive instance. Never close the user's other decks.
            if (app is not null && presentations is not null)
                ComSupport.Try(() => { if (presentations.Count == 0) app.Quit(); });
            ComSupport.Release((object?)presentation);
            ComSupport.Release((object?)presentations);
            ComSupport.Release((object?)app);
        }
    }
}
