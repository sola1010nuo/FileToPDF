using FileToPDF.Converters;
using FileToPDF.Utilities;
using PdfSharp.Pdf.IO;

internal static class OfficeTests
{
    public static void Word(string dir)
    {
        dynamic app = ComSupport.Create("Word.Application");
        dynamic docs = app.Documents;
        dynamic doc = docs.Add();
        dynamic range = doc.Content;
        try
        {
            app.Visible = false;
            app.DisplayAlerts = 0;
            range.Text = "FileToPDF Word test\r中文測試與表格\r";
            dynamic end = doc.Range(doc.Content.End - 1, doc.Content.End - 1);
            dynamic tables = doc.Tables;
            dynamic table = tables.Add(end, 2, 2);
            dynamic borders = table.Borders;
            borders.Enable = 1;
            for (int row = 1; row <= 2; row++)
                for (int col = 1; col <= 2; col++)
                {
                    dynamic cell = table.Cell(row, col);
                    dynamic cellRange = cell.Range;
                    cellRange.Text = $"儲存格 {row},{col}";
                    ComSupport.Release((object)cellRange); ComSupport.Release((object)cell);
                }
            dynamic imageRange = doc.Range(0, 0);
            dynamic images = doc.InlineShapes;
            dynamic picture = images.AddPicture(Path.Combine(dir, "photo.jpg"), false, true, imageRange);
            picture.Width = 160f; picture.Height = 80f;
            foreach (object item in new object[] { picture, images, imageRange, borders, table, tables, end }) ComSupport.Release(item);
            doc.SaveAs2(Path.Combine(dir, "report.docx"), 16);
            doc.SaveAs2(Path.Combine(dir, "report.doc"), 0);
        }
        finally
        {
            doc.Close(0); app.Quit(0);
            ComSupport.Release((object)range); ComSupport.Release((object)doc);
            ComSupport.Release((object)docs); ComSupport.Release((object)app);
        }
        foreach (string ext in new[] { ".docx", ".doc" })
        {
            string output = Path.Combine(dir, "report" + ext + ".pdf");
            new WordToPdfConverter().Convert(Path.Combine(dir, "report" + ext), output);
            using var pdf = PdfReader.Open(output, PdfDocumentOpenMode.Import);
            if (pdf.PageCount != 1) throw new Exception("Word page count");
        }
        Console.WriteLine("PASS: Word .docx and .doc native export");
    }
}
