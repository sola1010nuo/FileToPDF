using FileToPDF.Utilities;
namespace FileToPDF.Converters;
public sealed class WordToPdfConverter : IFileConverter
{
    public bool CanConvert(string extension) => new[] { ".doc", ".docx" }.Contains(extension, StringComparer.OrdinalIgnoreCase);
    public void Convert(string inputPath, string outputPath)
    {
        dynamic? app = null, documents = null, document = null;
        try
        {
            app = ComSupport.Create("Word.Application");
            app.Visible = false;
            app.DisplayAlerts = 0;
            app.AutomationSecurity = 3; // msoAutomationSecurityForceDisable
            documents = app.Documents;
            document = documents.Open(FileName: inputPath, ConfirmConversions: false,
                ReadOnly: true, AddToRecentFiles: false, Visible: false,
                PasswordDocument: "", PasswordTemplate: "", NoEncodingDialog: true);
            document.ExportAsFixedFormat(OutputFileName: outputPath, ExportFormat: 17,
                OpenAfterExport: false, OptimizeFor: 0);
        }
        finally
        {
            if (document is not null) ComSupport.Try(() => document.Close(0));
            if (app is not null) ComSupport.Try(() => app.Quit(0));
            ComSupport.Release((object?)document);
            ComSupport.Release((object?)documents);
            ComSupport.Release((object?)app);
        }
    }
}
