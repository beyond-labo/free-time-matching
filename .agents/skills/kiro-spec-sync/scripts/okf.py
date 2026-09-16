#!/usr/bin/env python3
"""Local OKF 0.2 structure/freshness checks. Does not establish meaning or approval."""
import argparse
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote, unquote

try:
    import yaml
except ImportError:
    requirements = Path(__file__).with_name('requirements.txt')
    print('PyYAML が必要です。依存導入: python3 -m pip install -r "' + str(requirements) + '"', file=sys.stderr)
    sys.exit(2)

class UniqueLoader(yaml.SafeLoader):
    pass

def mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, (str, int, float, bool, type(None))) or key in result:
            raise ValueError('duplicate or unsupported YAML key')
        result[key] = loader.construct_object(value_node, deep=deep)
    return result

UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)

class Audit:
    def __init__(self, root, feature=None, command="check"):
        self.root = root.resolve()
        self.feature = feature
        self.command = command
        self.issues = []
        self.docs = {}
        self.scanned_documents = 0
        self.edges = {}
        self.specs = {}
        self.external = set()

    def issue(self, code, path, message, severity='error'):
        try: path = str(path.relative_to(self.root))
        except ValueError: path = str(path)
        self.issues.append(dict(code=code, path=path, message=message, severity=severity))

    def safe(self, path, exists=True):
        try:
            path.relative_to(self.root)
            resolved = path.resolve()
            resolved.relative_to(self.root)
            if any(p.is_symlink() for p in [path, *path.parents] if p != self.root.parent):
                raise ValueError('symlink is not allowed')
            if exists and not path.is_file(): raise ValueError('file does not exist')
            return path
        except (ValueError, OSError) as exc:
            self.issue('UNSAFE_OR_MISSING_PATH', path, str(exc))
            return None

    def reference(self, doc, value, bundle, dependency=False, track=True):
        if not isinstance(value, str) or not value:
            self.issue('INVALID_REFERENCE', doc, 'reference must be a nonempty string'); return
        if re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', value):
            if dependency:
                self.issue('INVALID_DEPENDENCY', doc, 'depends_on requires repository-relative files')
            else: self.external.add(value)
            return
        value = unquote(value.split('#', 1)[0].split('?', 1)[0])
        if not value: return
        if dependency and value.startswith('/'):
            self.issue('INVALID_DEPENDENCY', doc, 'depends_on must be repository-relative'); return
        path = (self.root / value if dependency else bundle / value.lstrip('/') if value.startswith('/') else doc.parent / value)
        path = Path(__import__('os').path.abspath(path))
        if not track and path.is_dir():
            self.safe(path, exists=False)
            return
        if self.safe(path):
            if track: self.edges.setdefault(doc, set()).add(path)
        else: self.issue('INVALID_REFERENCE', doc, 'unsafe or missing reference: ' + value)

    def read_doc(self, path, bundle):
        self.scanned_documents += 1
        if not self.safe(path): return
        text = path.read_text(encoding='utf-8')
        meta, body = None, text
        if text.startswith('---\n'):
            parts = text.split('\n---', 1)
            if len(parts) == 2:
                try:
                    if re.search(r'\{\{[^}]+\}\}', parts[0][4:]): self.issue('UNRESOLVED_PLACEHOLDER', path, 'frontmatter contains an unresolved template placeholder')
                    meta = yaml.load(parts[0][4:], Loader=UniqueLoader); body = parts[1]
                except Exception as exc: self.issue('INVALID_YAML', path, str(exc)); return
            else: self.issue('INVALID_YAML', path, 'missing closing frontmatter delimiter'); return
        reserved = path.name in ('index.md', 'log.md')
        if path.name == 'index.md':
            if path.parent == bundle:
                if not isinstance(meta, dict) or set(meta) != {'okf_version'} or str(meta.get('okf_version')) != '0.2':
                    self.issue('INVALID_INDEX', path, 'root index requires okf_version: "0.2"')
            elif meta is not None: self.issue('INVALID_INDEX', path, 'subdirectory index has no frontmatter')
        elif path.name == 'log.md':
            if meta is not None: self.issue('INVALID_LOG', path, 'log has no frontmatter')
            dates = re.findall(r'^##\s+(\S+)', body, re.M)
            if dates != sorted(dates, reverse=True): self.issue('INVALID_LOG', path, 'log dates must be newest first')
            for date in dates:
                try: datetime.date.fromisoformat(date)
                except ValueError: self.issue('INVALID_LOG', path, 'log headings require YYYY-MM-DD')
        else:
            if not isinstance(meta, dict): self.issue('MISSING_METADATA', path, 'concept requires YAML mapping'); return
            if not isinstance(meta.get('type'), str) or not meta['type'].strip(): self.issue('INVALID_TYPE', path, 'type must be nonempty string')
            for field in ('title', 'description'):
                if field in meta and not isinstance(meta[field], str): self.issue('INVALID_METADATA', path, field + ' must be string')
            if meta.get('status', 'stable') not in ('draft', 'stable', 'deprecated'): self.issue('INVALID_STATUS', path, 'unknown status')
            sources = meta.get('sources', [])
            if not isinstance(sources, list): self.issue('INVALID_SOURCES', path, 'sources must be list')
            else:
                for source in sources:
                    if not isinstance(source, dict) or 'resource' not in source: self.issue('INVALID_SOURCES', path, 'source requires resource')
                    else: self.reference(path, source['resource'], bundle)
            kiro = meta.get('kiro', {})
            if not isinstance(kiro, dict): self.issue('INVALID_KIRO', path, 'kiro must be mapping')
            else:
                deps = kiro.get('depends_on', [])
                if not isinstance(deps, list): self.issue('INVALID_DEPENDENCY', path, 'depends_on must be list')
                else:
                    for dep in deps: self.reference(path, dep, bundle, True)
        self.docs[path] = meta or {}
        # A small Markdown scanner: remove fenced/inline code and inspect inline and reference links.
        body = re.sub(r'^\s*(`{3,}|~{3,}).*?^\s*\1\s*$', '', body, flags=re.M | re.S)
        body = re.sub(r'`[^`\n]*`', '', body)
        links = re.findall(r'!?\[(?:\\.|[^\]\\])*\]\(\s*<?([^\s)>]+)>?(?:\s+[^)]*)?\)', body)
        links += re.findall(r'^\s*\[(?!\^)[^\]]+\]:\s*<?([^\s>]+)>?', body, re.M)
        for link in links: self.reference(path, link, bundle, track=False)

    def scan(self):
        bundles = [self.root / '.kiro/specs', self.root / '.kiro/steering']
        for bundle in bundles:
            if not bundle.exists(): continue
            for path in sorted(bundle.rglob('*')):
                if path.is_symlink(): self.issue('UNSAFE_OR_MISSING_PATH', path, 'symlink is not allowed'); continue
                if path.is_file() and path.suffix == '.md':
                    if self.command == 'index' and path.name == 'index.md': continue
                    self.read_doc(path, bundle)
        specs_dir = self.root / '.kiro/specs'
        if specs_dir.exists():
            for path in sorted(specs_dir.glob('*/spec.json')):
                if self.feature and path.parent.name != self.feature: continue
                if not self.safe(path): continue
                try:
                    spec = json.loads(path.read_text())
                    if not isinstance(spec, dict): raise ValueError('spec must be object')
                    self.specs[path] = spec
                except (ValueError, OSError) as exc: self.issue('INVALID_SPEC', path, str(exc))
        if self.feature:
            scope = specs_dir / self.feature
            relevant = {p for p in self.docs if p.is_relative_to(scope)}
            relevant.update(scope.rglob('*.md'))
            relevant.add(scope / 'spec.json')
            todo = list(relevant)
            while todo:
                for dep in self.edges.get(todo.pop(), set()):
                    if dep not in relevant: relevant.add(dep); todo.append(dep)
            self.issues = [i for i in self.issues if self.root / i['path'] in relevant]
            if self.command == 'snapshot' and not self.specs: self.issue('MISSING_SPEC', scope, 'snapshot requires valid spec.json')
            elif not scope.is_dir(): self.issue('MISSING_FEATURE', scope, 'feature directory does not exist')
        return self

    def inputs(self, directory):
        initial = {p for p in self.docs if p.is_relative_to(directory) and p.name not in ('index.md', 'log.md')}
        seen, todo = set(), list(initial)
        while todo:
            path = todo.pop()
            if path in seen or path.name in ('index.md', 'log.md', 'spec.json'): continue
            seen.add(path)
            todo.extend(self.edges.get(path, set()) - seen)
        return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen) if p.is_file()}

    def states(self, freshness=True):
        for path, spec in self.specs.items():
            approvals = spec.get('approvals', {})
            if not isinstance(approvals, dict): self.issue('INVALID_APPROVALS', path, 'approvals must be object'); continue
            previous = True
            all_ready = True
            for stage, name in [('requirements', 'requirements.md'), ('design', 'design.md'), ('tasks', 'tasks.md')]:
                state = approvals.get(stage, {})
                if not isinstance(state, dict): self.issue('INVALID_APPROVALS', path, stage + ' must be object'); all_ready = False; continue
                approved, generated = state.get('approved', False), state.get('generated', False)
                if not isinstance(approved, bool) or not isinstance(generated, bool): self.issue('INVALID_APPROVALS', path, stage + ' flags must be boolean')
                if generated is True and not (path.parent / name).is_file(): self.issue('INVALID_APPROVALS', path, stage + ' generated artifact is missing')
                if approved is True and (generated is not True or not (path.parent / name).is_file() or not previous): self.issue('INVALID_APPROVALS', path, stage + ' approved without generated artifact or upstream approval')
                previous = approved is True
                all_ready = all_ready and approved is True and generated is True and (path.parent / name).is_file()
            ready = spec.get('ready_for_implementation', False)
            if not isinstance(ready, bool): self.issue('INVALID_READY', path, 'ready flag must be boolean')
            if ready is True and not all_ready: self.issue('INVALID_READY', path, 'ready requires all generated and approved artifacts')
            fresh = spec.get('freshness', {})
            if not isinstance(fresh, dict): self.issue('INVALID_FRESHNESS', path, 'freshness must be object'); continue
            if fresh.get('status', 'unchecked') not in ('unchecked', 'needs-sync', 'current'): self.issue('INVALID_FRESHNESS', path, 'invalid freshness status')
            pending = fresh.get('pending', [])
            if not isinstance(pending, list): self.issue('INVALID_FRESHNESS', path, 'pending must be list')
            else:
                for item in pending:
                    if not isinstance(item, dict) or any(not isinstance(item.get(k), str) or not item[k].strip() for k in ('path', 'reason')):
                        self.issue('INVALID_FRESHNESS', path, 'pending items require path and reason strings')
                    elif item['path'].startswith('/') or '..' in Path(item['path']).parts:
                        self.issue('INVALID_FRESHNESS', path, 'pending paths must stay repository-relative')
            if fresh.get('status') == 'current' and pending: self.issue('INVALID_FRESHNESS', path, 'current has pending items')
            if ready is True and (pending or fresh.get('status') != 'current'): self.issue('INVALID_READY', path, 'ready requires current freshness with no pending items')
            old = fresh.get('checked_inputs')
            if old is not None and (not isinstance(old, dict) or any(not isinstance(k, str) or not isinstance(v, str) or not re.fullmatch(r'[a-f0-9]{64}', v) for k, v in old.items())):
                self.issue('INVALID_FRESHNESS', path, 'checked_inputs must map paths to SHA256'); continue
            if old is not None:
                for key in old:
                    candidate = self.root / key
                    if key.startswith('/') or '..' in Path(key).parts: self.issue('INVALID_FRESHNESS', path, 'input path must stay repository-relative')
                    elif candidate.exists(): self.safe(candidate)
            if not freshness: continue
            if not old: self.issue('UNCHECKED', path, 'no reviewed input hashes', 'error' if ready is True else 'warning')
            elif old != self.inputs(path.parent): self.issue('NEEDS_REVIEW', path, 'reviewed inputs changed, were deleted, or new dependencies appeared')

    def result(self):
        return dict(scanned_documents=self.scanned_documents, scanned_specs=len(self.specs), document_count_scope='all bundle documents scanned, including unrelated features' if self.feature else 'all bundle documents', issues=self.issues, external_unverified=sorted(self.external), assurance='構造とローカル入力の変更のみを検査します。意味の整合性、外部資料の鮮度、承認を保証しません。')


