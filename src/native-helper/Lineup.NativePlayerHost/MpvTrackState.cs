using System;
using System.Collections.Generic;

namespace Lineup.NativePlayerHost
{
    internal sealed class MpvTrackState
    {
        private readonly IntPtr _mpv;
        private readonly Program.PlaybackSetup? _setup;

        // Maps publicTrackId -> mpv track ID (string)
        private readonly Dictionary<string, string> _publicToMpvId = new Dictionary<string, string>();
        // Maps mpv track ID -> publicTrackId
        private readonly Dictionary<string, string> _mpvToPublicId = new Dictionary<string, string>();

        public MpvTrackState(IntPtr mpv, Program.PlaybackSetup? setup)
        {
            _mpv = mpv;
            _setup = setup;
            RefreshTrackMappings();
        }

        public void RefreshTrackMappings()
        {
            _publicToMpvId.Clear();
            _mpvToPublicId.Clear();

            if (_setup?.trackMap == null)
            {
                return;
            }

            string? countStr = MpvCommandExecutor.GetPropertyString(_mpv, "track-list/count");
            if (string.IsNullOrEmpty(countStr) || !int.TryParse(countStr, out int count))
            {
                return;
            }

            int audioIdx = 0;
            int subtitleIdx = 0;
            int videoIdx = 0;

            for (int i = 0; i < count; i++)
            {
                string? type = MpvCommandExecutor.GetPropertyString(_mpv, $"track-list/{i}/type");
                string? id = MpvCommandExecutor.GetPropertyString(_mpv, $"track-list/{i}/id");

                if (string.IsNullOrEmpty(type) || string.IsNullOrEmpty(id))
                {
                    continue;
                }

                if (type == "audio")
                {
                    if (_setup.trackMap.audio != null && audioIdx < _setup.trackMap.audio.Count)
                    {
                        var trackInfo = _setup.trackMap.audio[audioIdx];
                        if (trackInfo.publicTrackId != null)
                        {
                            _publicToMpvId[trackInfo.publicTrackId] = id;
                            _mpvToPublicId[id] = trackInfo.publicTrackId;
                        }
                    }
                    audioIdx++;
                }
                else if (type == "sub")
                {
                    if (_setup.trackMap.subtitle != null && subtitleIdx < _setup.trackMap.subtitle.Count)
                    {
                        var trackInfo = _setup.trackMap.subtitle[subtitleIdx];
                        if (trackInfo.publicTrackId != null)
                        {
                            _publicToMpvId[trackInfo.publicTrackId] = id;
                            _mpvToPublicId[id] = trackInfo.publicTrackId;
                        }
                    }
                    subtitleIdx++;
                }
                else if (type == "video")
                {
                    if (_setup.trackMap.video != null && videoIdx < _setup.trackMap.video.Count)
                    {
                        var trackInfo = _setup.trackMap.video[videoIdx];
                        if (trackInfo.publicTrackId != null)
                        {
                            _publicToMpvId[trackInfo.publicTrackId] = id;
                            _mpvToPublicId[id] = trackInfo.publicTrackId;
                        }
                    }
                    videoIdx++;
                }
            }
        }

        public string? GetMpvTrackId(string publicTrackId)
        {
            return _publicToMpvId.TryGetValue(publicTrackId, out string? val) ? val : null;
        }

        public string? GetPublicTrackId(string mpvTrackId)
        {
            return _mpvToPublicId.TryGetValue(mpvTrackId, out string? val) ? val : null;
        }

        public List<Dictionary<string, object>> GetTracksSummary()
        {
            var result = new List<Dictionary<string, object>>();
            if (_setup?.trackMap == null)
            {
                return result;
            }

            // Get selected mpv track IDs
            HashSet<string> selectedMpvIds = new HashSet<string>();
            string? countStr = MpvCommandExecutor.GetPropertyString(_mpv, "track-list/count");
            if (int.TryParse(countStr, out int count))
            {
                for (int i = 0; i < count; i++)
                {
                    string? selected = MpvCommandExecutor.GetPropertyString(_mpv, $"track-list/{i}/selected");
                    string? id = MpvCommandExecutor.GetPropertyString(_mpv, $"track-list/{i}/id");
                    if (selected == "yes" && !string.IsNullOrEmpty(id))
                    {
                        selectedMpvIds.Add(id);
                    }
                }
            }

            // Now project all tracks from setup.trackMap, setting selected state based on selectedMpvIds
            if (_setup.trackMap.audio != null)
            {
                foreach (var track in _setup.trackMap.audio)
                {
                    if (track.publicTrackId == null) continue;
                    string? mpvId = GetMpvTrackId(track.publicTrackId);
                    bool selected = mpvId != null && selectedMpvIds.Contains(mpvId);
                    
                    var item = new Dictionary<string, object>
                    {
                        ["id"] = track.publicTrackId,
                        ["kind"] = "audio",
                        ["label"] = track.label ?? "Audio Track",
                        ["selected"] = selected,
                        ["available"] = mpvId != null
                    };
                    if (track.language != null) item["language"] = track.language;
                    if (track.codec != null) item["codec"] = track.codec;
                    if (track.channelCount != null) item["channelCount"] = track.channelCount.Value;
                    if (track.@default != null) item["default"] = track.@default.Value;

                    result.Add(item);
                }
            }

            if (_setup.trackMap.subtitle != null)
            {
                foreach (var track in _setup.trackMap.subtitle)
                {
                    if (track.publicTrackId == null) continue;
                    string? mpvId = GetMpvTrackId(track.publicTrackId);
                    bool selected = mpvId != null && selectedMpvIds.Contains(mpvId);

                    var item = new Dictionary<string, object>
                    {
                        ["id"] = track.publicTrackId,
                        ["kind"] = "subtitle",
                        ["label"] = track.label ?? "Subtitle Track",
                        ["selected"] = selected,
                        ["available"] = mpvId != null
                    };
                    if (track.language != null) item["language"] = track.language;
                    if (track.format != null) item["format"] = track.format;
                    if (track.deliveryType != null) item["deliveryType"] = track.deliveryType;
                    if (track.forced != null) item["forced"] = track.forced.Value;
                    if (track.@default != null) item["default"] = track.@default.Value;

                    result.Add(item);
                }
            }

            return result;
        }

        public string? GetSelectedAudioTrackId()
        {
            string? mpvId = MpvCommandExecutor.GetPropertyString(_mpv, "aid");
            if (string.IsNullOrEmpty(mpvId) || mpvId == "no")
            {
                return null;
            }
            return GetPublicTrackId(mpvId);
        }

        public string? GetSelectedSubtitleTrackId()
        {
            string? mpvId = MpvCommandExecutor.GetPropertyString(_mpv, "sid");
            if (string.IsNullOrEmpty(mpvId) || mpvId == "no")
            {
                return null;
            }
            return GetPublicTrackId(mpvId);
        }

        public string? GetSelectedVideoTrackId()
        {
            string? mpvId = MpvCommandExecutor.GetPropertyString(_mpv, "vid");
            if (string.IsNullOrEmpty(mpvId) || mpvId == "no")
            {
                return null;
            }
            return GetPublicTrackId(mpvId);
        }
    }
}
