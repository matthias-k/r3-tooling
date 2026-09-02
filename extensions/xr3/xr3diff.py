"""The xr3 diff engine — compares two job directories (file/config/metadata diffs,
stat/name-only/structured/interactive rendering, pager). Pathmap-independent: takes
resolved paths and does the diffing. The `diff` command wiring lives in `xr3` and
resolves the default target via pathmap before calling in here.
"""
import os
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Dict, List, Optional

import r3
import yaml
from executor import ExternalCommandFailed, execute


def _get_color_arg(color: Optional[bool]) -> str:
    """Get the color argument for diff command.

    When auto-detecting (color=None), checks if stdout is a TTY.
    We use --color=always when stdout is a TTY because we capture output
    first (which would make --color=auto think it's not a TTY).
    """
    if color is None:
        return "--color=always" if sys.stdout.isatty() else "--color=never"
    elif color:
        return "--color=always"
    else:
        return "--color=never"


@contextmanager
def _pager_context(use_pager: Optional[bool] = None):
    """Context manager that pipes output through a pager like less.

    Args:
        use_pager: True to force pager, False to disable, None for auto (TTY only)
    """
    import subprocess
    import tempfile
    import io

    # Determine if we should use a pager
    if use_pager is None:
        use_pager = sys.stdout.isatty()

    if not use_pager:
        yield
        return

    # Capture output to StringIO, write to temp file, then open with less
    # This avoids all pipe buffering issues with ANSI codes
    old_stdout = sys.stdout
    captured = io.StringIO()
    sys.stdout = captured
    tmp_path = None

    try:
        yield
    finally:
        sys.stdout = old_stdout
        content = captured.getvalue()

        if not content:
            return

        try:
            # Write to temp file
            with tempfile.NamedTemporaryFile(mode='w', suffix='.diff', delete=False) as f:
                f.write(content)
                tmp_path = f.name

            # Use less with -r (colors), -F (exit if fits on screen), -X (don't clear)
            # Note: -r handles multi-line color sequences better than -R
            pager_cmd = os.environ.get('PAGER', 'less -rFX')
            subprocess.run(f"{pager_cmd} {tmp_path}", shell=True)

            # Reset terminal colors after pager exits
            print('\033[0m', end='')
        finally:
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except:
                    pass


def _get_changed_files(
    path1: Path,
    path2: Path,
    exclude: Optional[List[str]] = None
) -> Dict[str, str]:
    """Get list of changed files between two directories.

    Returns:
        Dict mapping relative file paths to change type ('M'=modified, 'A'=added, 'D'=deleted)
    """
    exclude = exclude or []
    exclude_args = " ".join(f"--exclude={pattern}" for pattern in exclude)

    # Use diff with brief output to find changed files
    command = f"diff -rq {exclude_args} {path1} {path2}"

    try:
        result = execute(command, capture=True, shell=True, check=False)
        output = result if result else ""
    except ExternalCommandFailed:
        # diff returns exit code 1 when there are differences
        try:
            result = execute(command, capture=True, shell=True, check=False)
            output = result if result else ""
        except:
            output = ""

    changes: Dict[str, str] = {}
    for line in output.strip().split("\n"):
        if not line:
            continue

        # Parse diff -rq output:
        # "Files path1/file and path2/file differ" -> modified
        # "Only in path1/dir: file" -> deleted
        # "Only in path2/dir: file" -> added
        if line.startswith("Files ") and " differ" in line:
            # Extract relative path from "Files path1/foo and path2/foo differ"
            parts = line.split(" and ")
            if len(parts) >= 2:
                file_path = parts[0].replace(f"Files {path1}/", "")
                changes[file_path] = "M"
        elif line.startswith("Only in "):
            # "Only in path1/subdir: filename" or "Only in path2: filename"
            match_str = line[8:]  # Remove "Only in "
            if ": " in match_str:
                dir_part, filename = match_str.rsplit(": ", 1)
                if str(path1) in dir_part:
                    # File only in path1 -> deleted
                    rel_dir = dir_part.replace(str(path1), "").lstrip("/")
                    rel_path = f"{rel_dir}/{filename}" if rel_dir else filename
                    changes[rel_path] = "D"
                elif str(path2) in dir_part:
                    # File only in path2 -> added
                    rel_dir = dir_part.replace(str(path2), "").lstrip("/")
                    rel_path = f"{rel_dir}/{filename}" if rel_dir else filename
                    changes[rel_path] = "A"

    return changes


