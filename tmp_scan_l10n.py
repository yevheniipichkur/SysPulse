import re
import pathlib

root = pathlib.Path(r"c:\Users\YevheniiPichkur\OneDrive - EWL\Pulpit\ssh")
strings = set(
    re.findall(
        r'^"([^"]+)"',
        (root / "SysPulse/Resources/en.lproj/Localizable.strings").read_text(encoding="utf-8"),
        re.M,
    )
)
patterns = [
    r'Text\("([^"\\]+)"\)',
    r'Label\("([^"\\]+)"',
    r'title: "([^"\\]+)"',
    r'subtitle: "([^"\\]+)"',
    r'navigationTitle\("([^"\\]+)"\)',
    r'feature: "([^"\\]+)"',
    r'Section\("([^"\\]+)"\)',
    r'TextField\("([^"\\]+)"',
    r'Picker\("([^"\\]+)"',
    r'\.alert\("([^"\\]+)"',
    r'Button\("([^"\\]+)"',
    r'accessibilityLabel\("([^"\\]+)"',
    r'accessibilityLabel\(Text\("([^"\\]+)"\)\)',
    r'GlassPrimaryButton\(title: "([^"\\]+)"',
    r'message: "([^"\\]+)"',
    r'actionTitle: "([^"\\]+)"',
    r'emptyTitle: "([^"\\]+)"',
    r'emptyMessage: "([^"\\]+)"',
    r'refreshTitle: "([^"\\]+)"',
]
found = set()
for f in (root / "SysPulse").rglob("*.swift"):
    text = f.read_text(encoding="utf-8")
    for p in patterns:
        found.update(re.findall(p, text))
missing = sorted(k for k in found if k and k[0].isalpha() and k not in strings)
for k in missing:
    print(k)
print("---", len(missing), "missing")
