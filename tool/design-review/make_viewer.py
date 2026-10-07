"""Builds build/design-review/index.html from the tracked capture inputs."""
import json
from pathlib import Path

repo_root = Path(__file__).resolve().parents[2]
root = repo_root / 'build' / 'design-review'
captures = root / 'captures'
template = Path(__file__).with_name('viewer_template.html')
configs = ['1280x720', '1366x768', '1536x864@125', '1920x1080', '1920x1200',
           '2560x1440', '3440x1440', '3840x2160', '1920x1080-text150']
families = [
    ('Onboarding', ['onboarding', 'linking', 'linking-failure', 'profiles', 'profile-pin', 'servers', 'account-pickers']),
    ('Channel setup', ['setup-libraries', 'setup-configure', 'setup-review', 'setup-review-removals', 'setup-apply']),
    ('Guide', ['guide', 'guide-pip', 'guide-rich', 'guide-loading', 'guide-error', 'guide-empty', 'lineup-menu']),
    ('Player', ['player-osd', 'player-now-playing', 'player-now-playing-fallback', 'mini-guide', 'player-tracks', 'player-sleep', 'player-states', 'player-notices']),
    ('Channels & Studio', ['channels', 'studio']),
    ('Settings', ['settings', 'settings-over-playback']),
    ('Themes', ['theme-ember-steel', 'theme-slate-pine', 'theme-swiss', 'theme-directv']),
    ('Diagnostics', ['diagnostics']),
]
available = {c: {p.stem for p in (captures / c).glob('*.png')}
             for c in configs if (captures / c).is_dir()}
names = sorted(set().union(*available.values()))
items = []
for family, scenes in families:
    for scene in scenes:
        for name in names:
            if name.split('--')[0] == scene:
                items.append({'family': family, 'name': name,
                              'configs': [c for c in configs if name in available.get(c, ())]})
html = template.read_text().replace(
    '/*DATA*/', json.dumps({'configs': [c for c in configs if c in available], 'items': items}))
(root / 'index.html').write_text(html)
print(len(items), 'states,', sum(len(i['configs']) for i in items), 'captures')
