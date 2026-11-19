#!/usr/bin/env python3
"""Build the checked-in native .strings resources from reviewed translation tables."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ["en", "ja", "ko", "de", "fr", "es", "pt-BR", "it", "ru", "ar", "hi"]
translations = {language: {} for language in LANGUAGES}
for table in sorted((ROOT / "Translations").glob("*.tsv")):
    if table.name.startswith("."):  # exFAT AppleDouble companions, not tables
        continue
    for number, line in enumerate(table.read_text().splitlines(), 1):
        if not line.strip():
            continue
        columns = line.split("|")
        assert len(columns) == 12, (table.name, number, len(columns))
        key = columns[0]
        for language, value in zip(LANGUAGES, columns[1:]):
            assert key not in translations[language], ("duplicate", key)
            assert value and key.count("%@") == value.count("%@"), ("placeholder", language, key)
            translations[language][key] = value

for language, values in translations.items():
    for name in ["设置", "开启自动分组"]:
        values[name + "…"] = values[name] + "…"
    values["启用新版自动分组…"] = values["启用新版"] + "…"
    values["旧版服务运行中"] = values["旧版运行中"]
    for n in range(1, 4):
        values[f"文稿 {n:02d}"] = values["文稿"] + f" {n:02d}"
        values[f"照片 {n:02d}"] = values["图像"] + f" {n:02d}"
    values["Finder分组规则.json"] = "Finder-grouping-rules.json"
    values["Finder运行记录.json"] = "Finder-activity.json"

keys = set(translations["en"])
required = set()
for source in (ROOT / "Sources").glob("*.swift"):
    if source.name.startswith("."):
        continue
    required.update(re.findall(r'L\.[tf]\("([^"\n]+)"', source.read_text()))
assert not required - keys, ("missing translations", sorted(required - keys))

translations["zh-Hans"] = {key: key for key in keys}
hant_file = ROOT / "Translations" / "zh-Hant.json"
if hant_file.exists():
    translations["zh-Hant"] = json.loads(hant_file.read_text())
else:
    from opencc import OpenCC
    converter = OpenCC("s2twp")
    values = {key: converter.convert(key).replace("輔助功能", "輔助使用").replace("全域", "全域") for key in keys}
    translations["zh-Hant"] = values
    hant_file.write_text(json.dumps(values, ensure_ascii=False, indent=2))

def escape(text):
    return json.dumps(text, ensure_ascii=False)

for language, values in translations.items():
    assert set(values) == keys, ("key parity", language)
    for key, value in values.items():
        assert key.count("%@") == value.count("%@"), ("format parity", language, key)
    folder = ROOT / "Resources" / (language + ".lproj")
    folder.mkdir(parents=True, exist_ok=True)
    folder.joinpath("Localizable.strings").write_text("\n".join(f"{escape(key)} = {escape(values[key])};" for key in sorted(keys)) + "\n")
    name = values["Finder 分组助手"]
    reason = values["用于选择 Finder 原生分组与排序菜单"] + ". " + values["不上传文件，无第三方运行时"]
    folder.joinpath("InfoPlist.strings").write_text(
        f'"CFBundleDisplayName" = {escape(name)};\n'
        f'"CFBundleName" = {escape(name)};\n'
        f'"NSAppleEventsUsageDescription" = {escape(reason)};\n'
    )
print(f"Verified {len(keys)} keys × {len(translations)} languages. No missing keys or format mismatches.")
