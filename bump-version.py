"""Bump VERSION, one digit at a time, rolling over at 9.

Each component runs 0-9 and then carries into the one above, so the sequence is
1.3.0, 1.3.1, ... 1.3.9, 1.4.0, ... 1.9.9, 2.0.0. No component ever exceeds 9.

    python bump-version.py            # 1.3.0 -> 1.3.1
    python bump-version.py --minor    # 1.3.4 -> 1.4.0
    python bump-version.py --major    # 1.3.4 -> 2.0.0
    python bump-version.py --check    # verify the file obeys the rule

Bumping alone changes nothing anyone can install - run build-installer.py after,
which stamps the number into install.ps1 and refuses to ship if the two disagree.
"""
import argparse
import pathlib
import sys

VERSION = pathlib.Path(__file__).resolve().parent / "VERSION"


def read():
    parts = [int(p) for p in VERSION.read_text(encoding="utf-8").strip().split(".")]
    if len(parts) != 3:
        sys.exit(f"VERSION must have three parts, found {len(parts)}: {parts}")
    return parts


def check(parts):
    """A component above 9 means someone bumped by hand and skipped the carry."""
    bad = [i for i, p in enumerate(parts) if p > 9]
    if bad:
        names = ["major", "minor", "patch"]
        sys.exit(
            f"{'.'.join(map(str, parts))} breaks the rule: "
            + ", ".join(f"{names[i]} is {parts[i]}, above 9" for i in bad)
            + "\nEach component runs 0-9 and carries into the one above."
        )
    return parts


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--minor", action="store_true", help="carry into minor now")
    g.add_argument("--major", action="store_true", help="carry into major now")
    ap.add_argument("--check", action="store_true", help="verify only, change nothing")
    args = ap.parse_args()

    major, minor, patch = check(read())

    if args.check:
        print(f"VERSION {major}.{minor}.{patch} obeys the rule")
        return

    if args.major:
        major, minor, patch = major + 1, 0, 0
    elif args.minor:
        minor, patch = minor + 1, 0
    else:
        patch += 1

    # the carry, which is the whole point
    if patch > 9:
        patch, minor = 0, minor + 1
    if minor > 9:
        minor, major = 0, major + 1

    new = f"{major}.{minor}.{patch}"
    check([major, minor, patch])
    VERSION.write_text(new + "\n", encoding="utf-8")
    print(f"VERSION -> {new}")
    print("now run: python build-installer.py")


if __name__ == "__main__":
    main()
