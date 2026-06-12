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
                    MapTrackByPrivateId(_setup.trackMap.audio, id);
                }
                else if (type == "sub")
                {
                    MapTrackByPrivateId(_setup.trackMap.subtitle, id);
                }
                else if (type == "video")
                {
                    MapTrackByPrivateId(_setup.trackMap.video, id);
                }
            }
        }

        private void MapTrackByPrivateId<TTrack>(IEnumerable<TTrack>? tracks, string mpvTrackId)
            where TTrack : class
        {
            if (tracks == null)
            {
                return;
            }

            foreach (var track in tracks)
            {
                string? publicTrackId = null;
                string? privateTrackId = null;

                switch (track)
                {
                    case Program.AudioTrackMapItem audio:
                        publicTrackId = audio.publicTrackId;
                        privateTrackId = audio.privateTrackId;
                        break;
                    case Program.SubtitleTrackMapItem subtitle:
                        publicTrackId = subtitle.publicTrackId;
                        privateTrackId = subtitle.privateTrackId;
                        break;
                    case Program.VideoTrackMapItem video:
                        publicTrackId = video.publicTrackId;
                        privateTrackId = video.privateTrackId;
                        break;
                }

                if (string.IsNullOrEmpty(publicTrackId) || privateTrackId != mpvTrackId)
                {
                    continue;
                }

                _publicToMpvId[publicTrackId] = mpvTrackId;
                _mpvToPublicId[mpvTrackId] = publicTrackId;
                return;
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
