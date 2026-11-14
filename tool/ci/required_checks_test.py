import copy
import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('checks', Path(__file__).with_name('required-checks.py'))
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


class RequiredChecksTest(unittest.TestCase):
    def needs(self, engine='false', package='false'):
        result = {job: {'result': 'success'} for job in checks.UNCONDITIONAL}
        result['release-inputs']['outputs'] = {
            'engine-required': engine, 'package-required': package,
        }
        result['windows-engine-tests'] = {
            'result': 'success' if engine == 'true' else 'skipped',
        }
        result['build-windows-engine'] = {
            'result': 'success' if 'true' in (engine, package) else 'skipped',
        }
        return result

    def test_success_and_justified_skips(self):
        for engine in ('true', 'false'):
            for package in ('true', 'false'):
                with self.subTest(engine=engine, package=package):
                    self.assertEqual([], checks.failures(self.needs(engine, package)))

    def test_failed_cancelled_and_unexpected_skipped_jobs(self):
        for engine in ('true', 'false'):
            for package in ('true', 'false'):
                baseline = self.needs(engine, package)
                for job in baseline:
                    for conclusion in ('failure', 'cancelled', 'skipped'):
                        if conclusion == baseline[job]['result']:
                            continue
                        needs = copy.deepcopy(baseline)
                        needs[job]['result'] = conclusion
                        with self.subTest(job=job, conclusion=conclusion):
                            self.assertTrue(checks.failures(needs))

    def test_missing_or_invalid_decision_and_inventory(self):
        for value in (None, '', 'False', 'unexpected'):
            needs = self.needs()
            needs['release-inputs']['outputs']['engine-required'] = value
            self.assertTrue(checks.failures(needs))
        needs = self.needs()
        del needs['android']
        self.assertTrue(checks.failures(needs))

    def test_workflow_job_inventory_and_always_execution(self):
        workflow = (ROOT / '.github/workflows/ci.yml').read_text()
        jobs = set(re.findall(r'^  ([a-z][a-z0-9-]+):$', workflow, re.MULTILINE))
        # Top-level event/concurrency maps also use two-space indentation.
        jobs -= {'push', 'pull_request', 'workflow_dispatch'}
        self.assertEqual(set(checks.UNCONDITIONAL + checks.CONDITIONAL + ('required-checks',)), jobs)
        aggregate = workflow.split('\n  required-checks:\n')[1]
        self.assertIn('if: always()', aggregate)
        self.assertIn('CI_NEEDS: ${{ toJSON(needs) }}', aggregate)
        dependencies = set(re.findall(r'^      - ([a-z][a-z0-9-]+)$',
                                      aggregate, re.MULTILINE))
        self.assertEqual(set(checks.UNCONDITIONAL + checks.CONDITIONAL), dependencies)


if __name__ == '__main__':
    unittest.main()
