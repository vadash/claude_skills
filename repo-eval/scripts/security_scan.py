#!/usr/bin/env python3
"""
Quick security scan for repo evaluation.
Checks for common red flags: hardcoded secrets, dangerous patterns, suspicious scripts.
This is a first-pass heuristic scanner, not a replacement for proper security tooling.
"""

import os
import re
import sys
import json
from pathlib import Path
from collections import defaultdict

# Patterns that suggest hardcoded secrets
SECRET_PATTERNS = [
    (r'(?i)(api[_-]?key|apikey)\s*[:=]\s*["\'][a-zA-Z0-9_\-]{16,}["\']', "Possible API key"),
    (r'(?i)(secret|token|password|passwd|pwd)\s*[:=]\s*["\'][^\s"\']{8,}["\']', "Possible hardcoded secret"),
    (r'(?i)Bearer\s+[a-zA-Z0-9_\-\.]{20,}', "Possible bearer token"),
    (r'AKIA[0-9A-Z]{16}', "AWS access key ID"),
    (r'(?i)-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----', "Private key"),
    (r'ghp_[a-zA-Z0-9]{36}', "GitHub personal access token"),
    (r'sk-[a-zA-Z0-9]{32,}', "Possible OpenAI/Stripe secret key"),
    (r'xox[baprs]-[a-zA-Z0-9\-]{10,}', "Slack token"),
]

# Dangerous code patterns
DANGEROUS_PATTERNS = [
    (r'\beval\s*\(', "eval() usage"),
    (r'\bexec\s*\(', "exec() usage"),
    (r'child_process', "child_process import (Node.js)"),
    (r'subprocess\.call.*shell\s*=\s*True', "subprocess with shell=True"),
    (r'os\.system\s*\(', "os.system() call"),
    (r'__import__\s*\(', "Dynamic import"),
    (r'pickle\.loads?\s*\(', "Pickle deserialization"),
    (r'yaml\.load\s*\([^)]*(?!Loader)', "Unsafe YAML load (no Loader specified)"),
    (r'innerHTML\s*=', "Direct innerHTML assignment (XSS vector)"),
    (r'dangerouslySetInnerHTML', "React dangerouslySetInnerHTML"),
    (r'Function\s*\(', "Function constructor (dynamic code)"),
]

# Suspicious install/build script patterns
SCRIPT_PATTERNS = [
    (r'curl\s+.*\|\s*(bash|sh)', "Pipe curl to shell"),
    (r'wget\s+.*\|\s*(bash|sh)', "Pipe wget to shell"),
    (r'curl\s+.*-o\s+.*&&.*chmod\s+\+x', "Download and execute pattern"),
]

# File extensions to scan (skip binary, media, etc.)
SCAN_EXTENSIONS = {
    '.js', '.ts', '.jsx', '.tsx', '.mjs', '.cjs',
    '.py', '.pyw',
    '.rb', '.erb',
    '.go',
    '.rs',
    '.java', '.kt', '.scala',
    '.php',
    '.sh', '.bash', '.zsh',
    '.yml', '.yaml',
    '.json',
    '.toml',
    '.env', '.env.example', '.env.local',
    '.cfg', '.ini', '.conf',
    '.sql',
    '.md',  # sometimes secrets in docs
    '.dockerfile', '',  # Dockerfile has no extension
}

# Files to skip
SKIP_DIRS = {
    'node_modules', '.git', 'vendor', 'dist', 'build',
    '__pycache__', '.next', '.nuxt', 'coverage',
    '.idea', '.vscode', 'target', 'bin', 'obj',
}

SKIP_FILES = {
    'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml',
    'Cargo.lock', 'poetry.lock', 'Gemfile.lock',
    'composer.lock', 'go.sum',
}


def should_scan(filepath: Path) -> bool:
    """Determine if a file should be scanned."""
    # Skip directories
    for part in filepath.parts:
        if part in SKIP_DIRS:
            return False
    
    # Skip lockfiles
    if filepath.name in SKIP_FILES:
        return False
    
    # Check extension
    suffix = filepath.suffix.lower()
    if suffix in SCAN_EXTENSIONS:
        return True
    
    # Check for extensionless files that might be scripts (Dockerfile, Makefile, etc.)
    if suffix == '' and filepath.name in ('Dockerfile', 'Makefile', 'Rakefile', 'Procfile', 'Vagrantfile'):
        return True
    
    return False


