using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// Small Windows sensor helper for DeskPet.
//
// It only reads local state: CPU usage, foreground process, idle time, C: free
// space and top processes. It never opens a network connection and never writes
// outside the output directory passed by the app.
//
// Usage:
//   DeskPetSentinel.exe --run --parent <pid> --out <dir>
//   DeskPetSentinel.exe --once --out <dir>\once.json

internal static class Program
{
    private const int Schema = 1;

    [STAThread]
    private static int Main(string[] args)
    {
        if (HasArgument(args, "--autostart"))
        {
            return Autostart.Run(args);
        }
        if (HasArgument(args, "--scan-index"))
        {
            return DriveScan.RunIndex(args);
        }
        if (HasArgument(args, "--scan"))
        {
            return DriveScan.Run(args);
        }
        var options = Options.Parse(args);
        if (!options.Valid)
        {
            return 2;
        }
        try
        {
            if (options.Once)
            {
                Directory.CreateDirectory(options.OutDir);
                var collector = new Collector(options);
                var snapshot = collector.Collect(options, 0);
                File.WriteAllText(Path.Combine(options.OutDir, "once.json"),
                    new JavaScriptSerializer().Serialize(snapshot), new UTF8Encoding(false));
                return 0;
            }
            if (options.Run)
            {
                return Run(options);
            }
            return 2;
        }
        catch (Exception error)
        {
            try
            {
                Directory.CreateDirectory(options.OutDir);
                File.WriteAllText(Path.Combine(options.OutDir, "helper-error.txt"), error.ToString());
            }
            catch { }
            return 1;
        }
    }

    private static int Run(Options options)
    {
        Directory.CreateDirectory(options.OutDir);
        bool created;
        using (var mutex = new Mutex(true, "DeskPetSentinel_" + options.ParentPid, out created))
        {
            if (!created)
            {
                return 0;
            }
            var statePath = Path.Combine(options.OutDir, "state.json");
            var serializer = new JavaScriptSerializer();
            var collector = new Collector(options);
            long seq = 0;
            while (true)
            {
                if (options.ParentPid > 0 && !ProcessExists(options.ParentPid))
                {
                    return 0;
                }
                seq++;
                Dictionary<string, object> snapshot;
                try
                {
                    snapshot = collector.Collect(options, seq);
                }
                catch (Exception error)
                {
                    snapshot = new Dictionary<string, object>
                    {
                        { "schema", Schema },
                        { "seq", seq },
                        { "ts", NowUnix() },
                        { "available", false },
                        { "error", error.Message }
                    };
                }
                try
                {
                    AtomicWrite(statePath, serializer.Serialize(snapshot));
                }
                catch
                {
                    // Keep sampling; the app treats a stale file as unavailable.
                }
                Thread.Sleep(1000);
            }
        }
    }

