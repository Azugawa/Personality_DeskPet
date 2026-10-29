using System;
using Microsoft.Win32;

// Per-user autostart helper. Registry value writes avoid tricky command-line
// quoting when the install path contains spaces.

internal static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Hezhuazhua";

    public static int Run(string[] args)
    {
        var action = args.Length > 1 ? args[1] : "status";
        switch (action)
        {
            case "status":
                using (var key = Registry.CurrentUser.OpenSubKey(RunKey, false))
                {
                    return key != null && key.GetValue(ValueName) != null ? 0 : 1;
                }
            case "on":
                var app = Argument(args, "--app");
                if (app.Length == 0)
                {
                    return 2;
                }
                using (var key = Registry.CurrentUser.CreateSubKey(RunKey, true))
                {
                    if (key == null) return 1;
                    key.SetValue(ValueName, "\"" + app + "\" -- --desktop-mode", RegistryValueKind.String);
                }
                return 0;
            case "off":
                using (var key = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (key != null)
                    {
                        key.DeleteValue(ValueName, false);
                    }
                }
                return 0;
            default:
                return 2;
        }
    }

    private static string Argument(string[] args, string name)
    {
        for (var index = 0; index + 1 < args.Length; index++)
        {
            if (args[index] == name)
            {
                return args[index + 1];
            }
        }
        return "";
    }
}
