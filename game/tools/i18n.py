#!/usr/bin/env python3
"""Дві мови, російська й українська (питання Q26). Вихідна мова — російська: російський рядок і є ключем перекладу.

  python3 -I game/tools/i18n.py wrap      обгорнути російські рядки в коді в I18n.t("...") (повторний запуск нічого не змінює)
  python3 -I game/tools/i18n.py extract   зібрати всі рядки гри в i18n/uk.po (готові переклади зберігаються)
  python3 -I game/tools/i18n.py check     скільки рядків ще без перекладу (вихід 1, якщо є)

Звідки беруться рядки:
  - код .gd: усе, що обгорнуто в I18n.t("...");
  - дані data/**/*.json: рядкові значення з кирилицею (крім полів-приміток _note, notes тощо),
    вони перекладаються під час читання файлу через I18n.tree();
  - ресурси бою data/battle/**/*.tres: title і description, перекладаються в battle/battle_data.gd.
Не обгортаються: коментарі, print/push_error/push_warning/assert, шейдерний код у потрійних лапках,
шаблони match і значення @export (там потрібні сталі вирази).
"""
import json
import pathlib
import re
import sys

GAME = pathlib.Path(__file__).resolve().parent.parent
PO = GAME / "i18n" / "uk.po"
SKIP_DIRS = {"tests", "qa", "tools", ".godot", "i18n"}
CYR = re.compile(r"[А-Яа-яЁё]")
LOG_CALL = re.compile(r"^\s*(print|printerr|print_debug|push_error|push_warning|assert)\s*\(")
NOTE_KEYS = {"_note", "notes", "_notes", "note", "_comment", "_source", "_how"}
WRAP = "I18n.t("


def gd_files():
    for p in sorted(GAME.rglob("*.gd")):
        rel = p.relative_to(GAME)
        if SKIP_DIRS & set(rel.parts[:-1]) or rel.as_posix() == "i18n/i18n.gd":
            continue
        yield p


def literals(text):
    """(початок, кінець, лапка) звичайних рядків "..." і '...' поза коментарями й потрійними лапками."""
    i, n = 0, len(text)
    out = []
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith('"""', i) or text.startswith("'''", i):
            q = text[i:i + 3]
            j = text.find(q, i + 3)
            i = n if j < 0 else j + 3
            continue
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append((i, j + 1, c))
            i = j + 1
            continue
        i += 1
    return out


def line_of(text, pos):
    a = text.rfind("\n", 0, pos) + 1
    b = text.find("\n", pos)
    return a, (len(text) if b < 0 else b)


def wrap_file(p):
    text = p.read_text(encoding="utf-8")
    edits = []
    for a, b, q in literals(text):
        s = text[a:b]
        if not CYR.search(s):
            continue
        before = text[max(0, a - len(WRAP)):a]
        if before == WRAP or text[a - 1:a] in ("&", "^"):
            continue
        la, lb = line_of(text, a)
        line = text[la:lb]
        if LOG_CALL.match(line) or line.lstrip().startswith("@export"):
            continue
        st = line.strip()
        if st.endswith(":") and not st.startswith(("if ", "elif ", "for ", "while ", "func ", "static ")) and st.startswith(("\"", "'")) and "{" not in line:
            continue   # шаблон match
        edits.append((a, b))
    if not edits:
        return 0
    for a, b in reversed(edits):
        text = text[:a] + WRAP + text[a:b] + ")" + text[b:]
    # const с вызовом I18n.t — уже не постоянное выражение: верхний уровень → static var, внутри функции → var
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)const(\s+\w+)", lines[i])
        if m:
            j, depth = i, 0
            while True:
                depth += sum(lines[j].count(c) for c in "([{") - sum(lines[j].count(c) for c in ")]}")
                if depth <= 0 or j == len(lines) - 1:
                    break
                j += 1
            if any(WRAP in lines[k] for k in range(i, j + 1)):
                kw = "static var" if m.group(1) == "" else "var"
                lines[i] = m.group(1) + kw + lines[i][len(m.group(1)) + len("const"):]
            i = j + 1
            continue
        i += 1
    p.write_text("\n".join(lines), encoding="utf-8")
    return len(edits)