def escape_label(value):
    return value.replace('\\', '\\\\').replace('[', '\\[').replace(']', '\\]').replace('\n', ' ')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'snapshot', 'index'])
    parser.add_argument('--root', required=True)
    parser.add_argument('--feature')
    parser.add_argument('--reviewed', action='store_true')
    args = parser.parse_args(argv)
    try:
        root = Path(args.root)
        if not root.is_dir() or root.is_symlink(): raise ValueError('root must be an existing non-symlink directory')
        if args.feature and (args.feature in ('.', '..') or '/' in args.feature or '\\' in args.feature): raise ValueError('invalid feature name')
        if args.command == 'snapshot' and not args.reviewed: raise ValueError('snapshot requires --reviewed after semantic review')
        audit = Audit(root, args.feature, args.command).scan()
        audit.states(freshness=args.command == 'check')
        if any(i['severity'] == 'error' for i in audit.issues):
            print(json.dumps(audit.result(), ensure_ascii=False, indent=2)); return 1
        if args.command == 'snapshot':
            for path, spec in audit.specs.items():
                spec.setdefault('freshness', {})['checked_inputs'] = audit.inputs(path.parent)
                path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + '\n')
        elif args.command == 'index':
            for bundle in [audit.root / '.kiro/specs', audit.root / '.kiro/steering']:
                if not bundle.exists() or (args.feature and bundle.name == 'steering'): continue
                scope = bundle / args.feature if args.feature else bundle
                directories = {p.parent for p in audit.docs if p.is_relative_to(scope)}
                directories.add(scope)
                for directory in list(directories):
                    directories.update(parent for parent in directory.parents if parent.is_relative_to(scope))
                for directory in sorted(directories):
                    target = directory / 'index.md'
                    if not audit.safe(target, exists=False): continue
                    lines = ['---', 'okf_version: "0.2"', '---', ''] if directory == bundle else []
                    lines += ['# 文書一覧', '']
                    for child in sorted(directory.iterdir()):
                        if child.is_dir() and any(p.is_relative_to(child) for p in audit.docs): lines.append(f'- [{escape_label(child.name)}]({quote(child.name, safe="")}/index.md)')
                        elif child in audit.docs and child.name != 'index.md':
                            label = audit.docs[child].get('title', child.stem)
                            description = str(audit.docs[child].get('description', '')).replace(chr(10), ' ')
                            lines.append(f'- [{escape_label(str(label))}]({quote(child.name, safe="")})' + (f' — {description}' if description else ''))
                    target.write_text('\n'.join(lines) + '\n')
        print(json.dumps(audit.result(), ensure_ascii=False, indent=2))
        return 1 if any(i['severity'] == 'error' for i in audit.issues) else 0
    except (ValueError, OSError, UnicodeError) as exc:
        print(json.dumps({'error': str(exc)}, ensure_ascii=False)); return 2

if __name__ == '__main__': sys.exit(main())