def _diff_file(
    path1: Path,
    path2: Path,
    relative_path: str,
    change_type: str,
    color: Optional[bool] = None
) -> Optional[str]:
    """Get diff output for a single file.

    Args:
        path1: Base directory (previous version)
        path2: Compare directory (current version)
        relative_path: Path relative to the directories
        change_type: 'M' for modified, 'A' for added, 'D' for deleted
        color: Force color on/off

    Returns:
        Diff output string, or None if no diff
    """
    color_arg = _get_color_arg(color)
    file1 = path1 / relative_path
    file2 = path2 / relative_path

    if change_type == "M":
        command = f"diff -u {color_arg} {file1} {file2}"
    elif change_type == "A":
        # New file - diff against /dev/null
        command = f"diff -u {color_arg} /dev/null {file2}"
    elif change_type == "D":
        # Deleted file - diff against /dev/null
        command = f"diff -u {color_arg} {file1} /dev/null"
    else:
        return None

    try:
        result = execute(command, capture=True, shell=True, check=False)
        return result if result else None
    except ExternalCommandFailed:
        # diff returns exit code 1 when there are differences, but we want the output
        # Re-run and capture anyway
        import subprocess
        proc = subprocess.run(command, shell=True, capture_output=True, text=True)
        return proc.stdout if proc.stdout else None


def _categorize_changes(changes: Dict[str, str]) -> Dict[str, Dict[str, str]]:
    """Categorize changed files into config, metadata, and code.

    Returns:
        Dict with keys 'config', 'metadata', 'code', each containing
        a dict of relative_path -> change_type
    """
    categories: Dict[str, Dict[str, str]] = {
        "config": {},
        "metadata": {},
        "code": {}
    }

    for path, change_type in changes.items():
        if path == "r3.yaml" or path.endswith("/r3.yaml"):
            categories["config"][path] = change_type
        elif path == "metadata.yaml" or path.endswith("/metadata.yaml"):
            categories["metadata"][path] = change_type
        else:
            categories["code"][path] = change_type

    return categories


def _get_resolved_config(job_path: Path, repository_path: Path) -> dict:
    """Get the resolved config for a job (like at commit time).

    Resolves all dependencies and returns the updated config dict.
    Excludes 'hashes' which is only computed at commit time.
    """
    import copy

    job = r3.Job(job_path)
    repository = r3.Repository(repository_path)

    # resolve() modifies the job in place, updating job._config
    try:
        repository.resolve(job)
    except Exception as e:
        # If resolution fails, return original config with error note
        config = copy.deepcopy(job._config)
        config["_resolution_error"] = str(e)
        return config

    # Mirror Job.files: ensure dependency destinations are in ignore so the
    # resolved config matches what storage.add() persists at commit time.
    # Use idempotent insert — committed configs already contain them.
    ignore = job._config.get("ignore") or []
    existing = set(ignore)
    for dep in job.dependencies:
        pattern = f"/{dep.destination}"
        if pattern not in existing:
            ignore.append(pattern)
            existing.add(pattern)
    job._config["ignore"] = ignore

    # Remove fields computed at commit time, not relevant for diff
    config = copy.deepcopy(job._config)
    config.pop("hashes", None)
    config.pop("timestamp", None)
    return config


