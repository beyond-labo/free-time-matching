import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / 'scripts/okf.py'
spec = importlib.util.spec_from_file_location('okf', MODULE)
okf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(okf)

class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.feature = self.root / '.kiro/specs/demo'
        self.feature.mkdir(parents=True)
        self.doc = self.feature / 'requirements.md'
        self.doc.write_text('---\ntype: requirements\nstatus: draft\n---\n# 要件\n')
        self.state = self.feature / 'spec.json'
        self.state.write_text(json.dumps({'approvals': {'requirements': {'approved': False, 'generated': True}}, 'ready_for_implementation': False}))

    def runcli(self, command, *flags):
        out = io.StringIO()
        with contextlib.redirect_stdout(out): code = okf.main([command, '--root', str(self.root), *flags])
        return code, json.loads(out.getvalue())

    def snapshot(self): self.assertEqual(self.runcli('snapshot', '--reviewed')[0], 0)

    def test_check_readonly_and_unchecked(self):
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        code, result = self.runcli('check')
        self.assertEqual(code, 0)
        self.assertEqual(result['issues'][0]['code'], 'UNCHECKED')
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_snapshot_requires_review_and_preserves_state(self):
        self.assertEqual(self.runcli('snapshot')[0], 2)
        before = json.loads(self.state.read_text())
        self.snapshot()
        after = json.loads(self.state.read_text())
        self.assertEqual(after.pop('freshness').keys(), {'checked_inputs'})
        self.assertEqual(before, after)
        self.assertEqual(self.runcli('check')[0], 0)

    def test_transitive_changed_and_new_dependency(self):
        shared = self.root / '.kiro/steering'
        shared.mkdir()
        (shared / 'tech.md').write_text('---\ntype: policy\nsources:\n  - resource: extra.txt\n---\nPolicy\n')
        (shared / 'extra.txt').write_text('old')
        self.doc.write_text('---\ntype: requirements\nkiro:\n  depends_on: [.kiro/steering/tech.md]\n---\n# 要件\n')
        self.snapshot()
        (shared / 'extra.txt').write_text('new')
        code, data = self.runcli('check')
        self.assertEqual(code, 1)
        self.assertIn('NEEDS_REVIEW', str(data))
        self.snapshot()
        (shared / 'another.txt').write_text('new dependency')
        (shared / 'tech.md').write_text('---\ntype: policy\nsources:\n  - resource: another.txt\n---\nPolicy\n')
        self.assertEqual(self.runcli('check')[0], 1)

    def test_typo_detected_without_approval_mutation(self):
        self.snapshot()
        state = self.state.read_bytes()
        self.doc.write_text(self.doc.read_text() + 'typo fix\n')
        self.assertEqual(self.runcli('check')[0], 1)
        self.assertEqual(state, self.state.read_bytes())

    def test_bad_types_and_duplicate_keys(self):
        for yaml in ['type: []', 'type: x\ntype: y', 'type: x\nsources: x', 'type: x\nkiro: []', 'type: x\nstatus: []']:
            with self.subTest(yaml=yaml):
                self.doc.write_text('---\n' + yaml + '\n---\n')
                self.assertEqual(self.runcli('check')[0], 1)

    def test_escape_and_symlink(self):
        self.doc.write_text('---\ntype: x\nkiro:\n  depends_on: [../escape]\n---\n')
        self.assertEqual(self.runcli('check')[0], 1)
        self.assertEqual(self.runcli('check', '--feature', 'demo')[0], 1)
        self.doc.write_text('---\ntype: x\n---\n[link](unsafe)\n')
        (self.feature / 'unsafe').symlink_to('/etc/passwd')
        self.assertEqual(self.runcli('check')[0], 1)
        self.assertEqual(self.runcli('check', '--feature', '../escape')[0], 2)

    def test_fenced_examples_ignored(self):
        self.doc.write_text(self.doc.read_text() + '\n```md\n[not real](missing.md)\n```\n')
        self.assertEqual(self.runcli('check')[0], 0)

    def test_index_deterministic_and_feature_scoped(self):
        self.assertEqual(self.runcli('index', '--feature', 'demo')[0], 0)
        before = (self.feature / 'index.md').read_bytes()
        self.assertEqual(self.runcli('index', '--feature', 'demo')[0], 0)
        self.assertEqual(before, (self.feature / 'index.md').read_bytes())
        self.assertFalse((self.feature.parent / 'index.md').exists())
        self.assertNotIn('spec.json', before.decode())
        self.assertEqual(self.runcli('index')[0], 0)
        self.assertIn('okf_version: "0.2"', (self.feature.parent / 'index.md').read_text())

    def test_feature_ignores_unrelated_legacy_spec(self):
        other = self.feature.parent / 'other'
        other.mkdir()
        (other / 'requirements.md').write_text('# Legacy\n')
        self.assertEqual(self.runcli('check')[0], 1)
        self.assertEqual(self.runcli('check', '--feature', 'demo')[0], 0)

    def test_empty_repository_reports_zero_documents(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(okf.main(['check', '--root', temporary]), 0)
            result = json.loads(out.getvalue())
            self.assertEqual(result['scanned_documents'], 0)
            self.assertEqual(result['scanned_specs'], 0)

    def test_index_escapes_titles_and_paths(self):
        special = self.feature / 'notes (v1).md'
        special.write_text('---\ntype: Note\ntitle: "予約 [v1]"\n---\nBody\n')
        self.assertEqual(self.runcli('index')[0], 0)
        index = (self.feature / 'index.md').read_text()
        self.assertIn('notes%20%28v1%29.md', index)
        self.assertIn(r'予約 \[v1\]', index)
        self.assertEqual(self.runcli('check')[0], 0)
        code, result = self.runcli('check', '--feature', 'demo')
        self.assertEqual(code, 0)
        self.assertIn('all bundle', result['document_count_scope'])

    def test_index_recovers_deleted_reference(self):
        (self.feature / 'index.md').write_text('# Old\n[deleted](gone.md)\n')
        self.assertEqual(self.runcli('check')[0], 1)
        self.assertEqual(self.runcli('index')[0], 0)
        self.assertEqual(self.runcli('check')[0], 0)

    def test_brief_only_check_and_index(self):
        self.state.unlink()
        self.doc.rename(self.feature / 'brief.md')
        self.assertEqual(self.runcli('check', '--feature', 'demo')[0], 0)
        self.assertEqual(self.runcli('index', '--feature', 'demo')[0], 0)
        self.assertEqual(self.runcli('snapshot', '--reviewed', '--feature', 'demo')[0], 1)

    def test_generated_and_freshness_validation(self):
        data = json.loads(self.state.read_text())
        data['approvals']['design'] = {'generated': True, 'approved': False}
        self.state.write_text(json.dumps(data))
        self.assertEqual(self.runcli('check')[0], 1)
        del data['approvals']['design']
        for freshness in [{'status': 'bogus'}, {'pending': [42]}, {'pending': [{'path': '../x', 'reason': 'x'}]}]:
            data['freshness'] = freshness
            self.state.write_text(json.dumps(data))
            self.assertEqual(self.runcli('check')[0], 1)

    def test_control_hashes_excluded_and_footnotes_allowed(self):
        self.doc.write_text('---\ntype: x\nkiro:\n  depends_on: [.kiro/specs/demo/spec.json]\n---\nText[^source]\n\n[^source]: Plain description\n[dir](./)\n')
        self.snapshot()
        self.assertEqual(self.runcli('check')[0], 0)
        self.assertNotIn('.kiro/specs/demo/spec.json', json.loads(self.state.read_text())['freshness']['checked_inputs'])

    def test_unresolved_frontmatter_placeholder(self):
        self.doc.write_text('---\ntype: x\ntitle: "{{TITLE}}"\n---\n')
        self.assertEqual(self.runcli('check')[0], 1)

    def test_ready_requires_current_hashes(self):
        data = json.loads(self.state.read_text())
        data['ready_for_implementation'] = True
        self.state.write_text(json.dumps(data))
        self.assertEqual(self.runcli('check')[0], 1)

    def test_broken_source_refuses_snapshot(self):
        self.doc.write_text('---\ntype: x\nsources:\n  - resource: absent.md\n---\n')
        self.assertEqual(self.runcli('snapshot', '--reviewed')[0], 1)

if __name__ == '__main__': unittest.main()
