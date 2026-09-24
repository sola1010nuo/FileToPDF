using System.Runtime.InteropServices;
namespace FileToPDF.Utilities;
public static class ComSupport
{
    public static object Create(string progId)
    {
        var type = Type.GetTypeFromProgID(progId);
        if (type is null) throw new InvalidOperationException($"找不到 {progId}，請確認已安裝並啟用 Microsoft Office。");
        return Activator.CreateInstance(type) ?? throw new InvalidOperationException($"無法啟動 {progId}。");
    }
    public static void Release(object? value)
    {
        if (value is not null && Marshal.IsComObject(value)) Marshal.FinalReleaseComObject(value);
    }
    public static void Try(Action action) { try { action(); } catch { /* Cleanup must not mask the conversion error. */ } }
}
