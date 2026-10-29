using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

// Targeted C: drive analysis used by DesktopPet.
//
// This is deliberately *not* a full-disk scan: the app passes a small set of
// user folders and limits, and the scanner stops on time/file caps. It only
// reads metadata and never deletes or moves anything.

internal static class DriveScan
{
    private const int Schema = 1;
    private const long Megabyte = 1024L * 1024L;

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentThread();

    [DllImport("kernel32.dll")]
    private static extern bool SetThreadPriority(IntPtr thread, int priority);

    private const int ThreadModeBackgroundBegin = 0x00010000;
    private const int ThreadModeBackgroundEnd = 0x00020000;

    private sealed class ScanOptions
    {
        public string OutDir = "";
        public string ConfigPath = "";
        public string ScanId = "";
        public bool Valid = true;
    }

    public static int Run(string[] args)
    {
        var options = Parse(args);
        if (!options.Valid)
        {
            return 2;
        }
        Directory.CreateDirectory(options.OutDir);
        try
        {
            var config = LoadConfig(options.ConfigPath);
            var result = Scan(config, options);
            AtomicWrite(Path.Combine(options.OutDir, "scan-" + options.ScanId + ".json"),
                new JavaScriptSerializer().Serialize(result));
            return 0;
        }
        catch (Exception error)
        {
            var failure = new Dictionary<string, object>
            {
                { "schema", Schema },
                { "scan_id", options.ScanId },
                { "done", true },
                { "error", error.Message }
            };
            try
            {
                AtomicWrite(Path.Combine(options.OutDir, "scan-" + options.ScanId + ".json"),
                    new JavaScriptSerializer().Serialize(failure));
            }
            catch { }
            return 1;
        }
    }

