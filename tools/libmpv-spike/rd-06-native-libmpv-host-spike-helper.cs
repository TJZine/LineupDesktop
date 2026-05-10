using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

internal static class Rd06NativeLibmpvHostSpikeHelper
{
    private const int MpvEventShutdown = 1;
    private const int MpvEventLogMessage = 2;
    private const int MpvEventStartFile = 6;
    private const int MpvEventFileLoaded = 8;
    private const int MpvEventEndFile = 7;

    private static string? libmpvPath;

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr MpvCreateDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int MpvInitializeDelegate(IntPtr context);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int MpvSetOptionStringDelegate(IntPtr context, string name, string value);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int MpvCommandDelegate(IntPtr context, IntPtr args);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr MpvWaitEventDelegate(IntPtr context, double timeout);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void MpvTerminateDestroyDelegate(IntPtr context);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MpvEvent
    {
        public readonly int event_id;
        public readonly int error;
        public readonly ulong reply_userdata;
        public readonly IntPtr data;
    }

    private sealed class InitPayload
    {
        public string? requestId { get; set; }
        public string? libmpvDll { get; set; }
        public string? parentWid { get; set; }
        public string? localMedia { get; set; }
        public string? httpMedia { get; set; }
        public string? dummyHeaderName { get; set; }
        public string? dummyHeaderValue { get; set; }
        public int durationMs { get; set; }
        public bool crashAfterInitialize { get; set; }
        public bool apiProbe { get; set; }
    }

    public static int Main()
    {
        try
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                WriteEvent("blocked", new Dictionary<string, object?> { ["reason"] = "windows-required" });
                return 2;
            }

            string? line = Console.In.ReadLine();
            if (string.IsNullOrWhiteSpace(line))
            {
                WriteEvent("blocked", new Dictionary<string, object?> { ["reason"] = "missing-private-init" });
                return 2;
            }

            InitPayload? init = JsonSerializer.Deserialize<InitPayload>(line);
            if (init == null || string.IsNullOrWhiteSpace(init.libmpvDll) || (!init.apiProbe && string.IsNullOrWhiteSpace(init.parentWid)))
            {
                WriteEvent("blocked", new Dictionary<string, object?> { ["reason"] = "invalid-private-init" });
                return 2;
            }

            libmpvPath = init.libmpvDll;
            string? libmpvDirectory = Path.GetDirectoryName(libmpvPath);
            if (!string.IsNullOrWhiteSpace(libmpvDirectory))
            {
                NativeMethods.SetDllDirectory(libmpvDirectory);
            }
            NativeLibrary.SetDllImportResolver(typeof(Rd06NativeLibmpvHostSpikeHelper).Assembly, ResolveLibmpv);

            WriteClientApiVersion();
            if (init.apiProbe)
            {
                return 0;
            }