def unescape(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def code_strings():
    out = {}
    for p in gd_files():
        text = p.read_text(encoding="utf-8")
        for a, b, q in literals(text):
            if text[max(0, a - len(WRAP)):a] == WRAP and CYR.search(text[a:b]):
                out.setdefault(unescape(text[a + 1:b - 1]), p.relative_to(GAME).as_posix())
    return out


def json_strings():
    out = {}

    def walk(v, src, key=""):
        if isinstance(v, dict):
            for k, x in v.items():
                if k not in NOTE_KEYS:
                    walk(x, src, k)
        elif isinstance(v, list):
            for x in v:
                walk(x, src, key)
        elif isinstance(v, str) and CYR.search(v):
            out.setdefault(v, src)
    for p in sorted((GAME / "data").rglob("*.json")):
        walk(json.loads(p.read_text(encoding="utf-8")), p.relative_to(GAME).as_posix())
    return out


def tres_strings():
    out = {}
    for p in sorted((GAME / "data" / "battle").rglob("*.tres")):
        for m in re.finditer(r'^(title|description) = "((?:[^"\\]|\\.)*)"$', p.read_text(encoding="utf-8"), re.M):
            if CYR.search(m.group(2)):
                out.setdefault(unescape(m.group(2)), p.relative_to(GAME).as_posix())
    return out


def po_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def po_unquote(s):
    return unescape(s[1:-1])


def read_po(path):
    """{msgid: msgstr} из .po (только однострочные и склеенные строки, как пишет этот скрипт)."""
    tr = {}
    if not path.exists():
        return tr
    cur, field = {"msgid": "", "msgstr": ""}, None
    for line in path.read_text(encoding="utf-8").split("\n") + [""]:
        if line.startswith("msgid "):
            if cur["msgid"]:
                tr[cur["msgid"]] = cur["msgstr"]
            cur, field = {"msgid": po_unquote(line[6:]), "msgstr": ""}, "msgid"
        elif line.startswith("msgstr "):
            cur["msgstr"], field = po_unquote(line[7:]), "msgstr"
        elif line.startswith('"') and field:
            cur[field] += po_unquote(line)
        elif not line.strip() and field == "msgstr" and cur["msgid"]:
            tr[cur["msgid"]] = cur["msgstr"]
            cur, field = {"msgid": "", "msgstr": ""}, None
    return tr


def write_po(path, entries, old):
    path.parent.mkdir(parents=True, exist_ok=True)
    out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Language: uk\\n"',
           '"Plural-Forms: nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);\\n"', ""]
    for s, src in entries:
        out += [f"#: {src}", "msgid " + po_quote(s), "msgstr " + po_quote(old.get(s, "")), ""]
    path.write_text("\n".join(out), encoding="utf-8")


def all_entries():
    seen = {}
    for d in (code_strings(), json_strings(), tres_strings()):
        for s, src in d.items():
            seen.setdefault(s, src)
    return sorted(seen.items(), key=lambda x: (x[1], x[0]))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "wrap":
        total = 0
        for p in gd_files():
            n = wrap_file(p)
            if n:
                print(f"{p.relative_to(GAME)}: {n}")
                total += n
        print(f"обёрнуто строк: {total}")
    elif cmd == "extract":
        old = read_po(PO)
        entries = all_entries()
        write_po(PO, entries, old)
        done = sum(1 for s, _ in entries if old.get(s))
        print(f"{PO.relative_to(GAME)}: строк {len(entries)}, переведено {done}, лишних старых {len(set(old) - {s for s, _ in entries})}")
    elif cmd == "check":
        old = read_po(PO)
        miss = [s for s, _ in all_entries() if not old.get(s)]
        print(f"без перевода: {len(miss)}")
        for s in miss[:20]:
            print("  ", s[:100])
        sys.exit(1 if miss else 0)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
