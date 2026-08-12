using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Numerics;
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
        private const int MpvEndFileReasonEof = 0;
        private const int MpvEndFileReasonStop = 2;
        private const int MpvEndFileReasonQuit = 3;
        private const int MpvEndFileReasonError = 4;
        private const int MpvEndFileReasonRedirect = 5;

        private const int MpvFormatNone = 0;
        private const int MpvFormatString = 1;
        private const int MpvFormatFlag = 3;
        private const int MpvFormatInt64 = 4;
        private const int MpvFormatDouble = 5;
        private const int MpvFormatNode = 6;
        private const int MpvFormatNodeArray = 7;
        private const int MpvFormatNodeMap = 8;

        private const int GlColorBufferBit = 0x00004000;
        private const int SwpShowWindow = 0x0040;
        private const int SwpHideWindow = 0x0080;
        private const int SwpNoActivate = 0x0010;
        private const int MAX_HELPER_MESSAGE_SIZE = 1024 * 1024;
        private const int MAX_PRESENTATION_MESSAGE_SIZE = 4096;
        private static readonly IntPtr HwndBottom = new IntPtr(1);
        private static readonly object MpvLock = new object();

        private static string? libmpvPath;
        private static bool libmpvResolverRegistered = false;
        private static IntPtr mpvContext = IntPtr.Zero;
        private static string? currentRequestId;
        private static string? currentMediaId;
        private static string? currentMediaTitle;
        private static PlaybackSetup? currentPlaybackSetup;
        private static double cachedDurationSeconds = 0;
        private static bool isPaused = false;
        private static bool isBuffering = false;

        private static MpvTrackState? trackState;
        private static MpvPlaybackQualityState? qualityState;

        private static RenderSurface? renderSurface;
        private static Thread? eventThread;
        private static IntPtr renderContext = IntPtr.Zero;
        private static readonly MpvOpenGlGetProcAddressDelegate OpenGlGetProcAddress = GetOpenGlProcAddress;
        private static readonly BlockingCollection<PresentationWork> PresentationQueue = new BlockingCollection<PresentationWork>(16);
        private static Thread? presentationThread;
        private static long latestPresentationEpoch;
        private static long latestPresentationRevision;
        private static string? latestPresentationLoadedRequestId;
        private static bool latestPresentationHidden;
        private static BigInteger latestPresentationOperationSequence = BigInteger.Zero;
        private const long JavaScriptMaxSafeInteger = 9007199254740991L;

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
        private struct MpvEventEndFileData
        {
            public int reason;
            public int error;
            public long playlist_entry_id;
            public long playlist_insert_id;
            public int playlist_insert_num_entries;
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

        [StructLayout(LayoutKind.Sequential)]
        internal struct MpvNode
        {
            public MpvNodeUnion value;
            public int format;
        }

        [StructLayout(LayoutKind.Explicit)]
        internal struct MpvNodeUnion
        {
            [FieldOffset(0)] public IntPtr stringValue;
            [FieldOffset(0)] public IntPtr listValue;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MpvNodeList
        {
            public int num;
            public IntPtr values;
            public IntPtr keys;
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
            public int version { get; set; }
            public string? operationId { get; set; }
            public long documentEpoch { get; set; }
            public long revision { get; set; }
            public string? parentHwnd { get; set; }
            public int parentPid { get; set; }
            public string? loadedRequestId { get; set; }
            public string? mode { get; set; }
            public NormalizedBounds? bounds { get; set; }
        }

        public sealed class NormalizedBounds
        {
            public double x { get; set; }
            public double y { get; set; }
            public double width { get; set; }
            public double height { get; set; }
        }

        private sealed class PresentationWork
        {
            public required InputMessage Message { get; init; }
            public readonly ManualResetEventSlim Completed = new ManualResetEventSlim(false);
            public string Status { get; set; } = "rejected";
        }

        public sealed class PlaybackSetup
        {
            public string? playbackMode { get; set; }
            public string? mediaPath { get; set; }
            public string? variantId { get; set; }
            public string? partPath { get; set; }
            public TrackSelection? selectedTrackIds { get; set; }
            public PrivateTrackSelection? selectedPrivateTrackIds { get; set; }
            public PlaybackTrackMap? trackMap { get; set; }
            public string? audioOutputNativeKey { get; set; }
            public bool dtsPassthroughEnabled { get; set; }
        }

        public sealed class PlaybackTrackMap
        {
            public List<VideoTrackMapItem>? video { get; set; }
            public List<AudioTrackMapItem>? audio { get; set; }
            public List<SubtitleTrackMapItem>? subtitle { get; set; }
        }

        public sealed class VideoTrackMapItem
        {
            public string? publicTrackId { get; set; }
            public string? privateTrackId { get; set; }
            public string? codec { get; set; }
            public string? dynamicRange { get; set; }
        }

        public sealed class AudioTrackMapItem
        {
            public string? publicTrackId { get; set; }
            public string? privateTrackId { get; set; }
            public string? label { get; set; }
            public string? language { get; set; }
            public string? codec { get; set; }
            public int? channelCount { get; set; }
            public bool? @default { get; set; }
        }

        public sealed class SubtitleTrackMapItem
        {
            public string? publicTrackId { get; set; }
            public string? privateTrackId { get; set; }
            public string? label { get; set; }
            public string? language { get; set; }
            public string? format { get; set; }
            public string? deliveryType { get; set; }
            public bool? forced { get; set; }
            public bool? @default { get; set; }
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

                presentationThread = new Thread(PresentationLoop)
                {
                    IsBackground = true,
                    Name = "LineupPresentationRenderLoop"
                };
                presentationThread.SetApartmentState(ApartmentState.STA);
                presentationThread.Start();

                // Process stdin NDJSON stream
                Thread commandThread = new Thread(CommandLoop)
                {
                    IsBackground = true,
                    Name = "LineupCommandLoop"
                };
                commandThread.Start();

                commandThread.Join();
                HandleCleanup(currentRequestId);
                PresentationQueue.CompleteAdding();
                presentationThread.Join();
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

                if (line.Length > MAX_HELPER_MESSAGE_SIZE)
                {
                    break;
                }

                try
                {
                    using JsonDocument document = JsonDocument.Parse(line);
                    InputMessage? message = document.RootElement.Deserialize<InputMessage>();
                    if (message == null)
                    {
                        continue;
                    }

                    if (message.type == "presentation.update" && line.Length > MAX_PRESENTATION_MESSAGE_SIZE)
                    {
                        WritePresentationResult(message, "rejected");
                        continue;
                    }

                    if (message.type == "cleanup")
                    {
                        HandleCleanup(message.requestId);
                        break;
                    }

                    if (message.type == "audio-output.query" && message.requestId != null)
                    {
                        HandleAudioOutputQuery(message.requestId);
                        continue;
                    }

                    if (message.type == "presentation.update")
                    {
                        if (!HasExactPresentationKeys(document.RootElement))
                        {
                            WritePresentationResult(message, "rejected");
                            continue;
                        }
                        HandlePresentationUpdate(message);
                        continue;
                    }

                    if (message.type == "command" && message.requestId != null && message.command != null)
                    {
                        HandleCommand(message);
                    }
                }
                catch (Exception ex)
                {
                    WriteResult(currentRequestId ?? "unknown", false, "PLAYER_HELPER_PARSE_ERROR", ex.Message);
                }
            }
        }

        private static bool HasExactPresentationKeys(JsonElement root)
        {
            if (root.ValueKind != JsonValueKind.Object) return false;
            HashSet<string> expected = new HashSet<string> { "type", "version", "operationId", "documentEpoch", "revision", "parentHwnd", "parentPid", "loadedRequestId", "mode", "bounds" };
            int count = 0;
            foreach (JsonProperty property in root.EnumerateObject()) { if (!expected.Remove(property.Name)) return false; count += 1; }
            if (count != 10 || expected.Count != 0) return false;
            if (root.GetProperty("type").ValueKind != JsonValueKind.String || root.GetProperty("type").GetString() != "presentation.update" ||
                root.GetProperty("version").ValueKind != JsonValueKind.Number || !root.GetProperty("version").TryGetInt32(out int version) || version != 1 ||
                root.GetProperty("operationId").ValueKind != JsonValueKind.String || !IsPresentationRequestId(root.GetProperty("operationId").GetString()) ||
                root.GetProperty("documentEpoch").ValueKind != JsonValueKind.Number || !root.GetProperty("documentEpoch").TryGetInt64(out long documentEpoch) || !IsPositiveSafeInteger(documentEpoch) ||
                root.GetProperty("revision").ValueKind != JsonValueKind.Number || !root.GetProperty("revision").TryGetInt64(out long revision) || !IsPositiveSafeInteger(revision) ||
                root.GetProperty("parentHwnd").ValueKind != JsonValueKind.String || !IsNonZeroDecimal(root.GetProperty("parentHwnd").GetString()) ||
                root.GetProperty("parentPid").ValueKind != JsonValueKind.Number || !root.GetProperty("parentPid").TryGetInt32(out int parentPid) || parentPid <= 0 ||
                root.GetProperty("mode").ValueKind != JsonValueKind.String)
            {
                return false;
            }
            string? mode = root.GetProperty("mode").GetString();
            JsonElement loadedRequest = root.GetProperty("loadedRequestId");
            bool loadedRequestValid = loadedRequest.ValueKind == JsonValueKind.Null ||
                loadedRequest.ValueKind == JsonValueKind.String && IsPresentationRequestId(loadedRequest.GetString());
            if (!loadedRequestValid || (mode != "hidden" && loadedRequest.ValueKind == JsonValueKind.Null)) return false;
            JsonElement bounds = root.GetProperty("bounds");
            if (mode == "hidden") return bounds.ValueKind == JsonValueKind.Null;
            if (mode != "player-full" && mode != "guide-overlay-full" && mode != "guide-classic-pip") return false;
            if (bounds.ValueKind == JsonValueKind.Null) return false;
            if (bounds.ValueKind != JsonValueKind.Object) return false;
            HashSet<string> boundKeys = new HashSet<string> { "x", "y", "width", "height" };
            int boundCount = 0;
            foreach (JsonProperty property in bounds.EnumerateObject()) { if (!boundKeys.Remove(property.Name)) return false; boundCount += 1; }
            if (boundCount != 4 || boundKeys.Count != 0 ||
                !TryGetFiniteNormalized(bounds, "x", out double x) ||
                !TryGetFiniteNormalized(bounds, "y", out double y) ||
                !TryGetFiniteNormalized(bounds, "width", out double width) ||
                !TryGetFiniteNormalized(bounds, "height", out double height) ||
                width <= 0 || height <= 0 || x + width > 1 || y + height > 1)
            {
                return false;
            }
            return mode == "guide-classic-pip" || x == 0 && y == 0 && width == 1 && height == 1;
        }

        private static bool IsPositiveSafeInteger(long value) => value > 0 && value <= JavaScriptMaxSafeInteger;

        private static bool IsPresentationRequestId(string? value)
        {
            if (value == null || value.Length < 1 || value.Length > 120) return false;
            foreach (char character in value)
            {
                if (!(character >= 'A' && character <= 'Z') && !(character >= 'a' && character <= 'z') &&
                    !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != '-') return false;
            }
            return true;
        }

        private static bool IsNonZeroDecimal(string? value)
        {
            if (value == null || value.Length == 0) return false;
            foreach (char character in value) if (character < '0' || character > '9') return false;
            return ulong.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out ulong parsed) && parsed != 0;
        }

        private static bool TryGetFiniteNormalized(JsonElement bounds, string name, out double value)
        {
            value = 0;
            JsonElement property = bounds.GetProperty(name);
            return property.ValueKind == JsonValueKind.Number && property.TryGetDouble(out value) &&
                !double.IsNaN(value) && !double.IsInfinity(value) && value >= 0 && value <= 1;
        }

        private static void HandleAudioOutputQuery(string requestId)
        {
            try
            {
                List<Dictionary<string, string>> outputs;
                lock (MpvLock)
                {
                    if (mpvContext != IntPtr.Zero)
                    {
                        outputs = ReadAudioOutputs(mpvContext);
                    }
                    else
                    {
                        EnsureLibmpvResolverRegistered();
                        IntPtr probe = NativeMethods.mpv_create();
                        if (probe == IntPtr.Zero)
                        {
                            throw new InvalidOperationException();
                        }
                        try
                        {
                            if (SetOption(probe, "terminal", "no") < 0 ||
                                SetOption(probe, "msg-level", "all=no") < 0)
                            {
                                throw new InvalidOperationException();
                            }
                            if (NativeMethods.mpv_initialize(probe) < 0)
                            {
                                throw new InvalidOperationException();
                            }
                            outputs = ReadAudioOutputs(probe);
                        }
                        finally
                        {
                            NativeMethods.mpv_terminate_destroy(probe);
                        }
                    }
                }
                WriteAudioOutputResult(requestId, true, outputs);
            }
            catch
            {
                WriteAudioOutputResult(requestId, false, null);
            }
        }

        private static List<Dictionary<string, string>> ReadAudioOutputs(IntPtr context)
        {
            MpvNode node = new MpvNode();
            int result = NativeMethods.mpv_get_property(context, "audio-device-list", MpvFormatNode, ref node);
            if (result < 0)
            {
                throw new InvalidOperationException();
            }
            try
            {
                if (node.format != MpvFormatNodeArray || node.value.listValue == IntPtr.Zero)
                {
                    throw new InvalidOperationException();
                }
                List<Dictionary<string, string>> outputs = new List<Dictionary<string, string>>();
                MpvNodeList list = Marshal.PtrToStructure<MpvNodeList>(node.value.listValue);
                int nodeSize = Marshal.SizeOf<MpvNode>();
                for (int index = 0; index < list.num; index += 1)
                {
                    MpvNode item = Marshal.PtrToStructure<MpvNode>(IntPtr.Add(list.values, index * nodeSize));
                    if (item.format != MpvFormatNodeMap || item.value.listValue == IntPtr.Zero)
                    {
                        continue;
                    }
                    MpvNodeList map = Marshal.PtrToStructure<MpvNodeList>(item.value.listValue);
                    string? nativeKey = null;
                    string? label = null;
                    for (int fieldIndex = 0; fieldIndex < map.num; fieldIndex += 1)
                    {
                        IntPtr keyPointer = Marshal.ReadIntPtr(map.keys, fieldIndex * IntPtr.Size);
                        string? key = Marshal.PtrToStringUTF8(keyPointer);
                        MpvNode value = Marshal.PtrToStructure<MpvNode>(
                            IntPtr.Add(map.values, fieldIndex * nodeSize));
                        if (value.format != MpvFormatString)
                        {
                            continue;
                        }
                        string? text = Marshal.PtrToStringUTF8(value.value.stringValue);
                        if (key == "name") nativeKey = text;
                        if (key == "description") label = text;
                    }
                    if (!string.IsNullOrEmpty(nativeKey))
                    {
                        outputs.Add(new Dictionary<string, string>
                        {
                            ["nativeKey"] = nativeKey,
                            ["label"] = label ?? string.Empty
                        });
                    }
                }
                return outputs;
            }
            finally
            {
                NativeMethods.mpv_free_node_contents(ref node);
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

                    DestroyPresentationOnOwnerThread();

                    InitializeMpv(msg);
                    CacheLoadedMedia(msg);

                    // Load media
                    int loadResult = Command(mpvContext, "loadfile", msg.playbackUrl, "replace");
                    if (loadResult >= 0)
                    {
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
                    WriteCommandResult(msg.requestId!, SetPropertyBool(mpvContext, "pause", false));
                }
                else if (msg.command == "pause")
                {
                    WriteCommandResult(msg.requestId!, SetPropertyBool(mpvContext, "pause", true));
                }
                else if (msg.command == "stop")
                {
                    WriteCommandResult(msg.requestId!, Command(mpvContext, "stop"));
                }
                else if (msg.command == "seek.absolute")
                {
                    double positionSeconds = 0;
                    if (msg.payload.TryGetProperty("positionMs", out JsonElement val))
                    {
                        positionSeconds = val.GetDouble() / 1000.0;
                    }
                    WriteCommandResult(
                        msg.requestId!,
                        Command(mpvContext, "seek", positionSeconds.ToString("F3", CultureInfo.InvariantCulture), "absolute"));
                }
                else if (msg.command == "seek.relative")
                {
                    double deltaSeconds = 0;
                    if (msg.payload.TryGetProperty("deltaMs", out JsonElement val))
                    {
                        deltaSeconds = val.GetDouble() / 1000.0;
                    }
                    WriteCommandResult(
                        msg.requestId!,
                        Command(mpvContext, "seek", deltaSeconds.ToString("F3", CultureInfo.InvariantCulture), "relative"));
                }
                else if (msg.command == "volume.set")
                {
                    double volume = 100;
                    if (msg.payload.TryGetProperty("volume", out JsonElement val))
                    {
                        volume = val.GetDouble() * 100.0;
                    }
                    WriteCommandResult(msg.requestId!, SetPropertyDouble(mpvContext, "volume", volume));
                }
                else if (msg.command == "mute.set")
                {
                    bool muted = false;
                    if (msg.payload.TryGetProperty("muted", out JsonElement val))
                    {
                        muted = val.GetBoolean();
                    }
                    WriteCommandResult(msg.requestId!, SetPropertyBool(mpvContext, "mute", muted));
                }
                else if (msg.command == "track.audio.select")
                {
                    if (msg.payload.ValueKind == JsonValueKind.Object &&
                        msg.payload.TryGetProperty("trackId", out JsonElement val) &&
                        val.ValueKind == JsonValueKind.String)
                    {
                        string publicTrackId = val.GetString()!;
                        string? mpvTrackId = trackState?.GetMpvTrackId(publicTrackId);
                        if (string.IsNullOrEmpty(mpvTrackId))
                        {
                            WriteResult(msg.requestId!, false, "PLAYER_HELPER_TRACK_NOT_FOUND", "Requested audio track is not available.");
                            return;
                        }
                        int res = MpvCommandExecutor.SetPropertyString(mpvContext, "aid", mpvTrackId);
                        if (res >= 0)
                        {
                            WriteResult(msg.requestId!, true, null, null);
                        }
                        else
                        {
                            WriteResult(msg.requestId!, false, "PLAYER_HELPER_COMMAND_FAILED", "Failed to select audio track.");
                        }
                    }
                    else
                    {
                        WriteResult(msg.requestId!, false, "PLAYER_HELPER_INVALID_COMMAND", "Missing or invalid trackId.");
                    }
                }
                else if (msg.command == "track.subtitle.select")
                {
                    if (msg.payload.ValueKind == JsonValueKind.Object &&
                        msg.payload.TryGetProperty("trackId", out JsonElement val))
                    {
                        if (val.ValueKind == JsonValueKind.Null)
                        {
                            int res = MpvCommandExecutor.SetPropertyString(mpvContext, "sid", "no");
                            if (res >= 0)
                            {
                                WriteResult(msg.requestId!, true, null, null);
                            }
                            else
                            {
                                WriteResult(msg.requestId!, false, "PLAYER_HELPER_COMMAND_FAILED", "Failed to disable subtitle track.");
                            }
                        }
                        else if (val.ValueKind == JsonValueKind.String)
                        {
                            string publicTrackId = val.GetString()!;
                            string? mpvTrackId = trackState?.GetMpvTrackId(publicTrackId);
                            if (string.IsNullOrEmpty(mpvTrackId))
                            {
                                WriteResult(msg.requestId!, false, "PLAYER_HELPER_TRACK_NOT_FOUND", "Requested subtitle track is not available.");
                                return;
                            }
                            int res = MpvCommandExecutor.SetPropertyString(mpvContext, "sid", mpvTrackId);
                            if (res >= 0)
                            {
                                WriteResult(msg.requestId!, true, null, null);
                            }
                            else
                            {
                                WriteResult(msg.requestId!, false, "PLAYER_HELPER_COMMAND_FAILED", "Failed to select subtitle track.");
                            }
                        }
                        else
                        {
                            WriteResult(msg.requestId!, false, "PLAYER_HELPER_INVALID_COMMAND", "Invalid trackId format.");
                        }
                    }
                    else
                    {
                        WriteResult(msg.requestId!, false, "PLAYER_HELPER_INVALID_COMMAND", "Missing trackId.");
                    }
                }
                else
                {
                    WriteResult(msg.requestId!, false, "PLAYER_HELPER_UNSUPPORTED_COMMAND", $"Command {msg.command} is not supported.");
                }
            }
            catch (Exception)
            {
                WriteResult(msg.requestId!, false, "PLAYER_HELPER_COMMAND_FAILED", "Native player command failed.");
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

                currentRequestId = msg.requestId;
                EnsureLibmpvResolverRegistered();

                mpvContext = NativeMethods.mpv_create();
                if (mpvContext == IntPtr.Zero)
                {
                    throw new InvalidOperationException("Native player initialization failed.");
                }

                EnsureOptionSet(mpvContext, "terminal", "no");
                EnsureOptionSet(mpvContext, "msg-level", "all=no");
                EnsureOptionSet(mpvContext, "vo", "libmpv");
                EnsureOptionSet(mpvContext, "osc", "no");
                EnsureOptionSet(mpvContext, "hwdec", "auto");
                if (!string.IsNullOrEmpty(msg.setup?.audioOutputNativeKey))
                {
                    EnsureOptionSet(mpvContext, "audio-device", msg.setup.audioOutputNativeKey);
                }
                if (msg.setup?.dtsPassthroughEnabled == true)
                {
                    EnsureOptionSet(mpvContext, "audio-spdif", "dts,dts-hd");
                }
                if (msg.credentialHeader != null &&
                    !string.IsNullOrEmpty(msg.credentialHeader.name) &&
                    !string.IsNullOrEmpty(msg.credentialHeader.value))
                {
                    EnsureOptionSet(
                        mpvContext,
                        "http-header-fields",
                        $"{msg.credentialHeader.name}: {msg.credentialHeader.value}");
                }

                int initResult = NativeMethods.mpv_initialize(mpvContext);
                if (initResult < 0)
                {
                    TeardownMpvContext();
                    throw new InvalidOperationException("Native player initialization failed.");
                }

                trackState = new MpvTrackState(mpvContext, msg.setup);
                qualityState = new MpvPlaybackQualityState(mpvContext, msg.setup?.playbackMode ?? "unknown");
                currentPlaybackSetup = msg.setup;

                ObserveProperty(mpvContext, 1, "time-pos", MpvFormatDouble);
                ObserveProperty(mpvContext, 2, "duration", MpvFormatDouble);
                ObserveProperty(mpvContext, 3, "pause", MpvFormatFlag);
                ObserveProperty(mpvContext, 4, "core-idle", MpvFormatFlag);
                ObserveProperty(mpvContext, 5, "aid", MpvFormatString);
                ObserveProperty(mpvContext, 6, "sid", MpvFormatString);
                ObserveProperty(mpvContext, 7, "vid", MpvFormatString);
                ObserveProperty(mpvContext, 8, "video-params", MpvFormatNone);
                ObserveProperty(mpvContext, 9, "video-codec", MpvFormatString);
                ObserveProperty(mpvContext, 10, "audio-codec", MpvFormatString);

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
                    trackState?.RefreshTrackMappings();
                    if (!ApplySelectedTracks(currentPlaybackSetup?.selectedTrackIds))
                    {
                        WriteCommandFailureEvent(currentRequestId);
                        continue;
                    }

                    // Emit tracks.changed event
                    WriteOutputEvent(new Dictionary<string, object?>
                    {
                        ["type"] = "tracks.changed",
                        ["requestId"] = currentRequestId,
                        ["tracks"] = trackState?.GetTracksSummary() ?? new List<Dictionary<string, object>>()
                    });

                    // Emit quality.changed event
                    EmitQualityChanged();

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
                        ["tracks"] = trackState?.GetTracksSummary() ?? new List<Dictionary<string, object>>()
                    });

                    isBuffering = false;
                    UpdatePlaybackState();
                }
                else if (ev.event_id == MpvEventEndFile)
                {
                    HandleEndFileEvent(ev.data);
                }
                else if (ev.event_id == MpvEventPropertyChange)
                {
                    MpvEventProperty prop = Marshal.PtrToStructure<MpvEventProperty>(ev.data);
                    HandlePropertyChange(prop);
                }
            }
        }

        private static void HandleEndFileEvent(IntPtr data)
        {
            if (data == IntPtr.Zero)
            {
                WritePlaybackEndedWithError(false);
                return;
            }

            MpvEventEndFileData endFile = Marshal.PtrToStructure<MpvEventEndFileData>(data);
            if (endFile.reason == MpvEndFileReasonRedirect)
            {
                return;
            }
            if (endFile.reason == MpvEndFileReasonEof ||
                endFile.reason == MpvEndFileReasonStop ||
                endFile.reason == MpvEndFileReasonQuit)
            {
                WriteOutputEvent(new Dictionary<string, object?>
                {
                    ["type"] = "ended",
                    ["requestId"] = currentRequestId
                });
                return;
            }
            WritePlaybackEndedWithError(endFile.reason == MpvEndFileReasonError);
        }

        private static void WritePlaybackEndedWithError(bool retryable)
        {
            WriteOutputEvent(new Dictionary<string, object?>
            {
                ["type"] = "error",
                ["requestId"] = currentRequestId,
                ["error"] = new Dictionary<string, object?>
                {
                    ["code"] = "PLAYER_HELPER_PLAYBACK_ENDED_WITH_ERROR",
                    ["category"] = "engine-failure",
                    ["message"] = "Native playback ended with a player engine error.",
                    ["recoverable"] = retryable,
                    ["retryable"] = retryable
                }
            });
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
            else if (prop.name == "aid" || prop.name == "sid" || prop.name == "vid")
            {
                EmitTrackSelectionChanged();
            }
            else if (prop.name == "video-params" || prop.name == "video-codec" || prop.name == "audio-codec")
            {
                EmitQualityChanged();
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

        private static void HandlePresentationUpdate(InputMessage message)
        {
            if (message.version != 1 || string.IsNullOrWhiteSpace(message.operationId) ||
                message.documentEpoch <= 0 || message.revision <= 0 ||
                string.IsNullOrWhiteSpace(message.parentHwnd) || message.parentPid <= 0 ||
                string.IsNullOrWhiteSpace(message.mode))
            {
                WritePresentationResult(message, "rejected");
                return;
            }
            if (!TryAdvancePresentationOperationSequence(message.operationId))
            {
                WritePresentationResult(message, "rejected");
                return;
            }
            PresentationWork work = new PresentationWork { Message = message };
            if (!PresentationQueue.TryAdd(work))
            {
                WritePresentationResult(message, "rejected");
                return;
            }
            work.Completed.Wait();
            WritePresentationResult(message, work.Status);
        }

        private static bool TryAdvancePresentationOperationSequence(string operationId)
        {
            const string prefix = "presentation-";
            if (!operationId.StartsWith(prefix, StringComparison.Ordinal) ||
                !BigInteger.TryParse(operationId.Substring(prefix.Length), NumberStyles.None, CultureInfo.InvariantCulture, out BigInteger sequence) ||
                sequence <= latestPresentationOperationSequence)
            {
                return false;
            }
            latestPresentationOperationSequence = sequence;
            return true;
        }

        private static void PresentationLoop()
        {
            while (!PresentationQueue.IsCompleted)
            {
                if (PresentationQueue.TryTake(out PresentationWork? work, 16))
                {
                    try
                    {
                        work.Status = ExecutePresentationWork(work.Message);
                    }
                    catch
                    {
                        ContainPresentationFailure();
                        work.Status = "rejected";
                    }
                    finally
                    {
                        work.Completed.Set();
                    }
                }
                try
                {
                    RenderFrame();
                    PumpWindowMessages();
                }
                catch
                {
                    FailPresentationLifecycle();
                    return;
                }
            }
            DestroyPresentationResources();
        }

        private static string ExecutePresentationWork(InputMessage message)
        {
            if (message.type == "presentation.destroy")
            {
                DestroyPresentationResources();
                return "hidden";
            }
            bool exactTuple = message.documentEpoch == latestPresentationEpoch &&
                message.revision == latestPresentationRevision &&
                String.Equals(latestPresentationLoadedRequestId, message.loadedRequestId, StringComparison.Ordinal);
            bool staleRevision = message.documentEpoch < latestPresentationEpoch ||
                message.documentEpoch == latestPresentationEpoch && message.revision < latestPresentationRevision;
            bool stalePair = staleRevision ||
                message.documentEpoch == latestPresentationEpoch && message.revision == latestPresentationRevision &&
                    !String.Equals(latestPresentationLoadedRequestId, message.loadedRequestId, StringComparison.Ordinal) ||
                exactTuple && latestPresentationHidden && message.mode != "hidden";
            if (message.mode == "hidden")
            {
                if (!HidePresentationSurface()) return "rejected";
                latestPresentationHidden = true;
                if (staleRevision) return "stale";
                latestPresentationEpoch = message.documentEpoch;
                latestPresentationRevision = message.revision;
                latestPresentationLoadedRequestId = message.loadedRequestId;
                return "hidden";
            }
            if (stalePair)
            {
                if (!HidePresentationSurface()) return "rejected";
                return "stale";
            }
            if (message.loadedRequestId == null || message.loadedRequestId != currentRequestId || message.bounds == null ||
                !ulong.TryParse(message.parentHwnd, NumberStyles.None, CultureInfo.InvariantCulture, out ulong rawParent) || rawParent == 0)
            {
                if (!HidePresentationSurface()) return "rejected";
                return "stale";
            }
            IntPtr parent = unchecked((IntPtr)(long)rawParent);
            if (renderSurface == null || !renderSurface.HasParent(parent))
            {
                DestroyPresentationResources();
                renderSurface = RenderSurface.TryCreate(parent, message.parentPid);
            }
            if (renderSurface == null || !renderSurface.ApplyBounds(message.bounds, message.mode == "guide-classic-pip"))
            {
                HidePresentationSurface();
                return "rejected";
            }
            EnsureRenderContext();
            if (!renderSurface.Show())
            {
                DestroyPresentationResources();
                return "rejected";
            }
            latestPresentationEpoch = message.documentEpoch;
            latestPresentationRevision = message.revision;
            latestPresentationLoadedRequestId = message.loadedRequestId;
            latestPresentationHidden = false;
            return "applied";
        }

        private static bool HidePresentationSurface()
        {
            if (renderSurface == null || renderSurface.Hide()) return true;
            DestroyPresentationResources();
            return false;
        }

        private static void EnsureRenderContext()
        {
            if (renderContext != IntPtr.Zero) return;
            if (renderSurface == null || mpvContext == IntPtr.Zero) throw new InvalidOperationException();
            IntPtr apiType = Marshal.StringToHGlobalAnsi("opengl");
            MpvOpenGlInitParams initParams = new MpvOpenGlInitParams
            {
                get_proc_address = Marshal.GetFunctionPointerForDelegate(OpenGlGetProcAddress),
                get_proc_address_ctx = IntPtr.Zero
            };
            IntPtr initParamsPtr = Marshal.AllocHGlobal(Marshal.SizeOf<MpvOpenGlInitParams>());
            Marshal.StructureToPtr(initParams, initParamsPtr, false);
            IntPtr initParamArray = AllocRenderParams(new MpvRenderParam { type = 1, data = apiType }, new MpvRenderParam { type = 2, data = initParamsPtr });
            try
            {
                if (!renderSurface.MakeCurrent()) throw new InvalidOperationException();
                if (NativeMethods.mpv_render_context_create(out renderContext, mpvContext, initParamArray) < 0) renderContext = IntPtr.Zero;
                NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
            }
            finally
            {
                Marshal.FreeHGlobal(initParamArray); Marshal.FreeHGlobal(initParamsPtr); Marshal.FreeHGlobal(apiType);
            }
            if (renderContext == IntPtr.Zero) throw new InvalidOperationException();
        }

        private static void RenderFrame()
        {
            if (renderContext == IntPtr.Zero || renderSurface == null || !renderSurface.Visible) return;
            if (!renderSurface.MakeCurrent()) throw new InvalidOperationException();
            NativeMethods.glViewport(0, 0, renderSurface.Width, renderSurface.Height);
            NativeMethods.glClearColor(0, 0, 0, 1); NativeMethods.glClear(GlColorBufferBit);
            IntPtr renderParams = AllocRenderParams(new MpvRenderParam { type = 3, data = renderSurface.FboParam }, new MpvRenderParam { type = 4, data = renderSurface.FlipYParam });
            try { NativeMethods.mpv_render_context_update(renderContext); NativeMethods.mpv_render_context_render(renderContext, renderParams); }
            finally { Marshal.FreeHGlobal(renderParams); }
            if (!NativeMethods.SwapBuffers(renderSurface.DeviceContext)) throw new InvalidOperationException();
        }

        private static void DestroyPresentationResources()
        {
            IntPtr context = renderContext;
            renderContext = IntPtr.Zero;
            try
            {
                if (context != IntPtr.Zero) NativeMethods.mpv_render_context_free(context);
            }
            catch
            {
            }

            RenderSurface? surface = renderSurface;
            renderSurface = null;
            try
            {
                surface?.Dispose();
            }
            catch
            {
            }
        }

        private static void ContainPresentationFailure()
        {
            try
            {
                HidePresentationSurface();
            }
            catch
            {
            }
            DestroyPresentationResources();
            latestPresentationHidden = true;
        }

        private static void FailPresentationLifecycle()
        {
            ContainPresentationFailure();
            Environment.Exit(1);
        }

        private static void WritePresentationResult(InputMessage message, string status)
        {
            Console.Out.WriteLine(JsonSerializer.Serialize(new Dictionary<string, object?> {
                ["type"] = "presentation.result", ["version"] = 1, ["operationId"] = message.operationId,
                ["documentEpoch"] = message.documentEpoch, ["revision"] = message.revision, ["status"] = status
            }));
            Console.Out.Flush();
        }

        private static void HandleCleanup(string? requestId)
        {
            DestroyPresentationOnOwnerThread();
            lock (MpvLock)
            {
                TeardownMpvContext();
            }
        }

        private static void DestroyPresentationOnOwnerThread()
        {
            PresentationWork destroy = new PresentationWork { Message = new InputMessage { type = "presentation.destroy", operationId = "cleanup", documentEpoch = 1, revision = 1, mode = "hidden" } };
            if (!PresentationQueue.TryAdd(destroy))
            {
                throw new InvalidOperationException("Native presentation cleanup could not be queued.");
            }
            destroy.Completed.Wait();
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

            currentRequestId = null;
            currentMediaId = null;
            currentMediaTitle = null;
            currentPlaybackSetup = null;
            cachedDurationSeconds = 0;
            isPaused = false;
            isBuffering = false;
            trackState = null;
            qualityState = null;
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

        private static void EmitTrackSelectionChanged()
        {
            if (trackState == null) return;
            WriteOutputEvent(new Dictionary<string, object?>
            {
                ["type"] = "track.selection.changed",
                ["requestId"] = currentRequestId,
                ["audioTrackId"] = trackState.GetSelectedAudioTrackId(),
                ["subtitleTrackId"] = trackState.GetSelectedSubtitleTrackId(),
                ["videoTrackId"] = trackState.GetSelectedVideoTrackId()
            });
        }

        private static void EmitQualityChanged()
        {
            if (qualityState == null) return;
            WriteOutputEvent(new Dictionary<string, object?>
            {
                ["type"] = "quality.changed",
                ["requestId"] = currentRequestId,
                ["quality"] = qualityState.GetQualitySummary()
            });
        }

        private static bool ApplySelectedTracks(TrackSelection? selection)
        {
            if (selection == null)
            {
                return true;
            }

            bool applied = SetSelectedPublicTrack("aid", selection.audio);
            applied &= SetSelectedPublicTrack("sid", selection.subtitle);
            applied &= SetSelectedPublicTrack("vid", selection.video);
            return applied;
        }

        private static bool SetSelectedPublicTrack(string property, string? publicTrackId)
        {
            if (string.IsNullOrWhiteSpace(publicTrackId))
            {
                return true;
            }
            string? mpvTrackId = trackState?.GetMpvTrackId(publicTrackId);
            if (string.IsNullOrWhiteSpace(mpvTrackId))
            {
                return true;
            }
            return MpvCommandExecutor.SetPropertyString(mpvContext, property, mpvTrackId) >= 0;
        }

        private static void WriteCommandFailureEvent(string? requestId)
        {
            WriteOutputEvent(new Dictionary<string, object?>
            {
                ["type"] = "error",
                ["requestId"] = requestId,
                ["error"] = new Dictionary<string, object?>
                {
                    ["code"] = "PLAYER_HELPER_COMMAND_FAILED",
                    ["message"] = "Native player command failed.",
                    ["category"] = "helper-failure",
                    ["recoverable"] = true,
                    ["retryable"] = true
                }
            });
        }

        private static int SetOption(IntPtr mpv, string name, string value)
        {
            return NativeMethods.mpv_set_option_string(mpv, name, value);
        }

        private static void EnsureOptionSet(IntPtr mpv, string name, string value)
        {
            if (SetOption(mpv, name, value) < 0)
            {
                TeardownMpvContext();
                throw new InvalidOperationException("Native player initialization failed.");
            }
        }

        private static void ObserveProperty(IntPtr mpv, ulong replyUserdata, string name, int format)
        {
            if (NativeMethods.mpv_observe_property(mpv, replyUserdata, name, format) < 0)
            {
                TeardownMpvContext();
                throw new InvalidOperationException("Native player initialization failed.");
            }
        }

        private static int SetPropertyBool(IntPtr mpv, string name, bool value)
        {
            IntPtr data = Marshal.AllocHGlobal(sizeof(int));
            try
            {
                Marshal.WriteInt32(data, value ? 1 : 0);
                return NativeMethods.mpv_set_property(mpv, name, MpvFormatFlag, data);
            }
            finally
            {
                Marshal.FreeHGlobal(data);
            }
        }

        private static int SetPropertyDouble(IntPtr mpv, string name, double value)
        {
            IntPtr data = Marshal.AllocHGlobal(sizeof(long));
            try
            {
                Marshal.WriteInt64(data, BitConverter.DoubleToInt64Bits(value));
                return NativeMethods.mpv_set_property(mpv, name, MpvFormatDouble, data);
            }
            finally
            {
                Marshal.FreeHGlobal(data);
            }
        }

        private static void WriteCommandResult(string requestId, int nativeResult)
        {
            if (nativeResult >= 0)
            {
                WriteResult(requestId, true, null, null);
                return;
            }

            WriteResult(requestId, false, "PLAYER_HELPER_COMMAND_FAILED", "Native player command failed.");
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

        private static void WriteAudioOutputResult(
            string requestId,
            bool ok,
            List<Dictionary<string, string>>? outputs)
        {
            var result = new Dictionary<string, object>
            {
                ["type"] = "audio-output.result",
                ["requestId"] = requestId,
                ["ok"] = ok
            };
            if (ok)
            {
                result["outputs"] = outputs ?? new List<Dictionary<string, string>>();
            }
            else
            {
                result["error"] = new Dictionary<string, object>
                {
                    ["code"] = "PLAYER_HELPER_AUDIO_OUTPUT_QUERY_FAILED",
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
            private readonly IntPtr parent;
            private readonly int parentPid;

            public readonly IntPtr DeviceContext;
            public int Width { get; private set; }
            public int Height { get; private set; }
            public bool Visible { get; private set; }
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
                int height,
                IntPtr parent,
                int parentPid)
            {
                this.instance = instance;
                this.classAtom = classAtom;
                this.className = className;
                this.window = window;
                DeviceContext = deviceContext;
                this.renderingContext = renderingContext;
                Width = width;
                Height = height;
                this.parent = parent;
                this.parentPid = parentPid;

                MpvOpenGlFbo fbo = new MpvOpenGlFbo { fbo = 0, w = Width, h = Height, internal_format = 0 };
                FboParam = Marshal.AllocHGlobal(Marshal.SizeOf<MpvOpenGlFbo>());
                Marshal.StructureToPtr(fbo, FboParam, false);
                FlipYParam = Marshal.AllocHGlobal(sizeof(int));
                Marshal.WriteInt32(FlipYParam, 1);
            }

            public static RenderSurface? TryCreate(IntPtr parent, int parentPid)
            {
                if (!ValidateParent(parent, parentPid, out _, out _, out _)) return null;
                IntPtr instance = NativeMethods.GetModuleHandle(null);
                string className = "LineupNativePlayerPresentationHost";
                int width = 1;
                int height = 1;
                int style = unchecked((int)0x4E000000); // WS_CHILD | CLIPSIBLINGS | CLIPCHILDREN | DISABLED
                int exStyle = unchecked((int)0x08000004); // NOACTIVATE | NOPARENTNOTIFY

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
                    exStyle,
                    className,
                    string.Empty,
                    style,
                    0,
                    0,
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

                NativeMethods.wglMakeCurrent(IntPtr.Zero, IntPtr.Zero);
                return new RenderSurface(instance, new IntPtr(atom), className, window, deviceContext, renderingContext, width, height, parent, parentPid);
            }

            public bool HasParent(IntPtr value) => value == parent;

            public bool ApplyBounds(NormalizedBounds bounds, bool classic)
            {
                if (!ValidateParent(parent, parentPid, out NativeMethods.RECT client, out uint dpi, out NativeMethods.RECT stableClient)) return false;
                if (client.left != stableClient.left || client.top != stableClient.top || client.right != stableClient.right || client.bottom != stableClient.bottom) return false;
                int clientWidth = client.right - client.left, clientHeight = client.bottom - client.top;
                if (clientWidth <= 0 || clientHeight <= 0 || !FiniteBounds(bounds)) return false;
                int left = Clamp((int)Math.Floor(bounds.x * clientWidth), 0, clientWidth);
                int top = Clamp((int)Math.Floor(bounds.y * clientHeight), 0, clientHeight);
                int right = Clamp((int)Math.Ceiling((bounds.x + bounds.width) * clientWidth), 0, clientWidth);
                int bottom = Clamp((int)Math.Ceiling((bounds.y + bounds.height) * clientHeight), 0, clientHeight);
                int width = right - left, height = bottom - top;
                int inset = (int)Math.Ceiling(16.0 * dpi / 96.0);
                if (width <= 0 || height <= 0 || classic && (width < 160 || height < 90 || width > clientWidth / 2 || height > clientHeight / 2 || left < inset || top < inset || clientWidth - right < inset || clientHeight - bottom < inset)) return false;
                if (!NativeMethods.SetWindowPos(window, HwndBottom, left, top, width, height, SwpNoActivate)) return false;
                Width = width; Height = height;
                Marshal.StructureToPtr(new MpvOpenGlFbo { fbo = 0, w = Width, h = Height, internal_format = 0 }, FboParam, false);
                return true;
            }

            public bool Show()
            {
                bool shown = NativeMethods.SetWindowPos(window, HwndBottom, 0, 0, 0, 0, 0x0001 | 0x0002 | SwpNoActivate | SwpShowWindow);
                if (shown) Visible = true;
                return shown;
            }

            public bool Hide()
            {
                bool hidden = NativeMethods.SetWindowPos(window, HwndBottom, 0, 0, 0, 0, 0x0001 | 0x0002 | SwpNoActivate | SwpHideWindow);
                if (hidden) Visible = false;
                return hidden;
            }

            public bool MakeCurrent()
            {
                return NativeMethods.wglMakeCurrent(DeviceContext, renderingContext);
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
                if (msg == 0x0021) return new IntPtr(3); // WM_MOUSEACTIVATE / MA_NOACTIVATE
                if (msg == 0x003D) return IntPtr.Zero; // WM_GETOBJECT: no native accessibility provider
                return NativeMethods.DefWindowProc(hwnd, msg, wParam, lParam);
            }

            private static bool ValidateParent(IntPtr parent, int expectedPid, out NativeMethods.RECT client, out uint dpi, out NativeMethods.RECT stableClient)
            {
                client = default; stableClient = default; dpi = 0;
                if (!NativeMethods.IsWindow(parent)) return false;
                NativeMethods.GetWindowThreadProcessId(parent, out uint pid);
                if (pid != (uint)expectedPid || !NativeMethods.AreDpiAwarenessContextsEqual(NativeMethods.GetWindowDpiAwarenessContext(parent), NativeMethods.GetThreadDpiAwarenessContext())) return false;
                uint before = NativeMethods.GetDpiForWindow(parent);
                if (before == 0 || !NativeMethods.GetClientRect(parent, out client)) return false;
                uint after = NativeMethods.GetDpiForWindow(parent);
                if (before != after || !NativeMethods.GetClientRect(parent, out stableClient) || !NativeMethods.IsWindow(parent)) return false;
                NativeMethods.GetWindowThreadProcessId(parent, out uint stablePid);
                if (stablePid != (uint)expectedPid) return false;
                dpi = after; return true;
            }

            private static bool FiniteBounds(NormalizedBounds value) =>
                double.IsFinite(value.x) && double.IsFinite(value.y) && double.IsFinite(value.width) && double.IsFinite(value.height) &&
                value.x >= 0 && value.y >= 0 && value.width > 0 && value.height > 0 && value.x + value.width <= 1 && value.y + value.height <= 1;
            private static int Clamp(int value, int min, int max) => Math.Min(Math.Max(value, min), max);
        }

        internal static class NativeMethods
        {
            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern IntPtr mpv_create();

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_initialize(IntPtr context);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern int mpv_set_option_string(IntPtr context, string name, string value);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
            public static extern int mpv_set_property_string(IntPtr context, string name, string value);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
            public static extern int mpv_set_property(IntPtr context, string name, int format, IntPtr data);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
            public static extern IntPtr mpv_get_property_string(IntPtr context, string name);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
            internal static extern int mpv_get_property(IntPtr context, string name, int format, ref MpvNode data);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            public static extern void mpv_free(IntPtr data);

            [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
            internal static extern void mpv_free_node_contents(ref MpvNode node);

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

            [DllImport("user32.dll")]
            public static extern bool IsWindow(IntPtr hWnd);

            [DllImport("user32.dll")]
            public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

            [DllImport("user32.dll")]
            public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hWnd);

            [DllImport("user32.dll")]
            public static extern IntPtr GetThreadDpiAwarenessContext();

            [DllImport("user32.dll")]
            public static extern bool AreDpiAwarenessContextsEqual(IntPtr dpiContextA, IntPtr dpiContextB);

            [DllImport("user32.dll")]
            public static extern uint GetDpiForWindow(IntPtr hWnd);

            [DllImport("user32.dll")]
            public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

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
            public struct RECT
            {
                public int left;
                public int top;
                public int right;
                public int bottom;
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
