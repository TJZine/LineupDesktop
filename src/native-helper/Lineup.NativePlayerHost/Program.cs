using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Lineup.NativePlayerHost
{
    internal static class Program
    {
        private const int MpvEventShutdown = 1;
        private const int MpvEventStartFile = 6;
        private const int MpvEventEndFile = 7;
        private const int MpvEventFileLoaded = 8;
        private const int MpvEventPropertyChange = 22;

        private const int MpvFormatFlag = 1;
        private const int MpvFormatString = 2;
        private const int MpvFormatDouble = 8;

        private const int GlColorBufferBit = 0x00004000;
        private const int SwpShowWindow = 0x0040;
        private static readonly IntPtr HwndTopmost = new IntPtr(-1);
        private static readonly object MpvLock = new object();

        private static string? libmpvPath;
        private static bool libmpvResolverRegistered = false;
        private static IntPtr mpvContext = IntPtr.Zero;
        private static string? currentRequestId;
        private static string? currentMediaId;
        private static string? currentMediaTitle;
        private static double cachedDurationSeconds = 0;
        private static bool isPaused = false;
        private static bool isBuffering = false;

        private static RenderSurface? renderSurface;
        private static Thread? renderThread;
        private static Thread? eventThread;
        private static bool renderThreadRunning = false;
        private static IntPtr renderContext = IntPtr.Zero;

        [StructLayout(LayoutKind.Sequential)]
        private struct MpvEvent
        {
            public int event_id;
            public int error;
            public ulong reply_userdata;
            public IntPtr data;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MpvEventProperty
        {
            public string name;
            public int format;
            public IntPtr data;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MpvRenderParam
        {
            public int type;
            public IntPtr data;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MpvOpenGlInitParams
        {
            public IntPtr get_proc_address;
            public IntPtr get_proc_address_ctx;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MpvOpenGlFbo
        {
            public int fbo;
            public int w;
            public int h;
            public int internal_format;
        }

        public sealed class InputMessage
        {
            public string? type { get; set; }
            public string? requestId { get; set; }
            public string? command { get; set; }
            public JsonElement payload { get; set; }
            public PlaybackSetup? setup { get; set; }
            public string? playbackUrl { get; set; }
            public CredentialHeader? credentialHeader { get; set; }
        }

        public sealed class PlaybackSetup
        {
            public string? playbackMode { get; set; }
            public string? mediaPath { get; set; }
            public string? variantId { get; set; }
            public string? partPath { get; set; }
            public TrackSelection? selectedTrackIds { get; set; }
            public PrivateTrackSelection? selectedPrivateTrackIds { get; set; }
        }

        public sealed class TrackSelection
        {
            public string? video { get; set; }
            public string? audio { get; set; }
            public string? subtitle { get; set; }
        }

        public sealed class PrivateTrackSelection
        {
            public string? video { get; set; }
            public string? audio { get; set; }
            public string? subtitle { get; set; }
        }

        public sealed class CredentialHeader
        {
            public string? name { get; set; }
            public string? value { get; set; }
        }

        public static int Main(string[] args)
        {
            try
            {
                if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    // Safe OS-level guard
                    WriteEvent("blocked", new Dictionary<string, object?> { ["reason"] = "windows-required" });
                    return 2;
                }

                ConfigureLibmpvPath(args);

                // Process stdin NDJSON stream
                Thread commandThread = new Thread(CommandLoop)
                {
                    IsBackground = true,
                    Name = "LineupCommandLoop"
                };
                commandThread.Start();

                commandThread.Join();
                return 0;
            }
            catch (Exception)
            {
                WriteEvent("failed", new Dictionary<string, object?> { ["error"] = "helper-exception" });
                return 1;
            }
        }

        private static void CommandLoop()
        {
            while (true)
            {
                string? line = Console.In.ReadLine();
                if (line == null)
                {
                    break;
                }

                if (string.IsNullOrWhiteSpace(line))
                {
                    continue;
                }

                try
                {
                    InputMessage? message = JsonSerializer.Deserialize<InputMessage>(line);
                    if (message == null)
                    {
                        continue;
                    }

                    if (message.type == "cleanup")
                    {
                        HandleCleanup(message.requestId);
                        break;
                    }

                    if (message.type == "command" && message.requestId != null && message.command != null)
                    {
                        currentRequestId = message.requestId;
                        HandleCommand(message);
                    }
                }
                catch (Exception ex)
                {
                    WriteResult(currentRequestId ?? "unknown", false, "PLAYER_HELPER_PARSE_ERROR", ex.Message);
                }
            }
        }

        private static void HandleCommand(InputMessage msg)
        {
            try
            {
                if (msg.command != "load" && mpvContext == IntPtr.Zero)
                {
                    WriteResult(msg.requestId!, false, "PLAYER_HELPER_NOT_READY", "Player helper has not loaded media.");
                    return;
                }

                if (msg.command == "load")
                {
                    if (msg.playbackUrl == null || msg.setup == null)
                    {
                        WriteResult(msg.requestId!, false, "PLAYER_HELPER_INVALID_COMMAND", "Missing playbackUrl or setup details.");
                        return;
                    }

                    InitializeMpv(msg);
                    currentRequestId = msg.requestId;
                    CacheLoadedMedia(msg);

                    // Configure headers
                    if (msg.credentialHeader != null && !string.IsNullOrEmpty(msg.credentialHeader.name) && !string.IsNullOrEmpty(msg.credentialHeader.value))
                    {
                        SetOption(mpvContext, "http-header-fields", $"{msg.credentialHeader.name}: {msg.credentialHeader.value}");
                    }

                    // Load media
                    int loadResult = Command(mpvContext, "loadfile", msg.playbackUrl, "replace");
                    if (loadResult == 0)
                    {
                        ApplySelectedPrivateTracks(msg.setup.selectedPrivateTrackIds);

                        // Generate loading event
                        WriteOutputEvent(new Dictionary<string, object?>
                        {
                            ["type"] = "playback.state",
                            ["requestId"] = msg.requestId,
                            ["status"] = "buffering",
                            ["playing"] = false
                        });

                        WriteResult(msg.requestId!, true, null, null);
                    }
                    else
                    {
                        WriteResult(msg.requestId!, false, "PLAYER_HELPER_LOAD_FAILED", "Failed to load playbackUrl.");
                    }
                }
                else if (msg.command == "play")
                {
                    SetPropertyBool(mpvContext, "pause", false);
                    WriteResult(msg.requestId!, true, null, null);
                }
                else if (msg.command == "pause")
                {
                    SetPropertyBool(mpvContext, "pause", true);
                    WriteResult(msg.requestId!, true, null, null);
                }
                else if (msg.command == "stop")
                {
                    Command(mpvContext, "stop");
                    WriteResult(msg.requestId!, true, null, null);
                }
                else if (msg.command == "seek.absolute")
                {
                    double positionSeconds = 0;
                    if (msg.payload.TryGetProperty("positionMs", out JsonElement val))
                    {
                        positionSeconds = val.GetDouble() / 1000.0;
                    }
                    Command(mpvContext, "seek", positionSeconds.ToString("F3"), "absolute");
                    WriteResult(msg.requestId!, true, null, null);
                }
                else if (msg.command == "seek.relative")
                {
                    double deltaSeconds = 0;
                    if (msg.payload.TryGetProperty("deltaMs", out JsonElement val))
                    {
                        deltaSeconds = val.GetDouble() / 1000.0;
                    }
                    Command(mpvContext, "seek", deltaSeconds.ToString("F3"), "relative");
                    WriteResult(msg.requestId!, true, null, null);
                }
                else if (msg.command == "volume.set")
                {
                    double volume = 100;
                    if (msg.payload.TryGetProperty("volume", out JsonElement val))
                    {
                        volume = val.GetDouble();
                    }
                    SetPropertyDouble(mpvContext, "volume", volume);
                    WriteResult(msg.requestId!, true, null, null);
                }
                else if (msg.command == "mute.set")
                {
                    bool muted = false;
                    if (msg.payload.TryGetProperty("muted", out JsonElement val))
                    {
                        muted = val.GetBoolean();
                    }
                    SetPropertyBool(mpvContext, "mute", muted);
                    WriteResult(msg.requestId!, true, null, null);
                }
                else
                {
                    WriteResult(msg.requestId!, false, "PLAYER_HELPER_UNSUPPORTED_COMMAND", $"Command {msg.command} is not supported.");
                }
            }
            catch (Exception ex)
            {
                WriteResult(msg.requestId!, false, "PLAYER_HELPER_COMMAND_EXCEPTION", ex.Message);
            }
        }

        private static void InitializeMpv(InputMessage msg)
        {
            lock (MpvLock)
            {
                if (mpvContext != IntPtr.Zero)
                {
                    TeardownMpvContext();
                }

                EnsureLibmpvResolverRegistered();

                mpvContext = NativeMethods.mpv_create();
                if (mpvContext == IntPtr.Zero)
                {
                    throw new InvalidOperationException("Failed to create libmpv context.");
                }

                SetOption(mpvContext, "terminal", "no");
                SetOption(mpvContext, "msg-level", "all=no");
                SetOption(mpvContext, "vo", "libmpv");
                SetOption(mpvContext, "osc", "no");

                int initResult = NativeMethods.mpv_initialize(mpvContext);
                if (initResult != 0)
                {
                    throw new InvalidOperationException($"Failed to initialize libmpv: {initResult}");
                }

                // Create topmost presentation window
                renderSurface = RenderSurface.TryCreate();
                if (renderSurface == null)
                {
                    throw new InvalidOperationException("Failed to create presentation render window.");
                }

                // Create OpenGL Render Context
                IntPtr apiType = Marshal.StringToHGlobalAnsi("opengl");
                MpvOpenGlInitParams initParams = new MpvOpenGlInitParams
                {
                    get_proc_address = Marshal.GetFunctionPointerForDelegate((MpvOpenGlGetProcAddressDelegate)GetOpenGlProcAddress),
                    get_proc_address_ctx = IntPtr.Zero
                };
                IntPtr initParamsPtr = Marshal.AllocHGlobal(Marshal.SizeOf<MpvOpenGlInitParams>());
                Marshal.StructureToPtr(initParams, initParamsPtr, false);

                IntPtr initParamArray = AllocRenderParams(
                    new MpvRenderParam { type = 1, data = apiType },
                    new MpvRenderParam { type = 2, data = initParamsPtr }
                );

                renderSurface.MakeCurrent();
                int contextResult = NativeMethods.mpv_render_context_create(out renderContext, mpvContext, initParamArray);
                NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);

                Marshal.FreeHGlobal(initParamArray);
                Marshal.FreeHGlobal(initParamsPtr);
                Marshal.FreeHGlobal(apiType);

                if (contextResult != 0 || renderContext == IntPtr.Zero)
                {
                    throw new InvalidOperationException($"Failed to create libmpv render context: {contextResult}");
                }

                // Start rendering thread
                renderThreadRunning = true;
                renderThread = new Thread(RenderLoop)
                {
                    IsBackground = true,
                    Name = "LineupRenderLoop"
                };
                renderThread.Start();

                // Observe properties
                NativeMethods.mpv_observe_property(mpvContext, 1, "time-pos", MpvFormatDouble);
                NativeMethods.mpv_observe_property(mpvContext, 2, "duration", MpvFormatDouble);
                NativeMethods.mpv_observe_property(mpvContext, 3, "pause", MpvFormatFlag);
                NativeMethods.mpv_observe_property(mpvContext, 4, "core-idle", MpvFormatFlag);

                // Start Event Poll Loop
                eventThread = new Thread(EventPollLoop)
                {
                    IsBackground = true,
                    Name = "LineupEventPollLoop"
                };
                eventThread.Start();
            }
        }

        private static void EventPollLoop()
        {
            while (mpvContext != IntPtr.Zero)
            {
                IntPtr eventPtr = NativeMethods.mpv_wait_event(mpvContext, 0.1);
                if (eventPtr == IntPtr.Zero)
                {
                    continue;
                }

                MpvEvent ev = Marshal.PtrToStructure<MpvEvent>(eventPtr);
                if (ev.event_id == MpvEventShutdown)
                {
                    break;
                }
                else if (ev.event_id == MpvEventFileLoaded)
                {
                    WriteOutputEvent(new Dictionary<string, object?>
                    {
                        ["type"] = "media.loaded",
                        ["requestId"] = currentRequestId,
                        ["media"] = new Dictionary<string, object?>
                        {
                            ["id"] = currentMediaId ?? "unknown-media",
                            ["title"] = currentMediaTitle ?? "Untitled Media"
                        },
                        ["durationMs"] = (int)(cachedDurationSeconds * 1000),
                        ["tracks"] = new List<object>()
                    });

                    isBuffering = false;
                    UpdatePlaybackState();
                }
                else if (ev.event_id == MpvEventEndFile)
                {
                    WriteOutputEvent(new Dictionary<string, object?>
                    {
                        ["type"] = "ended",
                        ["requestId"] = currentRequestId
                    });
                }
                else if (ev.event_id == MpvEventPropertyChange)
                {
                    MpvEventProperty prop = Marshal.PtrToStructure<MpvEventProperty>(ev.data);
                    HandlePropertyChange(prop);
                }
            }
        }

        private static void HandlePropertyChange(MpvEventProperty prop)
        {
            if (prop.name == "time-pos")
            {
                if (prop.format == MpvFormatDouble && prop.data != IntPtr.Zero)
                {
                    double posSeconds = Marshal.PtrToStructure<double>(prop.data);
                    WriteOutputEvent(new Dictionary<string, object?>
                    {
                        ["type"] = "time.updated",
                        ["requestId"] = currentRequestId,
                        ["positionMs"] = (int)(posSeconds * 1000),
                        ["durationMs"] = (int)(cachedDurationSeconds * 1000)
                    });
                }
            }
            else if (prop.name == "duration")
            {
                if (prop.format == MpvFormatDouble && prop.data != IntPtr.Zero)
                {
                    cachedDurationSeconds = Marshal.PtrToStructure<double>(prop.data);
                }
            }
            else if (prop.name == "pause")
            {
                if (prop.format == MpvFormatFlag && prop.data != IntPtr.Zero)
                {
                    int pausedVal = Marshal.ReadInt32(prop.data);
                    isPaused = pausedVal != 0;
                    UpdatePlaybackState();
                }
            }
            else if (prop.name == "core-idle")
            {
                if (prop.format == MpvFormatFlag && prop.data != IntPtr.Zero)
                {
                    int idleVal = Marshal.ReadInt32(prop.data);
                    isBuffering = idleVal != 0;
                    UpdatePlaybackState();
                }
            }
        }

        private static void UpdatePlaybackState()
        {
            string status = "playing";
            if (isBuffering)
            {
                status = "buffering";
            }
            else if (isPaused)
            {
                status = "paused";
            }

            WriteOutputEvent(new Dictionary<string, object?>
            {
                ["type"] = "playback.state",
                ["requestId"] = currentRequestId,
                ["status"] = status,
                ["playing"] = !isPaused && !isBuffering
            });
        }

        private static void RenderLoop()
        {
            while (renderThreadRunning && renderContext != IntPtr.Zero && renderSurface != null)
            {
                renderSurface.MakeCurrent();
                NativeMethods.glViewport(0, 0, renderSurface.Width, renderSurface.Height);
                NativeMethods.glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
                NativeMethods.glClear(GlColorBufferBit);

                IntPtr renderParams = AllocRenderParams(
                    new MpvRenderParam { type = 3, data = renderSurface.FboParam },
                    new MpvRenderParam { type = 4, data = renderSurface.FlipYParam }
                );

                try
                {
                    NativeMethods.mpv_render_context_update(renderContext);
                    NativeMethods.mpv_render_context_render(renderContext, renderParams);
                }
                finally
                {
                    Marshal.FreeHGlobal(renderParams);
                }

                NativeMethods.SwapBuffers(renderSurface.DeviceContext);
                PumpWindowMessages();
                Thread.Sleep(16);
            }
        }

        private static void HandleCleanup(string? requestId)
        {
            lock (MpvLock)
            {
                TeardownMpvContext();
            }
        }

        private static void ConfigureLibmpvPath(string[] args)
        {
            string? overridePath = null;
            for (int index = 0; index < args.Length; index += 1)
            {
                if (args[index] == "--libmpv" && index + 1 < args.Length)
                {
                    overridePath = args[index + 1];
                    break;
                }
            }

            libmpvPath = !string.IsNullOrWhiteSpace(overridePath)
                ? Path.GetFullPath(overridePath)
                : Path.Combine(AppContext.BaseDirectory, "libmpv-2.dll");
        }

        private static void EnsureLibmpvResolverRegistered()
        {
            if (libmpvResolverRegistered)
            {
                return;
            }
            NativeLibrary.SetDllImportResolver(typeof(Program).Assembly, ResolveLibmpv);
            libmpvResolverRegistered = true;
        }

        private static void TeardownMpvContext()
        {
            renderThreadRunning = false;
            if (renderThread != null && renderThread.IsAlive)
            {
                renderThread.Join();
            }
            renderThread = null;

            if (renderContext != IntPtr.Zero)
            {
                NativeMethods.mpv_render_context_free(renderContext);
                renderContext = IntPtr.Zero;
            }

            if (mpvContext != IntPtr.Zero)
            {
                NativeMethods.mpv_terminate_destroy(mpvContext);
                mpvContext = IntPtr.Zero;
            }

            if (eventThread != null && eventThread.IsAlive)
            {
                eventThread.Join();
            }
            eventThread = null;

            if (renderSurface != null)
            {
                renderSurface.Dispose();
                renderSurface = null;
            }

            currentRequestId = null;
            currentMediaId = null;
            currentMediaTitle = null;
            cachedDurationSeconds = 0;
            isPaused = false;
            isBuffering = false;
        }

        private static void CacheLoadedMedia(InputMessage msg)
        {
            currentMediaId = null;
            currentMediaTitle = null;
            if (msg.payload.ValueKind != JsonValueKind.Object ||
                !msg.payload.TryGetProperty("media", out JsonElement media) ||
                media.ValueKind != JsonValueKind.Object)
            {
                return;
            }

            if (media.TryGetProperty("id", out JsonElement id) && id.ValueKind == JsonValueKind.String)
            {
                currentMediaId = id.GetString();
            }
            if (media.TryGetProperty("title", out JsonElement title) && title.ValueKind == JsonValueKind.String)
            {
                currentMediaTitle = title.GetString();
            }
        }

        private static void ApplySelectedPrivateTracks(PrivateTrackSelection? selection)
        {
            if (selection == null)
            {
                return;
            }

            SetTrackSelection("aid", selection.audio);
            SetTrackSelection("sid", selection.subtitle);
            SetTrackSelection("vid", selection.video);
        }

        private static void SetTrackSelection(string property, string? privateTrackId)
        {
            if (string.IsNullOrWhiteSpace(privateTrackId))
            {
                return;
            }
            Command(mpvContext, "set", property, privateTrackId);
        }

        private static void SetOption(IntPtr mpv, string name, string value)
        {
            NativeMethods.mpv_set_option_string(mpv, name, value);
        }

        private static void SetPropertyBool(IntPtr mpv, string name, bool value)
        {
            SetOption(mpv, name, value ? "yes" : "no");
        }

        private static void SetPropertyDouble(IntPtr mpv, string name, double value)
        {
            SetOption(mpv, name, value.ToString("F3"));
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

        private static IntPtr AllocRenderParams(params MpvRenderParam[] parameters)
        {
            int itemSize = Marshal.SizeOf<MpvRenderParam>();
            IntPtr buffer = Marshal.AllocHGlobal(itemSize * (parameters.Length + 1));
            for (int index = 0; index < parameters.Length; index += 1)
            {
                Marshal.StructureToPtr(parameters[index], IntPtr.Add(buffer, itemSize * index), false);
            }
            Marshal.StructureToPtr(new MpvRenderParam { type = 0, data = IntPtr.Zero }, IntPtr.Add(buffer, itemSize * parameters.Length), false);
            return buffer;
        }

        private static IntPtr GetOpenGlProcAddress(IntPtr context, string name)
        {
            IntPtr pointer = NativeMethods.wglGetProcAddress(name);
            if (pointer != IntPtr.Zero)
            {
                return pointer;
            }
            IntPtr module = NativeMethods.GetModuleHandle("opengl32.dll");
            return module == IntPtr.Zero ? IntPtr.Zero : NativeMethods.GetProcAddress(module, name);
        }

        private static IntPtr ResolveLibmpv(string libraryName, System.Reflection.Assembly assembly, DllImportSearchPath? searchPath)
        {
            if ((libraryName == "libmpv-2.dll" || libraryName == "mpv-2.dll") && !string.IsNullOrWhiteSpace(libmpvPath))
            {
                return NativeLibrary.Load(libmpvPath);
            }
            return IntPtr.Zero;
        }

        private static void WriteResult(string requestId, bool ok, string? errorCode, string? errorMessage)
        {
            var result = new Dictionary<string, object>
            {
                ["type"] = "result",
                ["requestId"] = requestId,
                ["ok"] = ok
            };
            if (!ok && errorCode != null)
            {
                result["error"] = new Dictionary<string, object>
                {
                    ["code"] = errorCode,
                    ["message"] = errorMessage ?? "Command execution failed.",
                    ["category"] = "helper-failure",
                    ["recoverable"] = true,
                    ["retryable"] = true
                };
            }
            Console.Out.WriteLine(JsonSerializer.Serialize(result));
            Console.Out.Flush();
        }

        private static void WriteOutputEvent(object eventData)
        {
            var envelope = new Dictionary<string, object>
            {
                ["type"] = "event",
                ["event"] = eventData
            };
            Console.Out.WriteLine(JsonSerializer.Serialize(envelope));
            Console.Out.Flush();
        }

        private static void WriteEvent(string kind, Dictionary<string, object?> fields)
        {
            fields["kind"] = kind;
            Console.Out.WriteLine(JsonSerializer.Serialize(fields));
            Console.Out.Flush();
        }

        private static void PumpWindowMessages()
        {
            while (NativeMethods.PeekMessage(out NativeMethods.MSG message, IntPtr.Zero, 0, 0, 1))
            {
                NativeMethods.TranslateMessage(ref message);
                NativeMethods.DispatchMessage(ref message);
            }
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr MpvOpenGlGetProcAddressDelegate(IntPtr context, string name);

        private sealed class RenderSurface : IDisposable
        {
            private static readonly NativeMethods.WndProc WndProcDelegate = DefWindowProc;
            private readonly IntPtr window;
            private readonly IntPtr renderingContext;
            private readonly IntPtr classAtom;
            private readonly IntPtr instance;
            private readonly string className;

            public readonly IntPtr DeviceContext;
            public readonly int Width;
            public readonly int Height;
            public readonly IntPtr FboParam;
            public readonly IntPtr FlipYParam;

            private RenderSurface(
                IntPtr instance,
                IntPtr classAtom,
                string className,
                IntPtr window,
                IntPtr deviceContext,
                IntPtr renderingContext,
                int width,
                int height)
            {
                this.instance = instance;
                this.classAtom = classAtom;
                this.className = className;
                this.window = window;
                DeviceContext = deviceContext;
                this.renderingContext = renderingContext;
                Width = width;
                Height = height;

                MpvOpenGlFbo fbo = new MpvOpenGlFbo { fbo = 0, w = Width, h = Height, internal_format = 0 };
                FboParam = Marshal.AllocHGlobal(Marshal.SizeOf<MpvOpenGlFbo>());
                Marshal.StructureToPtr(fbo, FboParam, false);
                FlipYParam = Marshal.AllocHGlobal(sizeof(int));
                Marshal.WriteInt32(FlipYParam, 1);
            }

            public static RenderSurface? TryCreate()
            {
                IntPtr instance = NativeMethods.GetModuleHandle(null);
                string className = "LineupNativePlayerPresentationHost";
                int width = 960;
                int height = 540;
                int x = 80;
                int y = 80;
                int style = unchecked((int)0x90000000); // WS_VISIBLE | WS_POPUP

                NativeMethods.WNDCLASSEX wndClass = new NativeMethods.WNDCLASSEX
                {
                    cbSize = Marshal.SizeOf<NativeMethods.WNDCLASSEX>(),
                    style = 0x0020 | 0x0002 | 0x0001,
                    lpfnWndProc = WndProcDelegate,
                    hInstance = instance,
                    lpszClassName = className,
                };
                ushort atom = NativeMethods.RegisterClassEx(ref wndClass);
                if (atom == 0 && Marshal.GetLastWin32Error() != 1410)
                {
                    return null;
                }

                IntPtr window = NativeMethods.CreateWindowEx(
                    0,
                    className,
                    string.Empty,
                    style,
                    x,
                    y,
                    width,
                    height,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    instance,
                    IntPtr.Zero);
                if (window == IntPtr.Zero)
                {
                    return null;
                }

                IntPtr deviceContext = NativeMethods.GetDC(window);
                if (deviceContext == IntPtr.Zero)
                {
                    NativeMethods.DestroyWindow(window);
                    return null;
                }

                NativeMethods.PIXELFORMATDESCRIPTOR pfd = NativeMethods.PIXELFORMATDESCRIPTOR.Create();
                int pixelFormat = NativeMethods.ChoosePixelFormat(deviceContext, ref pfd);
                if (pixelFormat == 0 || !NativeMethods.SetPixelFormat(deviceContext, pixelFormat, ref pfd))
                {
                    NativeMethods.ReleaseDC(window, deviceContext);
                    NativeMethods.DestroyWindow(window);
                    return null;
                }

                IntPtr renderingContext = NativeMethods.wglCreateContext(deviceContext);
                if (renderingContext == IntPtr.Zero || !NativeMethods.wglMakeCurrent(deviceContext, renderingContext))
                {
                    if (renderingContext != IntPtr.Zero)
                    {
                        NativeMethods.wglDeleteContext(renderingContext);
                    }
                    NativeMethods.ReleaseDC(window, deviceContext);
                    NativeMethods.DestroyWindow(window);
                    return null;
                }

                NativeMethods.ShowWindow(window, 5);
                NativeMethods.SetWindowPos(window, HwndTopmost, x, y, width, height, SwpShowWindow);
                NativeMethods.UpdateWindow(window);
                NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
                return new RenderSurface(instance, new IntPtr(atom), className, window, deviceContext, renderingContext, width, height);
            }

            public void MakeCurrent()
            {
                NativeMethods.wglMakeCurrent(DeviceContext, renderingContext);
            }

            public void Dispose()
            {
                Marshal.FreeHGlobal(FboParam);
                Marshal.FreeHGlobal(FlipYParam);
                NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
                NativeMethods.wglDeleteContext(renderingContext);
                NativeMethods.ReleaseDC(window, DeviceContext);
                NativeMethods.DestroyWindow(window);
                if (classAtom != IntPtr.Zero)
                {
                    NativeMethods.UnregisterClass(className, instance);
                }
            }

            private static IntPtr DefWindowProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
            {
                return NativeMethods.DefWindowProc(hwnd, msg, wParam, lParam);
            }
        }

        private static class NativeMethods
        {
            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern IntPtr mpv_create();

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_initialize(IntPtr context);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_set_option_string(IntPtr context, string name, string value);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_command(IntPtr context, IntPtr args);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_observe_property(IntPtr context, ulong reply_userdata, string name, int format);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern IntPtr mpv_wait_event(IntPtr context, double timeout);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern void mpv_terminate_destroy(IntPtr context);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_render_context_create(out IntPtr context, IntPtr mpv, IntPtr parameters);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern void mpv_render_context_render(IntPtr context, IntPtr parameters);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern ulong mpv_render_context_update(IntPtr context);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern void mpv_render_context_free(IntPtr context);

            [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
            public static extern IntPtr GetModuleHandle(string? moduleName);

            [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
            public static extern IntPtr GetProcAddress(IntPtr module, string procName);

            [DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
            public static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);

            [DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
            public static extern bool UnregisterClass(string lpClassName, IntPtr hInstance);

            [DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
            public static extern IntPtr CreateWindowEx(
                int dwExStyle,
                string lpClassName,
                string lpWindowName,
                int dwStyle,
                int x,
                int y,
                int nWidth,
                int nHeight,
                IntPtr hWndParent,
                IntPtr hMenu,
                IntPtr hInstance,
                IntPtr lpParam);

            [DllImport("user32.dll", SetLastError = true)]
            public static extern bool DestroyWindow(IntPtr hWnd);

            [DllImport("user32.dll", SetLastError = true)]
            public static extern IntPtr GetDC(IntPtr hWnd);

            [DllImport("user32.dll", SetLastError = true)]
            public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

            [DllImport("user32.dll")]
            public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

            [DllImport("user32.dll", SetLastError = true)]
            public static extern bool SetWindowPos(
                IntPtr hWnd,
                IntPtr hWndInsertAfter,
                int x,
                int y,
                int cx,
                int cy,
                int uFlags);

            [DllImport("user32.dll")]
            public static extern bool UpdateWindow(IntPtr hWnd);

            [DllImport("user32.dll")]
            public static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

            [DllImport("user32.dll")]
            public static extern bool PeekMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

            [DllImport("user32.dll")]
            public static extern bool TranslateMessage(ref MSG lpMsg);

            [DllImport("user32.dll")]
            public static extern IntPtr DispatchMessage(ref MSG lpMsg);

            [DllImport("gdi32.dll", SetLastError = true)]
            public static extern int ChoosePixelFormat(IntPtr hdc, ref PIXELFORMATDESCRIPTOR ppfd);

            [DllImport("gdi32.dll", SetLastError = true)]
            public static extern bool SetPixelFormat(IntPtr hdc, int format, ref PIXELFORMATDESCRIPTOR ppfd);

            [DllImport("gdi32.dll")]
            public static extern bool SwapBuffers(IntPtr hdc);

            [DllImport("opengl32.dll", SetLastError = true)]
            public static extern IntPtr wglCreateContext(IntPtr hdc);

            [DllImport("opengl32.dll", SetLastError = true)]
            public static extern bool wglMakeCurrent(IntPtr hdc, IntPtr hglrc);

            [DllImport("opengl32.dll", SetLastError = true)]
            public static extern bool wglDeleteContext(IntPtr hglrc);

            [DllImport("opengl32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
            public static extern IntPtr wglGetProcAddress(string lpszProc);

            [DllImport("opengl32.dll")]
            public static extern void glViewport(int x, int y, int width, int height);

            [DllImport("opengl32.dll")]
            public static extern void glClearColor(float red, float green, float blue, float alpha);

            [DllImport("opengl32.dll")]
            public static extern void glClear(int mask);

            public delegate IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

            [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
            public struct WNDCLASSEX
            {
                public int cbSize;
                public uint style;
                public WndProc lpfnWndProc;
                public int cbClsExtra;
                public int cbWndExtra;
                public IntPtr hInstance;
                public IntPtr hIcon;
                public IntPtr hCursor;
                public IntPtr hbrBackground;
                public string? lpszMenuName;
                public string lpszClassName;
                public IntPtr hIconSm;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct POINT
            {
                public int x;
                public int y;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct MSG
            {
                public IntPtr hwnd;
                public uint message;
                public IntPtr wParam;
                public IntPtr lParam;
                public uint time;
                public POINT pt;
            }

            [StructLayout(LayoutKind.Sequential)]
            public struct PIXELFORMATDESCRIPTOR
            {
                public ushort nSize;
                public ushort nVersion;
                public uint dwFlags;
                public byte iPixelType;
                public byte cColorBits;
                public byte cRedBits;
                public byte cRedShift;
                public byte cGreenBits;
                public byte cGreenShift;
                public byte cBlueBits;
                public byte cBlueShift;
                public byte cAlphaBits;
                public byte cAlphaShift;
                public byte cAccumBits;
                public byte cAccumRedBits;
                public byte cAccumGreenBits;
                public byte cAccumBlueBits;
                public byte cAccumAlphaBits;
                public byte cDepthBits;
                public byte cStencilBits;
                public byte cAuxBuffers;
                public sbyte iLayerType;
                public byte bReserved;
                public uint dwLayerMask;
                public uint dwVisibleMask;
                public uint dwDamageMask;

                public static PIXELFORMATDESCRIPTOR Create()
                {
                    return new PIXELFORMATDESCRIPTOR
                    {
                        nSize = (ushort)Marshal.SizeOf<PIXELFORMATDESCRIPTOR>(),
                        nVersion = 1,
                        dwFlags = 0x00000004 | 0x00000020 | 0x00000001,
                        iPixelType = 0,
                        cColorBits = 32,
                        cAlphaBits = 8,
                        cDepthBits = 24,
                        iLayerType = 0,
                    };
                }
            }
        }
    }
}
