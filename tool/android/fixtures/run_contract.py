#!/usr/bin/env python3
"""Run an identified installed fixture APK on an explicitly assigned target."""
import argparse
import json
import pathlib
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--case', choices=['contract', 'negative', 'lifetime', 'background', 'release-isolation', 'formats', 'seek-lifetime'], required=True)
parser.add_argument('--evidence', type=pathlib.Path, required=True)
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
adb = ['adb', '-s', args.serial]

def run(*command):
    return subprocess.check_output([*adb, *command], text=True, stderr=subprocess.STDOUT)

run('shell', 'am', 'force-stop', 'com.tjzine.lineup')
launch = run('shell', 'am', 'start', '-n', 'com.tjzine.lineup/.MainActivity', '--esal', 'dart_entrypoint_args', f"'--case={args.case}'")
(args.evidence / 'launch.txt').write_text(launch)
process = ''
for _ in range(100):
    query = subprocess.run([*adb, 'shell', 'pidof', 'com.tjzine.lineup'], capture_output=True, text=True)
    if query.returncode not in (0, 1):
        raise RuntimeError('adb_process_query_failed')
    process = query.stdout.strip()
    if process:
        break
    time.sleep(.1)
if not process:
    raise RuntimeError('fixture_process_missing')
start = time.monotonic()
backgrounded = False
resumed = False
facts = []
later = ''
log_lines = []
seen_lines = set()

def accumulate(value):
    for line in value.splitlines():
        if line not in seen_lines:
            seen_lines.add(line)
            log_lines.append(line)
    return '\n'.join(log_lines) + '\n'

captured = set()
while time.monotonic() - start < 150:
    log = accumulate(run('logcat', '-d', '--pid=' + process, '-v', 'threadtime'))
    (args.evidence / 'logcat.txt').write_text(log)
    facts = []
    for line in log.splitlines():
        if 'U3_CONTRACT ' in line:
            facts.append(json.loads(line.split('U3_CONTRACT ', 1)[1]))
    for fact in facts:
        if fact.get('phase') == 'track-subtitle' and fact.get('codec') not in captured:
            captured.add(fact['codec'])
            time.sleep(.6)
            with (args.evidence / ('subtitle-' + fact['codec'] + '.png')).open('wb') as output:
                subprocess.run([*adb, 'exec-out', 'screencap', '-p'], check=True, stdout=output)
    if any(f.get('phase') == 'FAIL' for f in facts):
        break
    if args.case == 'background' and any(f.get('phase') == 'background-ready' for f in facts) and not backgrounded:
        run('shell', 'input', 'keyevent', 'KEYCODE_HOME')
        backgrounded = True
    if backgrounded and not resumed and time.monotonic() - start > 6:
        (args.evidence / 'background-window.txt').write_text(run('shell', 'dumpsys', 'window', 'windows'))
        run('shell', 'am', 'start', '-n', 'com.tjzine.lineup/.MainActivity')
        resumed = True
    if any(f.get('phase') == 'PASS' for f in facts):
        # Retain a later observation: a success followed by rejection is not a pass.
        time.sleep(2)
        later = accumulate(run('logcat', '-d', '--pid=' + process, '-v', 'threadtime'))
        (args.evidence / 'logcat.txt').write_text(later)
        facts = [json.loads(line.split('U3_CONTRACT ', 1)[1]) for line in later.splitlines() if 'U3_CONTRACT ' in line]
        break
    time.sleep(.25)
passed = (any(f.get('phase') == 'PASS' for f in facts)
          and any(f.get('phase') == 'disposed' for f in facts)
          and not any(f.get('phase') == 'FAIL' for f in facts))
if args.case == 'lifetime':
    # Require direct parser/renderer evidence for segment two, not a timeline assumption.
    passed = (passed and 'loadId=1 revision=2 accepted=true' in later
              and 'loadId=2 revision=2 accepted=false' in later
              and any('loadId=1 ptsUs=' in line and int(line.split('ptsUs=')[1].split()[0]) >= 13_000_000
                      for line in later.splitlines() if 'frame_timestamp' in line))
if args.case == 'seek-lifetime':
    import re
    passed = (passed and all(any(int(value) > 0 for value in re.findall(r'fragment_seek .*loadId=' + str(load_id) + r' position=(\d+)', later)) for load_id in (1, 2))
              and 'loadId=1 revision=2 accepted=true' in later and 'loadId=2 revision=2 accepted=false' in later
              and any(int(value) > 61_000_000 for value in re.findall(r'frame_timestamp .*loadId=1 ptsUs=(\d+)', later)))
result = {'case': args.case, 'serial': args.serial, 'pid': process, 'pass': passed, 'facts': facts}
(args.evidence / 'result.json').write_text(json.dumps(result, indent=2))
with (args.evidence / 'screen.png').open('wb') as output:
    subprocess.run([*adb, 'exec-out', 'screencap', '-p'], check=True, stdout=output)
print(json.dumps(result, indent=2))
if not passed:
    raise SystemExit(1)
