using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

internal static class Rd06NativeLibmpvHostSpikeHelper
{
    private const int MpvFormatString = 1;
    private const int MpvEventShutdown = 1;
    private const int MpvEventLogMessage = 2;
    private const int MpvEventStartFile = 6;
    private const int MpvEventFileLoaded = 8;
    private const int MpvEventEndFile = 7;
    private const int MpvRenderParamInvalid = 0;
    private const int MpvRenderParamApiType = 1;
    private const int MpvRenderParamOpenGlInitParams = 2;
    private const int MpvRenderParamOpenGlFbo = 3;
    private const int MpvRenderParamFlipY = 4;
    private const int MpvRenderParamBlockForTargetTime = 5;
    private const int GlColorBufferBit = 0x00004000;
    private const int GlRgba = 0x1908;
    private const int GlUnsignedByte = 0x1401;
    private const int GlScissorTest = 0x0C11;
    private const int Srccopy = 0x00CC0020;
    private const int Captureblt = 0x40000000;
    private const int SwpShowWindow = 0x0040;
    private const uint MonitorDefaultToNearest = 2;
    private static readonly IntPtr HwndTopmost = new IntPtr(-1);

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

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr MpvOpenGlGetProcAddressDelegate(IntPtr context, string name);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct MpvEvent
    {
        public readonly int event_id;
        public readonly int error;
        public readonly ulong reply_userdata;
        public readonly IntPtr data;
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
        public bool renderApiProbe { get; set; }
        public bool renderApi { get; set; }
        public bool nativePresentation { get; set; }
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
            if (init == null ||
                string.IsNullOrWhiteSpace(init.libmpvDll) ||
                (!init.apiProbe && !init.nativePresentation && string.IsNullOrWhiteSpace(init.parentWid)))
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
            bool renderApiSymbolsAvailable = ProbeRenderApiSymbols();
            if (init.renderApiProbe || init.renderApi)
            {
                WriteEvent(renderApiSymbolsAvailable ? "observed" : "blocked", new Dictionary<string, object?>
                {
                    ["proof"] = "libmpv-render-api-symbols",
                    ["category"] = renderApiSymbolsAvailable ? "available" : "unavailable",
                });
            }
            if (init.apiProbe)
            {
                return !init.renderApiProbe || renderApiSymbolsAvailable ? 0 : 2;
            }
            if (init.renderApi && !renderApiSymbolsAvailable)
            {
                return 2;
            }

            IntPtr mpv = NativeMethods.mpv_create();
            if (mpv == IntPtr.Zero)
            {
                WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "mpv-create" });
                return 1;
            }

            try
            {
                if (init.nativePresentation)
                {
                    return RunNativePresentationSmoke(mpv, init);
                }

                if (init.renderApi)
                {
                    return RunRenderApiSmoke(mpv, init);
                }

                SetOption(mpv, "wid", init.parentWid!);
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

    private static int RunRenderApiSmoke(IntPtr mpv, InitPayload init)
    {
        RenderSurface? surface = null;
        IntPtr renderContext = IntPtr.Zero;
        IntPtr apiType = IntPtr.Zero;
        IntPtr initParamsPtr = IntPtr.Zero;
        IntPtr initParamArray = IntPtr.Zero;
        IntPtr getProcDelegatePtr = IntPtr.Zero;
        MpvOpenGlGetProcAddressDelegate? getProcDelegate = null;

        try
        {
            SetOption(mpv, "terminal", "no");
            SetOption(mpv, "msg-level", "all=no");
            SetOption(mpv, "vo", "libmpv");

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

            surface = RenderSurface.TryCreate(init.parentWid);
            if (surface == null)
            {
                WriteEvent("blocked", new Dictionary<string, object?> { ["proof"] = "render-surface", ["reason"] = "opengl-window-unavailable" });
                return 2;
            }

            getProcDelegate = GetOpenGlProcAddress;
            getProcDelegatePtr = Marshal.GetFunctionPointerForDelegate(getProcDelegate);
            apiType = Marshal.StringToHGlobalAnsi("opengl");
            MpvOpenGlInitParams initParams = new MpvOpenGlInitParams
            {
                get_proc_address = getProcDelegatePtr,
                get_proc_address_ctx = IntPtr.Zero,
            };
            initParamsPtr = Marshal.AllocHGlobal(Marshal.SizeOf<MpvOpenGlInitParams>());
            Marshal.StructureToPtr(initParams, initParamsPtr, false);
            initParamArray = AllocRenderParams(
                new MpvRenderParam { type = MpvRenderParamApiType, data = apiType },
                new MpvRenderParam { type = MpvRenderParamOpenGlInitParams, data = initParamsPtr });

            surface.MakeCurrent();
            int contextResult = NativeMethods.mpv_render_context_create(out renderContext, mpv, initParamArray);
            NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
            WriteEvent(contextResult == 0 ? "observed" : "blocked", new Dictionary<string, object?>
            {
                ["proof"] = "render-context",
                ["category"] = ResultCategory(contextResult),
                ["renderContextCreated"] = contextResult == 0,
            });
            if (contextResult != 0 || renderContext == IntPtr.Zero)
            {
                return 2;
            }

            WriteEvent("observed", new Dictionary<string, object?>
            {
                ["proof"] = "render-input",
                ["category"] = "app-owned-input-simulated",
            });
            WriteEvent("blocked", new Dictionary<string, object?>
            {
                ["proof"] = "render-thread-discipline",
                ["category"] = "not-proven-blocking-helper-loop",
            });

            bool localLoaded = LoadAndRender(mpv, renderContext, surface, init.localMedia, "local-media", null, null, init.durationMs);
            if (localLoaded)
            {
                WriteEvent("observed", new Dictionary<string, object?>
                {
                    ["proof"] = "local-media",
                    ["activePlayback"] = true,
                });
                if (!WaitForContinueWithRendering(renderContext, surface, Math.Max(3000, init.durationMs)))
                {
                    return 1;
                }
            }

            LoadAndRender(mpv, renderContext, surface, init.httpMedia, "dummy-http", init.dummyHeaderName, init.dummyHeaderValue, init.durationMs);
            Command(mpv, "stop");
            return 0;
        }
        finally
        {
            if (renderContext != IntPtr.Zero)
            {
                NativeMethods.mpv_render_context_free(renderContext);
            }
            surface?.Dispose();
            if (initParamArray != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(initParamArray);
            }
            if (initParamsPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(initParamsPtr);
            }
            if (apiType != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(apiType);
            }
            WriteEvent("observed", new Dictionary<string, object?>
            {
                ["proof"] = "render-api-cleanup",
                ["category"] = "cleanup-observed",
                ["cleanupObserved"] = true,
            });
        }
    }

    private static int RunNativePresentationSmoke(IntPtr mpv, InitPayload init)
    {
        RenderSurface? surface = null;
        RenderThreadProbe? renderThread = null;
        IntPtr renderContext = IntPtr.Zero;
        IntPtr apiType = IntPtr.Zero;
        IntPtr initParamsPtr = IntPtr.Zero;
        IntPtr initParamArray = IntPtr.Zero;
        IntPtr getProcDelegatePtr = IntPtr.Zero;
        MpvOpenGlGetProcAddressDelegate? getProcDelegate = null;

        try
        {
            SetOption(mpv, "terminal", "no");
            SetOption(mpv, "msg-level", "all=no");
            SetOption(mpv, "vo", "libmpv");

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

            surface = RenderSurface.TryCreate(null, nativePresentation: true);
            if (surface == null)
            {
                WriteEvent("blocked", new Dictionary<string, object?> { ["proof"] = "native-presentation-host", ["reason"] = "native-host-unavailable" });
                return 2;
            }
            WriteEvent("observed", new Dictionary<string, object?>
            {
                ["proof"] = "native-presentation-host",
                ["category"] = "app-owned-native-boundary",
                ["visiblePixelsObserved"] = true,
            });

            getProcDelegate = GetOpenGlProcAddress;
            getProcDelegatePtr = Marshal.GetFunctionPointerForDelegate(getProcDelegate);
            apiType = Marshal.StringToHGlobalAnsi("opengl");
            MpvOpenGlInitParams initParams = new MpvOpenGlInitParams
            {
                get_proc_address = getProcDelegatePtr,
                get_proc_address_ctx = IntPtr.Zero,
            };
            initParamsPtr = Marshal.AllocHGlobal(Marshal.SizeOf<MpvOpenGlInitParams>());
            Marshal.StructureToPtr(initParams, initParamsPtr, false);
            initParamArray = AllocRenderParams(
                new MpvRenderParam { type = MpvRenderParamApiType, data = apiType },
                new MpvRenderParam { type = MpvRenderParamOpenGlInitParams, data = initParamsPtr });

            surface.MakeCurrent();
            int contextResult = NativeMethods.mpv_render_context_create(out renderContext, mpv, initParamArray);
            NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
            WriteEvent(contextResult == 0 ? "observed" : "blocked", new Dictionary<string, object?>
            {
                ["proof"] = "render-context",
                ["category"] = ResultCategory(contextResult),
                ["renderContextCreated"] = contextResult == 0,
            });
            if (contextResult != 0 || renderContext == IntPtr.Zero)
            {
                return 2;
            }

            WriteEvent("observed", new Dictionary<string, object?>
            {
                ["proof"] = "render-input",
                ["category"] = "app-owned-input-simulated",
            });

            renderThread = new RenderThreadProbe(renderContext, surface);
            renderThread.Start();

            bool localLoaded = LoadAndObserve(mpv, init.localMedia, "local-media", null, null, Math.Max(500, Math.Min(init.durationMs / 2, 2500)));
            RenderSnapshot windowedSnapshot = renderThread.WaitForPixels(Math.Max(1000, init.durationMs));
            WriteEvent(windowedSnapshot.FrameObserved ? "observed" : "failed", new Dictionary<string, object?>
            {
                ["proof"] = "render-frame",
                ["category"] = windowedSnapshot.FrameObserved ? "frame-observed" : "not-observed",
                ["renderFrameObserved"] = windowedSnapshot.FrameObserved,
                ["visiblePixelsObserved"] = windowedSnapshot.VideoPixelsObserved,
            });
            WriteEvent(windowedSnapshot.VideoPixelsObserved ? "observed" : "failed", new Dictionary<string, object?>
            {
                ["proof"] = "video-surface",
                ["category"] = windowedSnapshot.VideoPixelsObserved ? "active-playback-pixels" : "not-captured",
                ["visiblePixelsObserved"] = windowedSnapshot.VideoPixelsObserved,
            });
            WriteEvent(windowedSnapshot.OverlayPixelsObserved ? "observed" : "failed", new Dictionary<string, object?>
            {
                ["proof"] = "overlay",
                ["category"] = windowedSnapshot.OverlayPixelsObserved ? "native-boundary-overlay-pixels" : "not-captured",
                ["visiblePixelsObserved"] = windowedSnapshot.OverlayPixelsObserved,
            });
            WriteEvent(windowedSnapshot.CompositionObserved ? "observed" : "failed", new Dictionary<string, object?>
            {
                ["proof"] = "composition",
                ["category"] = windowedSnapshot.CompositionObserved ? "native-boundary-composited" : "not-captured",
                ["visiblePixelsObserved"] = windowedSnapshot.CompositionObserved,
            });
            if (localLoaded)
            {
                WriteEvent("observed", new Dictionary<string, object?>
                {
                    ["proof"] = "local-media",
                    ["activePlayback"] = true,
                });
                WaitForOptionalContinue(Math.Max(500, Math.Min(init.durationMs, 2000)));
            }

            bool fullscreenHost = surface.EnterFullscreenHost();
            Thread.Sleep(600);
            renderThread.ResetProofWindow();
            RenderSnapshot fullscreenSnapshot = renderThread.WaitForPixels(Math.Max(1000, init.durationMs));
            DesktopProofPixels desktopPixels = surface.CaptureDesktopProofPixels();
            bool fullscreenVideoObserved = fullscreenHost && (fullscreenSnapshot.VideoPixelsObserved || desktopPixels.RedPixelsObserved);
            bool fullscreenCompositionObserved = fullscreenHost && (
                fullscreenSnapshot.CompositionObserved ||
                (desktopPixels.RedPixelsObserved && desktopPixels.GreenPixelsObserved));
            WriteEvent(fullscreenVideoObserved ? "observed" : "blocked", new Dictionary<string, object?>
            {
                ["proof"] = "fullscreen",
                ["category"] = fullscreenVideoObserved ? "native-presentation-host-captured" : "not-captured",
                ["visiblePixelsObserved"] = fullscreenVideoObserved,
                ["nativePresentationFullscreen"] = fullscreenHost,
            });
            WriteEvent(fullscreenCompositionObserved ? "observed" : "failed", new Dictionary<string, object?>
            {
                ["proof"] = "fullscreen-composition",
                ["category"] = fullscreenCompositionObserved ? "native-boundary-composited" : "not-captured",
                ["visiblePixelsObserved"] = fullscreenCompositionObserved,
                ["nativePresentationFullscreen"] = fullscreenHost,
            });

            LoadAndObserve(mpv, init.httpMedia, "dummy-http", init.dummyHeaderName, init.dummyHeaderValue, init.durationMs);
            bool renderThreadDisciplineProven = renderThread.WaitForFreshRenderProgress(3, Math.Max(1000, Math.Min(init.durationMs, 3000)));
            WriteEvent("observed", new Dictionary<string, object?>
            {
                ["proof"] = "render-thread-discipline",
                ["category"] = renderThreadDisciplineProven ? "proven" : "not-proven",
                ["renderFrameObserved"] = renderThreadDisciplineProven,
            });
            Command(mpv, "stop");
            return 0;
        }
        finally
        {
            renderThread?.Dispose();
            if (renderContext != IntPtr.Zero)
            {
                NativeMethods.mpv_render_context_free(renderContext);
            }
            surface?.Dispose();
            if (initParamArray != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(initParamArray);
            }
            if (initParamsPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(initParamsPtr);
            }
            if (apiType != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(apiType);
            }
            WriteEvent("observed", new Dictionary<string, object?>
            {
                ["proof"] = "render-api-cleanup",
                ["category"] = "cleanup-observed",
                ["cleanupObserved"] = true,
            });
        }
    }

    private static bool LoadAndRender(
        IntPtr mpv,
        IntPtr renderContext,
        RenderSurface surface,
        string? media,
        string proof,
        string? headerName,
        string? headerValue,
        int durationMs)
    {
        bool loaded = LoadAndObserve(mpv, media, proof, headerName, headerValue, Math.Max(500, Math.Min(durationMs / 2, 2500)));
        bool rendered = RenderFrames(renderContext, surface, Math.Max(500, Math.Min(durationMs, 10000)));
        WriteEvent(rendered ? "observed" : "failed", new Dictionary<string, object?>
        {
            ["proof"] = "render-frame",
            ["category"] = rendered ? "frame-observed" : "not-observed",
            ["renderFrameObserved"] = rendered,
            ["visiblePixelsObserved"] = rendered,
        });
        return loaded;
    }

    private static bool RenderFrames(IntPtr renderContext, RenderSurface surface, int durationMs)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(durationMs);
        bool observedPixels = false;

        while (DateTime.UtcNow < deadline)
        {
            surface.MakeCurrent();
            NativeMethods.glViewport(0, 0, surface.Width, surface.Height);
            NativeMethods.glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            NativeMethods.glClear(GlColorBufferBit);
            IntPtr renderParams = AllocRenderParams(
                new MpvRenderParam { type = MpvRenderParamOpenGlFbo, data = surface.FboParam },
                new MpvRenderParam { type = MpvRenderParamFlipY, data = surface.FlipYParam },
                new MpvRenderParam { type = MpvRenderParamBlockForTargetTime, data = surface.BlockForTargetTimeParam });
            try
            {
                NativeMethods.mpv_render_context_update(renderContext);
                NativeMethods.mpv_render_context_render(renderContext, renderParams);
            }
            finally
            {
                Marshal.FreeHGlobal(renderParams);
            }
            NativeMethods.SwapBuffers(surface.DeviceContext);
            observedPixels = observedPixels || surface.HasVisibleVideoPixels();
            PumpWindowMessages();
            if (observedPixels)
            {
                break;
            }
        }

        return observedPixels;
    }

    private static IntPtr AllocRenderParams(params MpvRenderParam[] parameters)
    {
        int itemSize = Marshal.SizeOf<MpvRenderParam>();
        IntPtr buffer = Marshal.AllocHGlobal(itemSize * (parameters.Length + 1));
        for (int index = 0; index < parameters.Length; index += 1)
        {
            Marshal.StructureToPtr(parameters[index], IntPtr.Add(buffer, itemSize * index), false);
        }
        Marshal.StructureToPtr(new MpvRenderParam { type = MpvRenderParamInvalid, data = IntPtr.Zero }, IntPtr.Add(buffer, itemSize * parameters.Length), false);
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

    private static bool ProbeRenderApiSymbols()
    {
        try
        {
            IntPtr library = NativeLibrary.Load(libmpvPath!);
            try
            {
                return NativeLibrary.TryGetExport(library, "mpv_render_context_create", out _) &&
                    NativeLibrary.TryGetExport(library, "mpv_render_context_render", out _) &&
                    NativeLibrary.TryGetExport(library, "mpv_render_context_update", out _) &&
                    NativeLibrary.TryGetExport(library, "mpv_render_context_free", out _);
            }
            finally
            {
                NativeLibrary.Free(library);
            }
        }
        catch
        {
            return false;
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

    private static void WaitForOptionalContinue(int timeoutMs)
    {
        Task<string?> readTask = Task.Run(() => Console.In.ReadLine());
        if (readTask.Wait(timeoutMs) && !string.IsNullOrWhiteSpace(readTask.Result))
        {
            WriteEvent("observed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["category"] = "continued" });
        }
    }

    private static bool WaitForContinueWithRendering(IntPtr renderContext, RenderSurface surface, int timeoutMs)
    {
        Task<string?> readTask = Task.Run(() => Console.In.ReadLine());
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            while (!readTask.IsCompleted && DateTime.UtcNow < deadline)
            {
                RenderFrames(renderContext, surface, 80);
                PumpWindowMessages();
            }

            if (!readTask.IsCompleted || string.IsNullOrWhiteSpace(readTask.Result))
            {
                WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["reason"] = "missing-control" });
                return false;
            }

            try
            {
                using JsonDocument document = JsonDocument.Parse(readTask.Result);
                if (document.RootElement.TryGetProperty("control", out JsonElement control) &&
                    control.ValueKind == JsonValueKind.String)
                {
                    string? controlValue = control.GetString();
                    if (controlValue == "continue")
                    {
                        WriteEvent("observed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["category"] = "continued" });
                        return true;
                    }

                    if (controlValue == "fullscreen-native-capture")
                    {
                        bool browserWindowFullscreen = document.RootElement.TryGetProperty("browserWindowFullscreen", out JsonElement fullscreen) &&
                            fullscreen.ValueKind == JsonValueKind.True;
                        bool redPixelsObserved = browserWindowFullscreen && surface.HasVisibleDesktopPixels();
                        WriteEvent(redPixelsObserved ? "observed" : "blocked", new Dictionary<string, object?>
                        {
                            ["proof"] = "fullscreen-native-capture",
                            ["category"] = redPixelsObserved ? "desktop-composited-red-pixels" : "not-captured",
                            ["nativeCaptureObserved"] = redPixelsObserved,
                            ["visiblePixelsObserved"] = redPixelsObserved,
                            ["browserWindowFullscreen"] = browserWindowFullscreen,
                        });
                        readTask = Task.Run(() => Console.In.ReadLine());
                        continue;
                    }
                }
            }
            catch
            {
                // Fall through to the sanitized failure event.
            }

            WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["reason"] = "invalid-control" });
            return false;
        }

        WriteEvent("failed", new Dictionary<string, object?> { ["proof"] = "active-playback-control", ["reason"] = "missing-control" });
        return false;
    }

    private static bool CaptureDesktopRedPixels(NativeMethods.RECT bounds)
    {
        return CaptureDesktopProofPixels(bounds).RedPixelsObserved;
    }

    private static DesktopProofPixels CaptureDesktopProofPixels(NativeMethods.RECT bounds)
    {
        int width = bounds.right - bounds.left;
        int height = bounds.bottom - bounds.top;
        if (width <= 0 || height <= 0 || width > 4096 || height > 4096)
        {
            return new DesktopProofPixels(false, false);
        }

        IntPtr screenDc = NativeMethods.GetDC(IntPtr.Zero);
        if (screenDc == IntPtr.Zero)
        {
            return new DesktopProofPixels(false, false);
        }

        IntPtr memoryDc = IntPtr.Zero;
        IntPtr bitmap = IntPtr.Zero;
        IntPtr oldBitmap = IntPtr.Zero;
        try
        {
            memoryDc = NativeMethods.CreateCompatibleDC(screenDc);
            bitmap = NativeMethods.CreateCompatibleBitmap(screenDc, width, height);
            if (memoryDc == IntPtr.Zero || bitmap == IntPtr.Zero)
            {
                return new DesktopProofPixels(false, false);
            }

            oldBitmap = NativeMethods.SelectObject(memoryDc, bitmap);
            if (oldBitmap == IntPtr.Zero)
            {
                return new DesktopProofPixels(false, false);
            }
            if (!NativeMethods.BitBlt(memoryDc, 0, 0, width, height, screenDc, bounds.left, bounds.top, Srccopy | Captureblt))
            {
                return new DesktopProofPixels(false, false);
            }
            NativeMethods.SelectObject(memoryDc, oldBitmap);
            oldBitmap = IntPtr.Zero;

            NativeMethods.BITMAPINFO bitmapInfo = NativeMethods.BITMAPINFO.Create(width, height);
            byte[] pixels = new byte[width * height * 4];
            int rows = NativeMethods.GetDIBits(screenDc, bitmap, 0, (uint)height, pixels, ref bitmapInfo, 0);
            if (rows == 0)
            {
                return new DesktopProofPixels(false, false);
            }

            bool redPixelsObserved = false;
            bool greenPixelsObserved = false;
            for (int index = 0; index < pixels.Length; index += 16)
            {
                byte blue = pixels[index];
                byte green = pixels[index + 1];
                byte red = pixels[index + 2];
                if (red > 128 && green < 128 && blue < 128)
                {
                    redPixelsObserved = true;
                }
                if (red < 128 && green > 128 && blue < 128)
                {
                    greenPixelsObserved = true;
                }
                if (redPixelsObserved && greenPixelsObserved)
                {
                    break;
                }
            }
            return new DesktopProofPixels(redPixelsObserved, greenPixelsObserved);
        }
        finally
        {
            if (oldBitmap != IntPtr.Zero)
            {
                NativeMethods.SelectObject(memoryDc, oldBitmap);
            }
            if (bitmap != IntPtr.Zero)
            {
                NativeMethods.DeleteObject(bitmap);
            }
            if (memoryDc != IntPtr.Zero)
            {
                NativeMethods.DeleteDC(memoryDc);
            }
            NativeMethods.ReleaseDC(IntPtr.Zero, screenDc);
        }
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
            "vo" => "video-output",
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

    private static void PumpWindowMessages()
    {
        while (NativeMethods.PeekMessage(out NativeMethods.MSG message, IntPtr.Zero, 0, 0, 1))
        {
            NativeMethods.TranslateMessage(ref message);
            NativeMethods.DispatchMessage(ref message);
        }
    }

    private readonly struct RenderSnapshot
    {
        public RenderSnapshot(bool frameObserved, bool videoPixelsObserved, bool overlayPixelsObserved)
        {
            FrameObserved = frameObserved;
            VideoPixelsObserved = videoPixelsObserved;
            OverlayPixelsObserved = overlayPixelsObserved;
        }

        public bool FrameObserved { get; }
        public bool VideoPixelsObserved { get; }
        public bool OverlayPixelsObserved { get; }
        public bool CompositionObserved => VideoPixelsObserved && OverlayPixelsObserved;
    }

    private readonly struct DesktopProofPixels
    {
        public DesktopProofPixels(bool redPixelsObserved, bool greenPixelsObserved)
        {
            RedPixelsObserved = redPixelsObserved;
            GreenPixelsObserved = greenPixelsObserved;
        }

        public bool RedPixelsObserved { get; }
        public bool GreenPixelsObserved { get; }
    }

    private sealed class RenderThreadProbe : IDisposable
    {
        private readonly IntPtr renderContext;
        private readonly RenderSurface surface;
        private readonly Thread thread;
        private readonly object sync = new object();
        private volatile bool running;
        private bool frameObserved;
        private bool videoPixelsObserved;
        private bool overlayPixelsObserved;
        private int observedFrameCount;

        public RenderThreadProbe(IntPtr renderContext, RenderSurface surface)
        {
            this.renderContext = renderContext;
            this.surface = surface;
            thread = new Thread(RenderLoop)
            {
                IsBackground = true,
                Name = "rd06-native-presentation-render",
            };
        }

        public void Start()
        {
            running = true;
            thread.Start();
        }

        public RenderSnapshot WaitForPixels(int timeoutMs)
        {
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < deadline)
            {
                RenderSnapshot snapshot = Snapshot();
                if (snapshot.CompositionObserved)
                {
                    return snapshot;
                }
                Thread.Sleep(25);
            }
            return Snapshot();
        }

        public RenderSnapshot Snapshot()
        {
            lock (sync)
            {
                return new RenderSnapshot(frameObserved, videoPixelsObserved, overlayPixelsObserved);
            }
        }

        public void ResetProofWindow()
        {
            lock (sync)
            {
                frameObserved = false;
                videoPixelsObserved = false;
                overlayPixelsObserved = false;
                observedFrameCount = 0;
            }
        }

        public bool WaitForFreshRenderProgress(int minimumFrameCount, int timeoutMs)
        {
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < deadline)
            {
                lock (sync)
                {
                    if (thread.IsAlive && observedFrameCount >= minimumFrameCount)
                    {
                        return true;
                    }
                }
                Thread.Sleep(25);
            }

            lock (sync)
            {
                return thread.IsAlive && observedFrameCount >= minimumFrameCount;
            }
        }

        private void RenderLoop()
        {
            while (running)
            {
                RenderSnapshot snapshot = surface.RenderPresentationFrame(renderContext, drawOverlay: true);
                lock (sync)
                {
                    frameObserved = frameObserved || snapshot.FrameObserved;
                    videoPixelsObserved = videoPixelsObserved || snapshot.VideoPixelsObserved;
                    overlayPixelsObserved = overlayPixelsObserved || snapshot.OverlayPixelsObserved;
                    observedFrameCount += snapshot.FrameObserved ? 1 : 0;
                }
                PumpWindowMessages();
                Thread.Sleep(16);
            }
            NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
        }

        public void Dispose()
        {
            running = false;
            if (thread.IsAlive)
            {
                thread.Join();
            }
        }
    }

    private sealed class RenderSurface : IDisposable
    {
        private static readonly NativeMethods.WndProc WndProcDelegate = DefWindowProc;
        private readonly IntPtr window;
        private readonly IntPtr renderingContext;
        private readonly IntPtr classAtom;
        private readonly IntPtr instance;
        private readonly string className;
        private const int SurfaceTop = 140;
        public readonly IntPtr DeviceContext;
        public readonly int Width;
        public readonly int Height;
        public readonly IntPtr FboParam;
        public readonly IntPtr FlipYParam;
        public readonly IntPtr BlockForTargetTimeParam;

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
            BlockForTargetTimeParam = Marshal.AllocHGlobal(sizeof(int));
            Marshal.WriteInt32(BlockForTargetTimeParam, 1);
        }

        public static RenderSurface? TryCreate(string? parentWid, bool nativePresentation = false)
        {
            IntPtr parent = IntPtr.Zero;
            ulong parentValue = 0;
            if (!nativePresentation && !ulong.TryParse(parentWid, out parentValue))
            {
                return null;
            }

            if (!nativePresentation)
            {
                parent = new IntPtr(unchecked((long)parentValue));
            }
            IntPtr instance = NativeMethods.GetModuleHandle(null);
            string className = nativePresentation ? "LineupRd06NativePresentationHost" : "LineupRd06RenderApiSurface";
            int width = nativePresentation ? 960 : 640;
            int height = nativePresentation ? 540 : 360;
            int x = nativePresentation ? 80 : 0;
            int y = nativePresentation ? 80 : SurfaceTop;
            int style = nativePresentation ? unchecked((int)0x90000000) : unchecked((int)0x50000000);
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
                parent,
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
            NativeMethods.SetWindowPos(window, nativePresentation ? HwndTopmost : IntPtr.Zero, x, y, width, height, SwpShowWindow);
            NativeMethods.UpdateWindow(window);
            NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
            return new RenderSurface(instance, new IntPtr(atom), className, window, deviceContext, renderingContext, width, height);
        }

        public void MakeCurrent()
        {
            NativeMethods.wglMakeCurrent(DeviceContext, renderingContext);
        }

        public RenderSnapshot RenderPresentationFrame(IntPtr renderContext, bool drawOverlay)
        {
            MakeCurrent();
            NativeMethods.glViewport(0, 0, Width, Height);
            NativeMethods.glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
            NativeMethods.glClear(GlColorBufferBit);
            IntPtr renderParams = AllocRenderParams(
                new MpvRenderParam { type = MpvRenderParamOpenGlFbo, data = FboParam },
                new MpvRenderParam { type = MpvRenderParamFlipY, data = FlipYParam });
            try
            {
                NativeMethods.mpv_render_context_update(renderContext);
                NativeMethods.mpv_render_context_render(renderContext, renderParams);
            }
            finally
            {
                Marshal.FreeHGlobal(renderParams);
            }
            if (drawOverlay)
            {
                DrawOverlay();
            }
            NativeMethods.SwapBuffers(DeviceContext);
            RenderSnapshot snapshot = ScanPresentationPixels();
            return new RenderSnapshot(true, snapshot.VideoPixelsObserved, snapshot.OverlayPixelsObserved);
        }

        public bool EnterFullscreenHost()
        {
            IntPtr monitor = NativeMethods.MonitorFromWindow(window, MonitorDefaultToNearest);
            NativeMethods.MONITORINFO monitorInfo = NativeMethods.MONITORINFO.Create();
            if (monitor == IntPtr.Zero || !NativeMethods.GetMonitorInfo(monitor, ref monitorInfo))
            {
                return false;
            }

            int width = monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left;
            int height = monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top;
            if (width <= 0 || height <= 0)
            {
                return false;
            }

            bool positioned = NativeMethods.SetWindowPos(
                window,
                HwndTopmost,
                monitorInfo.rcMonitor.left,
                monitorInfo.rcMonitor.top,
                width,
                height,
                SwpShowWindow);
            NativeMethods.UpdateWindow(window);
            PumpWindowMessages();
            return positioned;
        }

        public bool HasVisibleVideoPixels()
        {
            return ScanPresentationPixels().VideoPixelsObserved;
        }

        public DesktopProofPixels CaptureDesktopProofPixels()
        {
            NativeMethods.UpdateWindow(window);
            PumpWindowMessages();
            return NativeMethods.GetWindowRect(window, out NativeMethods.RECT bounds)
                ? Rd06NativeLibmpvHostSpikeHelper.CaptureDesktopProofPixels(bounds)
                : new DesktopProofPixels(false, false);
        }

        private RenderSnapshot ScanPresentationPixels()
        {
            byte[] pixels = new byte[Width * Height * 4];
            NativeMethods.glReadPixels(0, 0, Width, Height, GlRgba, GlUnsignedByte, pixels);
            bool videoPixelsObserved = false;
            bool overlayPixelsObserved = false;
            for (int index = 0; index < pixels.Length; index += 16)
            {
                byte red = pixels[index];
                byte green = pixels[index + 1];
                byte blue = pixels[index + 2];
                if (red > 128 && green < 128 && blue < 128)
                {
                    videoPixelsObserved = true;
                }
                if (red < 128 && green > 128 && blue < 128)
                {
                    overlayPixelsObserved = true;
                }
                if (videoPixelsObserved && overlayPixelsObserved)
                {
                    break;
                }
            }
            return new RenderSnapshot(videoPixelsObserved || overlayPixelsObserved, videoPixelsObserved, overlayPixelsObserved);
        }

        private void DrawOverlay()
        {
            NativeMethods.glEnable(GlScissorTest);
            NativeMethods.glScissor(32, Math.Max(0, Height - 122), 180, 90);
            NativeMethods.glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
            NativeMethods.glClear(GlColorBufferBit);
            NativeMethods.glDisable(GlScissorTest);
        }

        public bool HasVisibleDesktopPixels()
        {
            NativeMethods.SetWindowPos(window, IntPtr.Zero, 0, SurfaceTop, Width, Height, SwpShowWindow);
            NativeMethods.UpdateWindow(window);
            PumpWindowMessages();
            return NativeMethods.GetWindowRect(window, out NativeMethods.RECT bounds) && CaptureDesktopRedPixels(bounds);
        }

        public void Dispose()
        {
            Marshal.FreeHGlobal(FboParam);
            Marshal.FreeHGlobal(FlipYParam);
            Marshal.FreeHGlobal(BlockForTargetTimeParam);
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

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int mpv_render_context_create(out IntPtr context, IntPtr mpv, IntPtr parameters);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void mpv_render_context_render(IntPtr context, IntPtr parameters);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong mpv_render_context_update(IntPtr context);

        [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void mpv_render_context_free(IntPtr context);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetDllDirectory(string pathName);

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

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

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
        public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

        [DllImport("user32.dll")]
        public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

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

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int cx, int cy);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern bool DeleteObject(IntPtr ho);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern bool BitBlt(
            IntPtr hdc,
            int x,
            int y,
            int cx,
            int cy,
            IntPtr hdcSrc,
            int x1,
            int y1,
            int rop);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern int GetDIBits(
            IntPtr hdc,
            IntPtr hbm,
            uint start,
            uint cLines,
            byte[] lpvBits,
            ref BITMAPINFO lpbmi,
            uint usage);

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

        [DllImport("opengl32.dll")]
        public static extern void glEnable(int cap);

        [DllImport("opengl32.dll")]
        public static extern void glDisable(int cap);

        [DllImport("opengl32.dll")]
        public static extern void glScissor(int x, int y, int width, int height);

        [DllImport("opengl32.dll")]
        public static extern void glReadPixels(int x, int y, int width, int height, int format, int type, byte[] pixels);

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
        public struct RECT
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MONITORINFO
        {
            public uint cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;

            public static MONITORINFO Create()
            {
                return new MONITORINFO
                {
                    cbSize = (uint)Marshal.SizeOf<MONITORINFO>(),
                };
            }
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
        public struct BITMAPINFOHEADER
        {
            public uint biSize;
            public int biWidth;
            public int biHeight;
            public ushort biPlanes;
            public ushort biBitCount;
            public uint biCompression;
            public uint biSizeImage;
            public int biXPelsPerMeter;
            public int biYPelsPerMeter;
            public uint biClrUsed;
            public uint biClrImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct BITMAPINFO
        {
            public BITMAPINFOHEADER bmiHeader;
            public uint bmiColors;

            public static BITMAPINFO Create(int width, int height)
            {
                return new BITMAPINFO
                {
                    bmiHeader = new BITMAPINFOHEADER
                    {
                        biSize = (uint)Marshal.SizeOf<BITMAPINFOHEADER>(),
                        biWidth = width,
                        biHeight = -height,
                        biPlanes = 1,
                        biBitCount = 32,
                        biCompression = 0,
                        biSizeImage = (uint)(width * height * 4),
                    },
                };
            }
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