def _diff_normalized_yaml(
    file1: Path,
    file2: Path,
    label1: str,
    label2: str,
    color: Optional[bool] = None
) -> Optional[str]:
    """Get diff of two YAML files with normalized formatting.

    Loads both files and re-dumps them with consistent formatting (sort_keys=True)
    to avoid spurious diffs from formatting differences.
    """
    import tempfile
    import os as _os

    with open(file1) as f:
        content1 = yaml.safe_load(f)
    with open(file2) as f:
        content2 = yaml.safe_load(f)

    # Use default yaml.dump (sort_keys=True) for consistent formatting
    yaml1 = yaml.dump(content1, default_flow_style=False)
    yaml2 = yaml.dump(content2, default_flow_style=False)

    if yaml1 == yaml2:
        return None

    # Write to temp files for diff
    with tempfile.NamedTemporaryFile(mode='w', suffix='_old.yaml', delete=False) as f:
        f.write(yaml1)
        tmp1 = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='_new.yaml', delete=False) as f:
        f.write(yaml2)
        tmp2 = f.name

    try:
        color_arg = _get_color_arg(color)
        command = f"diff -u {color_arg} --label '{label1}' --label '{label2}' {tmp1} {tmp2}"

        import subprocess
        proc = subprocess.run(command, shell=True, capture_output=True, text=True)
        return proc.stdout if proc.stdout else None
    finally:
        _os.unlink(tmp1)
        _os.unlink(tmp2)


def _diff_resolved_r3_yaml(
    path1: Path,
    path2: Path,
    repository_path: Path,
    color: Optional[bool] = None
) -> Optional[str]:
    """Get diff of resolved r3.yaml between two job paths."""
    import tempfile
    import os as _os

    config1 = _get_resolved_config(path1, repository_path)
    config2 = _get_resolved_config(path2, repository_path)

    # r3 uses yaml.dump with default sort_keys=True, so we do the same for consistent comparison
    yaml1 = yaml.dump(config1, default_flow_style=False)
    yaml2 = yaml.dump(config2, default_flow_style=False)

    if yaml1 == yaml2:
        return None

    # Write to temp files for diff
    with tempfile.NamedTemporaryFile(mode='w', suffix='_old.yaml', delete=False) as f1:
        f1.write(yaml1)
        tmp1 = f1.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='_new.yaml', delete=False) as f2:
        f2.write(yaml2)
        tmp2 = f2.name

    try:
        color_arg = _get_color_arg(color)
        command = f"diff -u {color_arg} --label 'r3.yaml (resolved, previous)' --label 'r3.yaml (resolved, current)' {tmp1} {tmp2}"

        import subprocess
        proc = subprocess.run(command, shell=True, capture_output=True, text=True)
        return proc.stdout if proc.stdout else None
    finally:
        _os.unlink(tmp1)
        _os.unlink(tmp2)


def _print_name_only(changes: Dict[str, str]) -> bool:
    """Print only the names of changed files.

    Returns:
        True if no changes, False if there are changes
    """
    if not changes:
        print("No changes.")
        return True

    categories = _categorize_changes(changes)
    sections = [
        ("config", "Config"),
        ("metadata", "Metadata"),
        ("code", "Code"),
    ]

    for category_key, header in sections:
        category_changes = categories[category_key]
        if not category_changes:
            continue

        print(f"\n{header}:")
        for rel_path, change_type in sorted(category_changes.items()):
            indicator = {"M": "M", "A": "A", "D": "D"}[change_type]
            print(f"  {indicator} {rel_path}")

    return False


def _get_file_stat(path1: Path, path2: Path, relative_path: str, change_type: str) -> tuple:
    """Get line statistics for a single file.

    Returns:
        Tuple of (additions, deletions)
    """
    file1 = path1 / relative_path
    file2 = path2 / relative_path

    if change_type == "M":
        command = f"diff {file1} {file2}"
    elif change_type == "A":
        command = f"diff /dev/null {file2}"
    elif change_type == "D":
        command = f"diff {file1} /dev/null"
    else:
        return (0, 0)

    import subprocess
    proc = subprocess.run(command, shell=True, capture_output=True, text=True)
    output = proc.stdout

    additions = 0
    deletions = 0
    for line in output.split("\n"):
        if line.startswith("> "):
            additions += 1
        elif line.startswith("< "):
            deletions += 1

    return (additions, deletions)