            IntPtr mpv = NativeMethods.mpv_create();
            if (mpv == IntPtr.Zero)
            {
                WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "mpv-create" });
                return 1;
            }

            try
            {
                SetOption(mpv, "wid", init.parentWid);
                SetOption(mpv, "input-vo-keyboard", "yes");
                SetOption(mpv, "terminal", "no");
                SetOption(mpv, "msg-level", "all=no");

                int initializeResult = NativeMethods.mpv_initialize(mpv);
                WriteEvent(initializeResult == 0 ? "observed" : "failed", new Dictionary<string, object?>
                {
                    ["proof"] = "libmpv-initialize",
                    ["category"] = ResultCategory(initializeResult),
                });
                if (initializeResult != 0)
                {
                    return 1;
                }

                if (init.crashAfterInitialize)
                {
                    Environment.FailFast("rd-06 dummy helper crash");
                }

                bool localLoaded = LoadAndObserve(mpv, init.localMedia, "local-media", null, null, init.durationMs);
                if (localLoaded)
                {
                    WriteEvent("observed", new Dictionary<string, object?>
                    {
                        ["proof"] = "local-media",
                        ["activePlayback"] = true,
                    });
                    if (!WaitForContinue())
                    {
                        return 1;
                    }
                }
                LoadAndObserve(mpv, init.httpMedia, "dummy-http", init.dummyHeaderName, init.dummyHeaderValue, init.durationMs);
                Command(mpv, "stop");
                return 0;
            }
            finally
            {
                NativeMethods.mpv_terminate_destroy(mpv);
            }
        }
        catch
        {
            WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "helper-exception" });
            return 1;
        }
    }

    private static IntPtr ResolveLibmpv(string libraryName, System.Reflection.Assembly assembly, DllImportSearchPath? searchPath)
    {
        if ((libraryName == "libmpv-2.dll" || libraryName == "mpv-2.dll") && !string.IsNullOrWhiteSpace(libmpvPath))
        {
            return NativeLibrary.Load(libmpvPath);
        }
        return IntPtr.Zero;
    }

    private static bool LoadAndObserve(
        IntPtr mpv,
        string? media,
        string proof,
        string? headerName,
        string? headerValue,
        int durationMs)
    {
        if (string.IsNullOrWhiteSpace(media))
        {
            WriteEvent("blocked", new Dictionary<string, object?> { ["proof"] = proof, ["reason"] = "missing-dummy-input" });
            return false;
        }

        if (proof == "dummy-http")
        {
            if (headerName != "X-Lineup-RD06" || headerValue != "dummy")
            {
                WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "dummy-header-policy" });
                return false;
            }
            SetOption(mpv, "http-header-fields", $"{headerName}: {headerValue}");
        }
        else if (!string.IsNullOrWhiteSpace(headerName) || !string.IsNullOrWhiteSpace(headerValue))
        {
            WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "dummy-header-policy" });
            return false;
        }

        int loadResult = Command(mpv, "loadfile", media, "replace");
        WriteEvent(loadResult == 0 ? "observed" : "failed", new Dictionary<string, object?>
        {
            ["proof"] = proof,
            ["category"] = ResultCategory(loadResult),
        });
        return ObserveEvents(mpv, proof, Math.Max(500, Math.Min(durationMs, 10000)));
    }

    private static bool ObserveEvents(IntPtr mpv, string proof, int durationMs)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(durationMs);
        bool fileLoaded = false;
        bool endFile = false;
        int logEvents = 0;

        while (DateTime.UtcNow < deadline)
        {
            IntPtr eventPointer = NativeMethods.mpv_wait_event(mpv, 0.1);
            if (eventPointer == IntPtr.Zero)
            {
                continue;
            }

            MpvEvent observed = Marshal.PtrToStructure<MpvEvent>(eventPointer);
            if (observed.event_id == MpvEventFileLoaded)
            {
                fileLoaded = true;
            }
            else if (observed.event_id == MpvEventEndFile)
            {
                endFile = true;
            }
            else if (observed.event_id == MpvEventLogMessage)
            {
                logEvents += 1;
            }
            else if (observed.event_id == MpvEventShutdown)
            {
                break;
            }
            else if (observed.event_id == MpvEventStartFile)
            {
                // Start-file is intentionally folded into the final category.
            }
        }

        WriteEvent("observed", new Dictionary<string, object?>
        {
            ["proof"] = proof,
            ["fileLoaded"] = fileLoaded,
            ["endFileObserved"] = endFile,
            ["nativeLogEventCount"] = logEvents,
        });
        return fileLoaded;
    }

    private static bool WaitForContinue()
    {
        string? controlLine = Console.In.ReadLine();
        if (string.IsNullOrWhiteSpace(controlLine))
        {
            WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["reason"] = "missing-control" });
            return false;
        }

        try
        {
            using JsonDocument document = JsonDocument.Parse(controlLine);
            if (document.RootElement.TryGetProperty("control", out JsonElement control) &&
                control.ValueKind == JsonValueKind.String &&
                control.GetString() == "continue")
            {
                WriteEvent("observed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["category"] = "continued" });
                return true;
            }
        }
        catch
        {
            // Fall through to the sanitized failure event.
        }

        WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["reason"] = "invalid-control" });
        return false;
    }

    private static void WriteClientApiVersion()
    {
        ulong version = NativeMethods.mpv_client_api_version();
        WriteEvent("observed", new Dictionary<string, object?>
        {
            ["proof"] = "libmpv-client-api",
            ["category"] = "numeric-version",
            ["libmpvClientApiMajor"] = (int)(version >> 16),
            ["libmpvClientApiMinor"] = (int)(version & 0xffff),
        });
    }

    private static void SetOption(IntPtr mpv, string name, string value)
    {
        int result = NativeMethods.mpv_set_option_string(mpv, name, value);
        if (result != 0)
        {
            WriteEvent("failed", new Dictionary<string, object?>
            {
                ["proof"] = "set-option",
                ["option"] = SafeOptionName(name),
                ["category"] = ResultCategory(result),
            });
        }
    }

    private static int Command(IntPtr mpv, params string[] command)
    {
        IntPtr[] pointers = new IntPtr[command.Length + 1];
        IntPtr argv = IntPtr.Zero;
        try
        {
            for (int index = 0; index < command.Length; index += 1)
            {
                pointers[index] = Marshal.StringToHGlobalAnsi(command[index]);
            }

            argv = Marshal.AllocHGlobal(IntPtr.Size * pointers.Length);
            Marshal.Copy(pointers, 0, argv, pointers.Length);
            return NativeMethods.mpv_command(mpv, argv);
        }
        finally
        {
            if (argv != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(argv);
            }
            foreach (IntPtr pointer in pointers)
            {
                if (pointer != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(pointer);
                }
            }
        }
    }

    private static string ResultCategory(int result)
    {
        return result == 0 ? "success" : "error";
    }

    private static string SafeOptionName(string name)
    {
        return name switch
        {
            "wid" => "parent-window",
            "input-vo-keyboard" => "input-keyboard",
            "terminal" => "terminal",
            "msg-level" => "message-level",
            "http-header-fields" => "dummy-http-header",
            _ => "other",
        };
    }

    private static void WriteEvent(string kind, Dictionary<string, object?> fields)
    {
        fields["kind"] = kind;
        Console.Out.WriteLine(JsonSerializer.Serialize(fields));
        Console.Out.Flush();
    }

    private static class NativeMethods
    {
        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr mpv_create();

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong mpv_client_api_version();

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int mpv_initialize(IntPtr context);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int mpv_set_option_string(IntPtr context, string name, string value);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int mpv_command(IntPtr context, IntPtr args);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr mpv_wait_event(IntPtr context, double timeout);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void mpv_terminate_destroy(IntPtr context);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetDllDirectory(string pathName);
    }
}
