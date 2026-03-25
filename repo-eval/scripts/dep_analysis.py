#!/usr/bin/env python3
"""
Dependency analysis for repo evaluation.
Extracts dependency info from common package manifest files and reports on
counts, pinning strategy, and license information where available.
"""

import os
import sys
import json
import re
from pathlib import Path
from collections import defaultdict


def analyze_package_json(repo_path: Path):
    """Analyze Node.js package.json dependencies."""
    pkg_file = repo_path / 'package.json'
    if not pkg_file.exists():
        return None
    
    try:
        pkg = json.loads(pkg_file.read_text())
    except Exception as e:
        return {'error': f'Failed to parse package.json: {e}'}
    
    deps = pkg.get('dependencies', {})
    dev_deps = pkg.get('devDependencies', {})
    peer_deps = pkg.get('peerDependencies', {})
    
    def classify_version(version):
        if version.startswith('^'):
            return 'caret (minor float)'
        elif version.startswith('~'):
            return 'tilde (patch float)'
        elif version == '*' or version == 'latest':
            return 'wildcard (DANGEROUS)'
        elif re.match(r'^\d+\.\d+\.\d+$', version):
            return 'pinned'
        elif 'git' in version or 'github' in version:
            return 'git reference'
        elif version.startswith('file:'):
            return 'local file'
        else:
            return 'range/other'
    
    pinning = defaultdict(int)
    for v in list(deps.values()) + list(dev_deps.values()):
        pinning[classify_version(v)] += 1
    
    # Check for lockfile
    has_lockfile = any((repo_path / lf).exists() for lf in [
        'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb'
    ])
    
    lockfile_type = None
    for lf in ['package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb']:
        if (repo_path / lf).exists():
            lockfile_type = lf
            break
    
    # Count transitive deps from lockfile
    transitive_count = None
    if (repo_path / 'package-lock.json').exists():
        try:
            lock = json.loads((repo_path / 'package-lock.json').read_text())
            if 'packages' in lock:
                transitive_count = len([k for k in lock['packages'] if k != ''])
            elif 'dependencies' in lock:
                transitive_count = len(lock['dependencies'])
        except Exception:
            pass
    
    return {
        'ecosystem': 'node',
        'manifest': 'package.json',
        'project_license': pkg.get('license', 'Not specified'),
        'direct_dependencies': len(deps),
        'dev_dependencies': len(dev_deps),
        'peer_dependencies': len(peer_deps),
        'transitive_dependencies': transitive_count,
        'pinning_strategy': dict(pinning),
        'has_lockfile': has_lockfile,
        'lockfile_type': lockfile_type,
        'engines': pkg.get('engines', None),
        'dependency_list': {name: ver for name, ver in deps.items()},
    }


def analyze_pyproject(repo_path: Path):
    """Analyze Python pyproject.toml or requirements.txt."""
    results = {
        'ecosystem': 'python',
        'manifest': None,
        'direct_dependencies': 0,
        'dev_dependencies': 0,
        'pinning_strategy': defaultdict(int),
        'has_lockfile': False,
        'dependency_list': {},
    }
    
    # Check for requirements.txt
    req_file = repo_path / 'requirements.txt'
    if req_file.exists():
        results['manifest'] = 'requirements.txt'
        try:
            lines = req_file.read_text().strip().split('\n')
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('-'):
                    continue
                if '==' in line:
                    results['pinning_strategy']['pinned'] += 1
                elif '>=' in line or '<=' in line:
                    results['pinning_strategy']['range'] += 1
                else:
                    results['pinning_strategy']['unpinned'] += 1
                results['direct_dependencies'] += 1
                name = re.split(r'[><=!~\[]', line)[0].strip()
                results['dependency_list'][name] = line.replace(name, '').strip()
        except Exception:
            pass
    
    # Check for pyproject.toml
    pyproject = repo_path / 'pyproject.toml'
    if pyproject.exists():
        results['manifest'] = 'pyproject.toml'
        try:
            content = pyproject.read_text()
            # Basic TOML parsing for dependencies (not a full parser)
            in_deps = False
            in_dev_deps = False
            for line in content.split('\n'):
                stripped = line.strip()
                if stripped == '[project]' or stripped == '[tool.poetry.dependencies]':
                    in_deps = True
                    in_dev_deps = False
                    continue
                elif 'dev' in stripped.lower() and stripped.startswith('['):
                    in_dev_deps = True
                    in_deps = False
                    continue
                elif stripped.startswith('['):
                    in_deps = False
                    in_dev_deps = False
                    continue
                
                if stripped.startswith('dependencies') and '=' in stripped:
                    # Inline dependencies list
                    in_deps = True
        except Exception:
            pass
    
    # Check for lockfiles
    for lf in ['poetry.lock', 'Pipfile.lock', 'pdm.lock', 'uv.lock']:
        if (repo_path / lf).exists():
            results['has_lockfile'] = True
            results['lockfile_type'] = lf
            break
    
    # Check for setup.py as fallback
    if results['manifest'] is None and (repo_path / 'setup.py').exists():
        results['manifest'] = 'setup.py'
    
    results['pinning_strategy'] = dict(results['pinning_strategy'])
    
    if results['manifest'] is None:
        return None
    return results