def _print_stat(path1: Path, path2: Path, changes: Dict[str, str]) -> bool:
    """Print diff statistics (like git diff --stat).

    Returns:
        True if no changes, False if there are changes
    """
    if not changes:
        print("No changes.")
        return True

    categories = _categorize_changes(changes)
    sections = [
        ("config", "Config"),
        ("metadata", "Metadata"),
        ("code", "Code"),
    ]

    total_additions = 0
    total_deletions = 0
    total_files = 0

    for category_key, header in sections:
        category_changes = categories[category_key]
        if not category_changes:
            continue

        print(f"\n{header}:")
        for rel_path, change_type in sorted(category_changes.items()):
            additions, deletions = _get_file_stat(path1, path2, rel_path, change_type)
            total_additions += additions
            total_deletions += deletions
            total_files += 1

            # Format like git diff --stat
            indicator = {"M": "M", "A": "A", "D": "D"}[change_type]
            stat_str = ""
            if additions > 0:
                stat_str += f"+{additions}"
            if deletions > 0:
                if stat_str:
                    stat_str += ", "
                stat_str += f"-{deletions}"
            if not stat_str:
                stat_str = "0"

            print(f"  {indicator} {rel_path} ({stat_str})")

    print(f"\n{total_files} file(s) changed, {total_additions} insertion(s), {total_deletions} deletion(s)")
    return False