def scan_file(filepath: Path):
    """Scan a single file for security patterns."""
    findings = []
    
    try:
        content = filepath.read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return findings
    
    lines = content.split('\n')
    
    for line_num, line in enumerate(lines, 1):
        # Skip comments (basic heuristic)
        stripped = line.strip()
        if stripped.startswith(('#', '//', '/*', '*', '<!--')):
            # Still check for secrets in comments — that's actually worse
            pass
        
        # Check secret patterns
        for pattern, description in SECRET_PATTERNS:
            if re.search(pattern, line):
                # Skip if it looks like an example/placeholder
                lower_line = line.lower()
                if any(placeholder in lower_line for placeholder in [
                    'example', 'placeholder', 'your_', 'xxx', 'todo',
                    'changeme', 'replace', 'insert', '<your', 'dummy',
                    'test_', 'fake', 'mock', 'sample'
                ]):
                    continue
                findings.append({
                    'type': 'secret',
                    'description': description,
                    'file': str(filepath),
                    'line': line_num,
                    'snippet': stripped[:120],
                })
        
        # Check dangerous patterns
        for pattern, description in DANGEROUS_PATTERNS:
            if re.search(pattern, line):
                findings.append({
                    'type': 'dangerous_pattern',
                    'description': description,
                    'file': str(filepath),
                    'line': line_num,
                    'snippet': stripped[:120],
                })
        
        # Check script patterns
        for pattern, description in SCRIPT_PATTERNS:
            if re.search(pattern, line):
                findings.append({
                    'type': 'script_risk',
                    'description': description,
                    'file': str(filepath),
                    'line': line_num,
                    'snippet': stripped[:120],
                })
    
    return findings


def check_install_scripts(repo_path: Path):
    """Check for postinstall and similar lifecycle scripts."""
    findings = []
    
    pkg_json = repo_path / 'package.json'
    if pkg_json.exists():
        try:
            pkg = json.loads(pkg_json.read_text())
            scripts = pkg.get('scripts', {})
            suspicious_hooks = ['preinstall', 'postinstall', 'preuninstall', 'postuninstall']
            for hook in suspicious_hooks:
                if hook in scripts:
                    findings.append({
                        'type': 'lifecycle_script',
                        'description': f'{hook} script in package.json',
                        'file': 'package.json',
                        'line': 0,
                        'snippet': f'{hook}: {scripts[hook][:120]}',
                    })
        except Exception:
            pass
    
    return findings


def scan_repo(repo_path: str):
    """Full repo scan."""
    repo = Path(repo_path)
    if not repo.exists():
        print(json.dumps({'error': f'Path does not exist: {repo_path}'}))
        sys.exit(1)
    
    all_findings = []
    files_scanned = 0
    
    # Scan all eligible files
    for filepath in repo.rglob('*'):
        if filepath.is_file() and should_scan(filepath):
            findings = scan_file(filepath)
            all_findings.extend(findings)
            files_scanned += 1
    
    # Check install scripts
    all_findings.extend(check_install_scripts(repo))
    
    # Check for .env files that aren't examples
    for env_file in repo.rglob('.env'):
        if env_file.is_file() and '.example' not in env_file.name:
            all_findings.append({
                'type': 'secret',
                'description': '.env file committed to repo',
                'file': str(env_file),
                'line': 0,
                'snippet': '(entire file)',
            })
    
    # Summarize
    summary = {
        'files_scanned': files_scanned,
        'total_findings': len(all_findings),
        'by_type': defaultdict(int),
        'findings': all_findings,
    }
    
    for f in all_findings:
        summary['by_type'][f['type']] += 1
    
    summary['by_type'] = dict(summary['by_type'])
    
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <repo-path>")
        sys.exit(1)
    scan_repo(sys.argv[1])