    private static bool ProcessExists(int pid)
    {
        try
        {
            var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }

    private static bool HasArgument(string[] args, string name)
    {
        foreach (var argument in args)
        {
            if (argument == name)
            {
                return true;
            }
        }
        return false;
    }

    private static double NowUnix()
    {
        return (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
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

    private sealed class Options
    {
        public bool Run;
        public bool Once;
        public bool CaptureTitles;
        public int ParentPid;
        public string OutDir = "";
        public bool Valid = true;

        public static Options Parse(string[] args)
        {
            var options = new Options();
            for (var i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--run": options.Run = true; break;
                    case "--once": options.Once = true; break;
                    case "--titles": options.CaptureTitles = true; break;
                    case "--parent":
                        if (++i >= args.Length || !int.TryParse(args[i], out options.ParentPid)) options.Valid = false;
                        break;
                    case "--out":
                        if (++i >= args.Length) options.Valid = false; else options.OutDir = args[i];
                        break;
                    default:
                        break;
                }
            }
            if (options.OutDir.Length == 0 || (!options.Run && !options.Once))
            {
                options.Valid = false;
            }
            return options;
        }
    }

    private sealed class Collector
    {
        private readonly Options _options;
        private ulong _previousIdle;
        private ulong _previousKernel;
        private ulong _previousUser;
        private bool _haveCpu;
        private Dictionary<int, TimeSpan> _previousProcessCpu = new Dictionary<int, TimeSpan>();
        private DateTime _previousProcessSample = DateTime.UtcNow;
        private Dictionary<string, object> _disk = new Dictionary<string, object>();
        private Dictionary<string, object> _processes = new Dictionary<string, object>();
        private int _ticks;

        public Collector(Options options)
        {
            _options = options;
        }

        public Dictionary<string, object> Collect(Options options, long seq)
        {
            _ticks++;
            var cpu = ReadCpuPercent();
            if (_ticks == 1 || _ticks % 5 == 0)
            {
                _processes = ReadTopProcesses();
            }
            if (_ticks == 1 || _ticks % 30 == 0)
            {
                _disk = ReadDisk();
            }
            var foreground = ReadForeground(options.CaptureTitles);
            var snapshot = new Dictionary<string, object>
            {
                { "schema", Schema },
                { "seq", seq },
                { "ts", NowUnix() },
                { "cpu_percent", cpu },
                { "idle_seconds", ReadIdleSeconds() },
                { "foreground", foreground },
                { "disk_c", _disk },
                { "processes", _processes },
                { "available", true }
            };
            return snapshot;
        }

        private double ReadCpuPercent()
        {
            FILETIME idle;
            FILETIME kernel;
            FILETIME user;
            if (!Native.GetSystemTimes(out idle, out kernel, out user))
            {
                return 0;
            }
            var idleTicks = ToUInt64(idle);
            var kernelTicks = ToUInt64(kernel);
            var userTicks = ToUInt64(user);
            if (!_haveCpu)
            {
                _previousIdle = idleTicks;
                _previousKernel = kernelTicks;
                _previousUser = userTicks;
                _haveCpu = true;
                return 0;
            }
            var idleDelta = idleTicks - _previousIdle;
            var totalDelta = (kernelTicks - _previousKernel) + (userTicks - _previousUser);
            _previousIdle = idleTicks;
            _previousKernel = kernelTicks;
            _previousUser = userTicks;
            if (totalDelta == 0)
            {
                return 0;
            }
            var value = (totalDelta - idleDelta) * 100.0 / totalDelta;
            if (value < 0) value = 0;
            if (value > 100) value = 100;
            return Math.Round(value, 1);
        }

        private Dictionary<string, object> ReadDisk()
        {
            var result = new Dictionary<string, object>();
            try
            {
                var drive = new DriveInfo("C");
                result["total"] = drive.TotalSize;
                result["free"] = drive.AvailableFreeSpace;
                result["ok"] = true;
            }
            catch (Exception error)
            {
                result["ok"] = false;
                result["error"] = error.Message;
            }
            return result;
        }

        private Dictionary<string, object> ReadForeground(bool captureTitle)
        {
            var result = new Dictionary<string, object> { { "process", "" }, { "pid", 0 }, { "fullscreen", false } };
            try
            {
                var window = Native.GetForegroundWindow();
                if (window == IntPtr.Zero)
                {
                    return result;
                }
                uint pid;
                Native.GetWindowThreadProcessId(window, out pid);
                result["pid"] = (int)pid;
                result["process"] = ProcessName((int)pid);
                if (captureTitle)
                {
                    var builder = new StringBuilder(512);
                    Native.GetWindowText(window, builder, builder.Capacity);
                    result["title"] = builder.ToString();
                }
                RECT bounds;
                if (Native.GetWindowRect(window, out bounds))
                {
                    var monitor = Native.MonitorFromWindow(window, 2);
                    if (monitor != IntPtr.Zero)
                    {
                        var info = new MONITORINFO();
                        info.cbSize = (uint)Marshal.SizeOf(typeof(MONITORINFO));
                        if (Native.GetMonitorInfo(monitor, ref info))
                        {
                            var width = info.rcMonitor.right - info.rcMonitor.left;
                            var height = info.rcMonitor.bottom - info.rcMonitor.top;
                            var windowWidth = bounds.right - bounds.left;
                            var windowHeight = bounds.bottom - bounds.top;
                            result["fullscreen"] = Math.Abs(windowWidth - width) <= 2 && Math.Abs(windowHeight - height) <= 2;
                        }
                    }
                }
            }
            catch
            {
            }
            return result;
        }

        private Dictionary<string, object> ReadTopProcesses()
        {
            var now = DateTime.UtcNow;
            var elapsed = (now - _previousProcessSample).TotalSeconds;
            if (elapsed <= 0.2) elapsed = 1;
            var current = new Dictionary<int, TimeSpan>();
            var scored = new List<KeyValuePair<string, double>>();
            Process[] processes;
            try
            {
                processes = Process.GetProcesses();
            }
            catch
            {
                return new Dictionary<string, object>();
            }
            foreach (var process in processes)
            {
                try
                {
                    var total = process.TotalProcessorTime;
                    current[process.Id] = total;
                    TimeSpan previous;
                    if (_previousProcessCpu.TryGetValue(process.Id, out previous))
                    {
                        var delta = (total - previous).TotalSeconds;
                        var percent = delta / elapsed / Environment.ProcessorCount * 100.0;
                        if (percent > 0.05)
                        {
                            scored.Add(new KeyValuePair<string, double>(process.ProcessName + ".exe", Math.Round(percent, 1)));
                        }
                    }
                }
                catch
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
            _previousProcessCpu = current;
            _previousProcessSample = now;
            scored.Sort((a, b) => b.Value.CompareTo(a.Value));
            var list = new List<Dictionary<string, object>>();
            for (var i = 0; i < scored.Count && i < 8; i++)
            {
                list.Add(new Dictionary<string, object>
                {
                    { "process", scored[i].Key },
                    { "cpu_percent", scored[i].Value }
                });
            }
            return new Dictionary<string, object> { { "list", list } };
        }

        private int ReadIdleSeconds()
        {
            var info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!Native.GetLastInputInfo(ref info))
            {
                return 0;
            }
            var tick = unchecked((uint)Environment.TickCount);
            var idle = unchecked(tick - info.dwTime) / 1000u;
            return (int)idle;
        }

        private static string ProcessName(int pid)
        {
            try
            {
                var handle = Native.OpenProcess(0x1000, false, pid);
                if (handle != IntPtr.Zero)
                {
                    try
                    {
                        var builder = new StringBuilder(1024);
                        var size = builder.Capacity;
                        if (Native.QueryFullProcessImageName(handle, 0, builder, ref size))
                        {
                            return Path.GetFileName(builder.ToString());
                        }
                    }
                    finally
                    {
                        Native.CloseHandle(handle);
                    }
                }
            }
            catch
            {
            }
            try
            {
                using (var process = Process.GetProcessById(pid))
                {
                    return process.ProcessName + ".exe";
                }
            }
            catch
            {
                return "";
            }
        }

        private static ulong ToUInt64(FILETIME value)
        {
            return ((ulong)value.dwHighDateTime << 32) | value.dwLowDateTime;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FILETIME
    {
        public uint dwLowDateTime;
        public uint dwHighDateTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO
    {
        public uint cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    private static class Native
    {
        [DllImport("kernel32.dll")]
        public static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr window, out RECT rect);

        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

        [DllImport("user32.dll")]
        public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

        [DllImport("user32.dll")]
        public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr window, StringBuilder text, int count);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref int size);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);
    }
}