def analyze_cargo(repo_path: Path):
    """Analyze Rust Cargo.toml."""
    cargo_file = repo_path / 'Cargo.toml'
    if not cargo_file.exists():
        return None
    
    results = {
        'ecosystem': 'rust',
        'manifest': 'Cargo.toml',
        'direct_dependencies': 0,
        'dev_dependencies': 0,
        'build_dependencies': 0,
        'has_lockfile': (repo_path / 'Cargo.lock').exists(),
        'dependency_list': {},
    }
    
    try:
        content = cargo_file.read_text()
        section = None
        for line in content.split('\n'):
            stripped = line.strip()
            if stripped == '[dependencies]':
                section = 'deps'
            elif stripped == '[dev-dependencies]':
                section = 'dev'
            elif stripped == '[build-dependencies]':
                section = 'build'
            elif stripped.startswith('['):
                if stripped.startswith('[dependencies.'):
                    results['direct_dependencies'] += 1
                    dep_name = stripped[14:-1]
                    results['dependency_list'][dep_name] = '(table format)'
                section = None
            elif '=' in stripped and section:
                name = stripped.split('=')[0].strip()
                ver = stripped.split('=', 1)[1].strip().strip('"').strip("'")
                if section == 'deps':
                    results['direct_dependencies'] += 1
                    results['dependency_list'][name] = ver
                elif section == 'dev':
                    results['dev_dependencies'] += 1
                elif section == 'build':
                    results['build_dependencies'] += 1
    except Exception:
        pass
    
    return results


def analyze_go_mod(repo_path: Path):
    """Analyze Go go.mod."""
    go_mod = repo_path / 'go.mod'
    if not go_mod.exists():
        return None
    
    results = {
        'ecosystem': 'go',
        'manifest': 'go.mod',
        'direct_dependencies': 0,
        'indirect_dependencies': 0,
        'has_lockfile': (repo_path / 'go.sum').exists(),
        'go_version': None,
        'dependency_list': {},
    }
    
    try:
        content = go_mod.read_text()
        in_require = False
        for line in content.split('\n'):
            stripped = line.strip()
            if stripped.startswith('go '):
                results['go_version'] = stripped.split()[1]
            elif stripped == 'require (':
                in_require = True
            elif stripped == ')':
                in_require = False
            elif in_require and stripped:
                parts = stripped.split()
                if len(parts) >= 2:
                    if '// indirect' in stripped:
                        results['indirect_dependencies'] += 1
                    else:
                        results['direct_dependencies'] += 1
                        results['dependency_list'][parts[0]] = parts[1]
    except Exception:
        pass
    
    return results


def find_license(repo_path: Path):
    """Find and identify the project license."""
    license_files = ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENCE', 'COPYING']
    
    for lf in license_files:
        filepath = repo_path / lf
        if filepath.exists():
            try:
                content = filepath.read_text()[:2000].lower()
                if 'mit license' in content or 'permission is hereby granted, free of charge' in content:
                    return 'MIT'
                elif 'apache license' in content and 'version 2.0' in content:
                    return 'Apache-2.0'
                elif 'gnu general public license' in content:
                    if 'version 3' in content:
                        return 'GPL-3.0'
                    elif 'version 2' in content:
                        return 'GPL-2.0'
                    return 'GPL (version unclear)'
                elif 'bsd' in content:
                    if '3-clause' in content or 'neither the name' in content:
                        return 'BSD-3-Clause'
                    elif '2-clause' in content:
                        return 'BSD-2-Clause'
                    return 'BSD (variant unclear)'
                elif 'isc license' in content:
                    return 'ISC'
                elif 'unlicense' in content or 'public domain' in content:
                    return 'Unlicense/Public Domain'
                elif 'mozilla public license' in content:
                    return 'MPL-2.0'
                else:
                    return f'Custom/Unrecognized (see {lf})'
            except Exception:
                return f'Present but unreadable ({lf})'
    
    return 'No license file found'


def analyze_repo(repo_path: str):
    """Run all dependency analyses."""
    repo = Path(repo_path)
    if not repo.exists():
        print(json.dumps({'error': f'Path does not exist: {repo_path}'}))
        sys.exit(1)
    
    results = {
        'license': find_license(repo),
        'ecosystems': [],
    }
    
    # Try all ecosystem analyzers
    analyzers = [
        analyze_package_json,
        analyze_pyproject,
        analyze_cargo,
        analyze_go_mod,
    ]
    
    for analyzer in analyzers:
        result = analyzer(repo)
        if result:
            results['ecosystems'].append(result)
    
    if not results['ecosystems']:
        results['note'] = 'No recognized package manifest found. This may be a language/ecosystem not covered by this scanner, or a project without managed dependencies.'
    
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <repo-path>")
        sys.exit(1)
    analyze_repo(sys.argv[1])
