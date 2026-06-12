using System;
using System.Collections.Generic;

namespace Lineup.NativePlayerHost
{
    internal sealed class MpvPlaybackQualityState
    {
        private readonly IntPtr _mpv;
        private readonly string _playbackMode;

        public MpvPlaybackQualityState(IntPtr mpv, string playbackMode)
        {
            _mpv = mpv;
            _playbackMode = playbackMode;
        }

        public Dictionary<string, object?> GetQualitySummary()
        {
            string? videoCodec = MpvCommandExecutor.GetPropertyString(_mpv, "video-codec");
            string? audioCodec = MpvCommandExecutor.GetPropertyString(_mpv, "audio-codec");

            string sourceDynamicRange = GetSourceDynamicRange();
            string outputDynamicRange = GetOutputDynamicRange(sourceDynamicRange);

            var summary = new Dictionary<string, object?>
            {
                ["mode"] = _playbackMode,
                ["sourceDynamicRange"] = sourceDynamicRange,
                ["outputDynamicRangeStatus"] = outputDynamicRange
            };

            if (!string.IsNullOrEmpty(videoCodec))
            {
                summary["videoCodec"] = videoCodec;
            }
            if (!string.IsNullOrEmpty(audioCodec))
            {
                summary["audioCodec"] = audioCodec;
            }

            return summary;
        }

        private string GetSourceDynamicRange()
        {
            string? primaries = MpvCommandExecutor.GetPropertyString(_mpv, "video-params/primaries");
            string? gamma = MpvCommandExecutor.GetPropertyString(_mpv, "video-params/gamma");

            if (primaries == "bt.2020" && (gamma == "pq" || gamma == "hlg"))
            {
                return "hdr10";
            }
            if (!string.IsNullOrEmpty(primaries))
            {
                return "sdr";
            }
            return "unknown";
        }

        private string GetOutputDynamicRange(string sourceRange)
        {
            if (sourceRange == "hdr10" || sourceRange == "dolby-vision")
            {
                return "tone-mapped";
            }
            if (sourceRange == "sdr")
            {
                return "sdr";
            }
            return "unknown";
        }
    }
}