def _interactive_diff(
    path1: Path,
    path2: Path,
    changes: Dict[str, str],
    color: Optional[bool] = None
) -> None:
    """Interactive diff mode - select files to view.

    Shows a list of changed files and lets user select which to view.
    """
    if not changes:
        print("No changes.")
        return

    # Build flat list of files with their info
    categories = _categorize_changes(changes)
    files_list: List[tuple] = []  # (category, rel_path, change_type)

    for category_key in ["config", "metadata", "code"]:
        for rel_path, change_type in sorted(categories[category_key].items()):
            files_list.append((category_key, rel_path, change_type))

    def show_menu():
        print("\nChanged files:")
        print("-" * 40)
        for i, (category, rel_path, change_type) in enumerate(files_list, 1):
            indicator = {"M": "M", "A": "+", "D": "-"}[change_type]
            cat_label = {"config": "config", "metadata": "meta", "code": "code"}[category]
            print(f"  {i:2}. [{indicator}] [{cat_label}] {rel_path}")
        print("-" * 40)
        print("Commands: <number> = view file, a = all, q = quit")

    show_menu()

    while True:
        try:
            choice = input("\n> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if choice == 'q' or choice == 'quit':
            break
        elif choice == 'a' or choice == 'all':
            # Show all diffs
            for category, rel_path, change_type in files_list:
                print(f"\n{'='*60}")
                print(f"File: {rel_path}")
                print('='*60)
                diff_output = _diff_file(path1, path2, rel_path, change_type, color)
                if diff_output:
                    print(diff_output)
            show_menu()
        elif choice == 'l' or choice == 'list':
            show_menu()
        elif choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(files_list):
                category, rel_path, change_type = files_list[idx]
                print(f"\n{'='*60}")
                print(f"File: {rel_path}")
                print('='*60)
                diff_output = _diff_file(path1, path2, rel_path, change_type, color)
                if diff_output:
                    print(diff_output)
                show_menu()
            else:
                print(f"Invalid number. Enter 1-{len(files_list)}")
        elif choice == '':
            continue
        else:
            print("Unknown command. Use <number>, 'a' for all, 'l' for list, 'q' to quit")


def _print_structured_diff(
    path1: Path,
    path2: Path,
    changes: Dict[str, str],
    color: Optional[bool] = None,
    resolved: bool = False,
    repository_path: Optional[Path] = None
) -> bool:
    """Print structured diff output organized by category.

    Args:
        path1: Previous job path
        path2: Current job path
        changes: Dict of relative_path -> change_type
        color: Force color on/off
        resolved: If True, show resolved r3.yaml comparison
        repository_path: Path to r3 repository (required if resolved=True)

    Returns:
        True if no changes, False if there are changes
    """
    if not changes:
        print("No changes.")
        return True

    categories = _categorize_changes(changes)

    # Define section headers and their display names
    sections = [
        ("config", "Config Changes (r3.yaml)"),
        ("metadata", "Metadata Changes (metadata.yaml)"),
        ("code", "Code Changes"),
    ]

    has_output = False
    for category_key, header in sections:
        category_changes = categories[category_key]
        if not category_changes:
            continue

        has_output = True
        # Add "(resolved)" to config header if showing resolved diff
        if category_key == "config" and resolved:
            header = "Config Changes (r3.yaml, resolved)"
        print(f"\n{'='*3} {header} {'='*3}")

        for rel_path, change_type in sorted(category_changes.items()):
            # Print change indicator
            indicator = {"M": "M", "A": "+", "D": "-"}[change_type]
            print(f"  [{indicator}] {rel_path}")

        # Print actual diffs for this category
        print()
        for rel_path, change_type in sorted(category_changes.items()):
            # Use resolved diff for r3.yaml if requested
            if category_key == "config" and resolved and repository_path and rel_path == "r3.yaml":
                diff_output = _diff_resolved_r3_yaml(path1, path2, repository_path, color)
            # Use normalized diff for metadata.yaml to avoid formatting differences
            elif category_key == "metadata" and rel_path == "metadata.yaml" and change_type == "M":
                diff_output = _diff_normalized_yaml(
                    path1 / rel_path, path2 / rel_path,
                    "metadata.yaml (previous)", "metadata.yaml (current)",
                    color
                )
            else:
                diff_output = _diff_file(path1, path2, rel_path, change_type, color)
            if diff_output:
                print(diff_output)

    if not has_output:
        print("No changes.")
        return True

    hint = "--raw for unstructured output"
    if resolved:
        hint += ", --no-resolved for raw r3.yaml"
    print(f"\nUse {hint}")
    return False


def compare_directories(
    path1: Path,
    path2: Path,
    color: Optional[bool] = None,
    exclude: Optional[List[str]] = None
) -> bool:
    """Compare two directories recursively with colored output.

    Args:
        path1: First directory (typically the previous/committed version)
        path2: Second directory (typically the current version)
        color: Force color on/off. None = auto-detect TTY
        exclude: List of directory/file names to exclude from comparison

    Returns:
        True if directories are identical, False otherwise
    """
    if not path1.is_dir() or not path2.is_dir():
        raise ValueError("Both paths must be directories.")

    # Determine color setting (GNU diff 3.4+ supports --color)
    # When auto-detecting and stdout is a TTY, use --color=always since we capture
    # output first (which would make --color=auto think it's not a TTY)
    if color is None:
        color_arg = "--color=always" if sys.stdout.isatty() else "--color=never"
    elif color:
        color_arg = "--color=always"
    else:
        color_arg = "--color=never"

    # Build exclusion arguments
    exclude = exclude or []
    exclude_args = " ".join(f"--exclude={pattern}" for pattern in exclude)

    command = f"diff -ur {color_arg} {exclude_args} {path1} {path2}"

    try:
        result = execute(command, capture=True, shell=True, check=False)
        if result and result.strip():
            print(result)
            return False
        else:
            print("Directories are identical.")
            return True
    except ExternalCommandFailed:
        # diff returns exit code 1 when there are differences - just re-run without capture
        try:
            execute(command, shell=True, check=False)
        except ExternalCommandFailed:
            pass
        return False