    private static ScanOptions Parse(string[] args)
    {
        var options = new ScanOptions();
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--out":
                    if (++index >= args.Length) options.Valid = false; else options.OutDir = args[index];
                    break;
                case "--config":
                    if (++index >= args.Length) options.Valid = false; else options.ConfigPath = args[index];
                    break;
                case "--scan-id":
                    if (++index >= args.Length) options.Valid = false; else options.ScanId = args[index];
                    break;
                default:
                    break;
            }
        }
        if (options.OutDir.Length == 0 || options.ConfigPath.Length == 0 || options.ScanId.Length == 0)
        {
            options.Valid = false;
        }
        return options;
    }

    private static Dictionary<string, object> LoadConfig(string path)
    {
        var text = File.ReadAllText(path, Encoding.UTF8);
        var parsed = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(text);
        if (parsed == null)
        {
            throw new InvalidDataException("empty scan config");
        }
        return parsed;
    }

    private static Dictionary<string, object> Scan(Dictionary<string, object> config, ScanOptions options)
    {
        SetThreadPriority(GetCurrentThread(), ThreadModeBackgroundBegin);
        var stopwatch = Stopwatch.StartNew();
        var startedAt = NowUnix();
        var maxSeconds = GetInt(config, "max_seconds", 60);
        var maxFiles = GetInt(config, "max_files", 200000);
        var largeMb = GetInt(config, "large_file_mb", 100);
        var documentMb = GetInt(config, "document_mb", 50);
        var maxCandidates = GetInt(config, "max_candidates", 200);
        var categories = GetDictionary(config, "categories");
        var extensionCategory = new Dictionary<string, string>();
        foreach (var pair in categories)
        {
            var category = pair.Key;
            foreach (var extension in ToStringList(pair.Value))
            {
                var normalized = extension.ToLowerInvariant();
                if (!normalized.StartsWith(".")) normalized = "." + normalized;
                extensionCategory[normalized] = category;
            }
        }
        var excludedExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var extension in ToStringList(GetValue(config, "exclude_extensions")))
        {
            excludedExtensions.Add(extension.ToLowerInvariant());
        }
        var excludedDirs = new List<string>();
        foreach (var directory in ToStringList(GetValue(config, "exclude_dirs")))
        {
            excludedDirs.Add(directory.ToLowerInvariant());
        }
        var roots = new List<string>();
        foreach (var root in ToStringList(GetValue(config, "roots")))
        {
            var expanded = Expand(root);
            if (Directory.Exists(expanded)) roots.Add(expanded);
        }
        var totals = new Dictionary<string, long>();
        var candidates = new List<Dictionary<string, object>>();
        var matched = 0;
        var matchedBytes = 0L;
        var filesScanned = 0;
        var dirsScanned = 0;
        var denied = 0;
        var cancelled = false;
        var truncated = false;
        var cancelFile = Path.Combine(options.OutDir, "cancel-" + options.ScanId);
        var progressFile = Path.Combine(options.OutDir, "scan-" + options.ScanId + ".progress.json");
        var stack = new Stack<string>();
        foreach (var root in roots) stack.Push(root);
        var lastProgress = 0L;
        while (stack.Count > 0)
        {
            if (stopwatch.Elapsed.TotalSeconds > maxSeconds)
            {
                truncated = true;
                break;
            }
            if (filesScanned >= maxFiles)
            {
                truncated = true;
                break;
            }
            if (File.Exists(cancelFile))
            {
                cancelled = true;
                break;
            }
            var directory = stack.Pop();
            dirsScanned++;
            FileSystemInfo[] entries;
            try
            {
                entries = new DirectoryInfo(directory).GetFileSystemInfos();
            }
            catch
            {
                denied++;
                continue;
            }
            foreach (var entry in entries)
            {
                if (stopwatch.Elapsed.TotalSeconds > maxSeconds || filesScanned >= maxFiles)
                {
                    truncated = true;
                    break;
                }
                FileAttributes attributes;
                try
                {
                    attributes = entry.Attributes;
                }
                catch
                {
                    denied++;
                    continue;
                }
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    continue;
                }                if (entry is DirectoryInfo)
                {
                    if (!IsExcludedDirectory(entry.FullName, entry.Name, excludedDirs))
                    {
                        stack.Push(entry.FullName);
                    }
                    continue;
                }
                var file = entry as FileInfo;
                if (file == null) continue;
                filesScanned++;
                var extension = file.Extension.ToLowerInvariant();
                if (excludedExtensions.Contains(extension)) continue;
                string category;
                if (!extensionCategory.TryGetValue(extension, out category)) continue;
                long size;
                try { size = file.Length; }
                catch { denied++; continue; }
                var threshold = category == "document" ? documentMb : largeMb;
                if (size < threshold * Megabyte) continue;
                matched++;
                matchedBytes += size;
                long total;
                totals.TryGetValue(category, out total);
                totals[category] = total + size;
                if (candidates.Count < maxCandidates * 20)
                {
                    candidates.Add(new Dictionary<string, object>
                    {
                        { "path", file.FullName },
                        { "size", size },
                        { "category", category },
                        { "mtime", ToUnix(file.LastWriteTimeUtc) },
                        { "motw", HasMarkOfTheWeb(file.FullName) }
                    });
                }
                if (stopwatch.ElapsedMilliseconds - lastProgress > 500)
                {
                    lastProgress = stopwatch.ElapsedMilliseconds;
                    WriteProgress(progressFile, options.ScanId, dirsScanned, filesScanned, matched, matchedBytes, stopwatch, false);
                }
            }
        }
        candidates.Sort((a, b) => Convert.ToInt64(b["size"]).CompareTo(Convert.ToInt64(a["size"])));
        if (candidates.Count > maxCandidates)
        {
            candidates = candidates.GetRange(0, maxCandidates);
        }
        var result = new Dictionary<string, object>
        {
            { "schema", Schema },
            { "scan_id", options.ScanId },
            { "started_at", startedAt },
            { "finished_at", NowUnix() },
            { "elapsed_ms", stopwatch.ElapsedMilliseconds },
            { "roots", roots },
            { "dirs_scanned", dirsScanned },
            { "files_scanned", filesScanned },
            { "matched", matched },
            { "bytes", matchedBytes },
            { "denied", denied },
            { "truncated", truncated },
            { "cancelled", cancelled },
            { "candidates", candidates },
            { "totals", totals },
            { "done", true }
        };
        WriteProgress(progressFile, options.ScanId, dirsScanned, filesScanned, matched, matchedBytes, stopwatch, true);
        SetThreadPriority(GetCurrentThread(), ThreadModeBackgroundEnd);
        return result;
    }

    private static bool IsExcludedDirectory(string fullPath, string name, List<string> excluded)
    {
        var lowerName = name.ToLowerInvariant();
        var lowerPath = fullPath.ToLowerInvariant();
        foreach (var item in excluded)
        {
            if (lowerName == item) return true;
            if (item.Contains("\\") && lowerPath.Contains(item)) return true;
        }
        return false;
    }

    private static bool HasMarkOfTheWeb(string path)
    {
        try
        {
            return File.Exists(path + ":Zone.Identifier");
        }
        catch
        {
            return false;
        }
    }

    private static void WriteProgress(
        string path, string scanId, int dirs, int files, int matched, long bytes, Stopwatch stopwatch, bool done)
    {
        var progress = new Dictionary<string, object>
        {
            { "schema", Schema },
            { "scan_id", scanId },
            { "dirs_scanned", dirs },
            { "files_scanned", files },
            { "matched", matched },
            { "bytes", bytes },
            { "elapsed_ms", stopwatch.ElapsedMilliseconds },
            { "done", done }
        };
        try
        {
            AtomicWrite(path, new JavaScriptSerializer().Serialize(progress));
        }
        catch { }
    }

    private static void AtomicWrite(string path, string text)
    {
        var temp = path + ".tmp";
        File.WriteAllText(temp, text, new UTF8Encoding(false));
        if (File.Exists(path))
        {
            var backup = path + ".bak";
            try
            {
                if (File.Exists(backup)) File.Delete(backup);
                File.Replace(temp, path, backup);
            }
            catch
            {
                File.Copy(temp, path, true);
                File.Delete(temp);
            }
        }
        else
        {
            File.Move(temp, path);
        }
    }

    private static string Expand(string path)
    {
        var user = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Environment.ExpandEnvironmentVariables(path.Replace("{USER}", user));
    }

    private static object GetValue(Dictionary<string, object> dictionary, string key)
    {
        object value;
        return dictionary.TryGetValue(key, out value) ? value : null;
    }

    private static Dictionary<string, object> GetDictionary(Dictionary<string, object> dictionary, string key)
    {
        var value = GetValue(dictionary, key);
        var typed = value as Dictionary<string, object>;
        return typed ?? new Dictionary<string, object>();
    }

    private static int GetInt(Dictionary<string, object> dictionary, string key, int fallback)
    {
        var value = GetValue(dictionary, key);
        if (value == null) return fallback;
        try { return Convert.ToInt32(value); }
        catch { return fallback; }
    }

    private static List<string> ToStringList(object value)
    {
        var result = new List<string>();
        if (value == null) return result;
        if (value is string)
        {
            result.Add((string)value);
            return result;
        }
        var enumerable = value as IEnumerable;
        if (enumerable == null)
        {
            result.Add(Convert.ToString(value));
            return result;
        }
        foreach (var item in enumerable)
        {
            if (item != null) result.Add(Convert.ToString(item));
        }
        return result;
    }

    private static long NowUnix()
    {
        return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    }

    private static long ToUnix(DateTime value)
    {
        return (long)(value.ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    }
}

