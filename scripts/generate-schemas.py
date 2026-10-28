#!/usr/bin/env python3
"""從 markdown 規格產生機器可讀白名單。

markdown 是 source of truth；本腳本產生的 json 不要手改。
json 內含來源檔的 sha256，Swift 測試用它確認兩邊沒有漂移。

用法：python3 scripts/generate-schemas.py
"""
import hashlib, io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "organizer", "references")
OUT = os.path.join(ROOT, "organizer", "schemas")

def read(path):
    with io.open(path, encoding="utf-8") as f:
        return f.read()

def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def sections(md):
    """切成 {標題: 內文}，以 '# N. Title' 為界。"""
    out, cur, buf = {}, None, []
    for line in md.splitlines():
        m = re.match(r"^# \d+\.\s+(.*)$", line)
        if m:
            if cur is not None:
                out[cur] = "\n".join(buf)
            cur, buf = m.group(1).strip(), []
        elif cur is not None:
            buf.append(line)
    if cur is not None:
        out[cur] = "\n".join(buf)
    return out

def first_block(body):
    m = re.search(r"```text\n(.*?)```", body, re.S)
    return [l.strip() for l in m.group(1).splitlines() if l.strip()] if m else []

def clean_tree(lines):
    out = []
    for l in lines:
        l = re.sub(r"^[│├└─\s]+", "", l).strip()
        if l:
            out.append(l)
    return out

# ---------- taxonomy ----------
tax_md = read(os.path.join(REF, "taxonomy.md"))
tax = sections(tax_md)

top_level = first_block(tax["Top-Level Categories"])
categories = {name: [] for name in top_level}

foley = clean_tree(first_block(tax["Foley"]))
categories["Foley"] = [x for x in foley if x != "Foley"]

for name in top_level:
    if name in ("Foley", "Other", "Unclassified"):
        continue
    body = tax.get(name)
    if not body:
        continue
    subs = first_block(body)
    # Impacts 用 "Impacts/Metal" 形式
    subs = [s.split("/", 1)[1].strip() if s.startswith(name + "/") else s for s in subs]
    categories[name] = subs

taxonomy = {
    "version": 3,
    "source": "organizer/references/taxonomy.md",
    "source_sha256": sha256(tax_md),
    "top_level": top_level,
    "categories": categories,
}

# ---------- tag vocabulary ----------
tag_md = read(os.path.join(REF, "tagging-rules.md"))
tagsec = sections(tag_md)
GROUPS = {
    "material": "Material",
    "action": "Action",
    "character": "Character",
    "environment": "Environment",
    "temporal": "Temporal",
    "movement": "Movement",
    "mechanical": "Mechanical Qualities",
}
groups = {k: first_block(tagsec[v]) for k, v in GROUPS.items()}
canonical = sorted({t for g in groups.values() for t in g})

vocab = {
    "version": 1,
    "source": "organizer/references/tagging-rules.md",
    "source_sha256": sha256(tag_md),
    "max_tags": 12,
    "target_range": [3, 8],
    "groups": groups,
    "canonical": canonical,
}

# ---------- style vocabulary ----------
style_md = read(os.path.join(REF, "style-vocabulary.md"))
stylesec = sections(style_md)
styles = first_block(stylesec["Styles"])

aliases = {}
for line in first_block(stylesec["Aliases"]):
    if "->" not in line:
        continue
    left, right = [x.strip() for x in line.split("->", 1)]
    aliases[left.lower()] = right

# 長詞先比對，"tech house" 才不會被 "house" 搶走。
# 排序在產生階段做掉，Swift 端就不必依賴宣告順序。
alias_order = sorted(aliases.keys(), key=lambda t: (-len(t.split()), -len(t), t))

# 同時是曲風名也是一般音效描述詞的字。只有在音樂製作素材的脈絡下才算風格，
# 否則「金屬地板上的腳步聲」會被標成 Metal、「房子音效庫」會被標成 House。
ambiguous = [a.strip().lower() for a in first_block(stylesec["Ambiguous Aliases"]) if a.strip()]

style = {
    "version": 1,
    "source": "organizer/references/style-vocabulary.md",
    "source_sha256": sha256(style_md),
    "styles": styles,
    "aliases": aliases,
    "alias_order": alias_order,
    "ambiguous": ambiguous,
}

# ---------- texture vocabulary ----------
# 材質是字面題，不是聲學題：塑膠跟木頭在頻譜上沒有可靠的分界（D-013）。
texture_md = read(os.path.join(REF, "texture-vocabulary.md"))
texsec = sections(texture_md)
textures = first_block(texsec["Textures"])

tex_aliases = {}
for line in first_block(texsec["Aliases"]):
    if "->" not in line:
        continue
    left, right = [x.strip() for x in line.split("->", 1)]
    tex_aliases[left.lower()] = right

tex_order = sorted(tex_aliases.keys(), key=lambda t: (-len(t.split()), -len(t), t))

# 表面詞只是退路：路徑上有材質詞就用材質詞，材質比較具體。
surface = [x.strip() for x in first_block(texsec["Surface Terms"]) if x.strip()]

# 同時是材質也是曲風的字。在 Drums/ 或 Instruments/ 底下由風格認領，材質留空。
tex_ambiguous = [x.strip().lower() for x in first_block(texsec["Genre-Colliding Aliases"]) if x.strip()]

texture = {
    "version": 1,
    "source": "organizer/references/texture-vocabulary.md",
    "source_sha256": sha256(texture_md),
    "textures": textures,
    "aliases": tex_aliases,
    "alias_order": tex_order,
    "surface": surface,
    "ambiguous": tex_ambiguous,
}

os.makedirs(OUT, exist_ok=True)
for name, data in (("taxonomy.json", taxonomy),
                   ("tag-vocabulary.json", vocab),
                   ("style-vocabulary.json", style),
                   ("texture-vocabulary.json", texture)):
    with io.open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

# ---------- 自我檢查 ----------
errors = []
# 硬編數量是為了讓「不小心刪掉一整個分類」變成建置失敗而不是靜默漂移。
# 刻意增減分類時要一起改這裡。
EXPECTED_TOP_LEVEL = 15
if len(top_level) != EXPECTED_TOP_LEVEL:
    errors.append("top-level 分類數不是 %d：%d" % (EXPECTED_TOP_LEVEL, len(top_level)))
for must in ("Foley", "Unclassified"):
    if must not in top_level:
        errors.append("缺少必要的 top-level 分類：%s" % must)
for name, subs in categories.items():
    for s in subs:
        if s not in tax_md:
            errors.append("子分類 %s/%s 在 taxonomy.md 中找不到" % (name, s))
for a in ambiguous:
    if a not in aliases:
        errors.append("ambiguous 清單裡的 %s 不在別名表中" % a)
for alias, target in aliases.items():
    if target not in styles:
        errors.append("別名 %s 指向不存在的風格：%s" % (alias, target))
if len(styles) < 10:
    errors.append("風格白名單只有 %d 個，看起來解析失敗了" % len(styles))

if errors:
    print("FAILED:")
    for e in errors:
        print("  -", e)
    sys.exit(1)

print("taxonomy.json       %d 個 top-level，%d 個分類路徑" % (len(top_level), sum(len(v) for v in categories.values()) + len(top_level)))
print("tag-vocabulary.json %d 個 canonical 標籤" % len(canonical))
print("style-vocabulary.json %d 個風格，%d 條別名，%d 條需脈絡" % (len(styles), len(aliases), len(ambiguous)))
print("texture-vocabulary.json %d 個材質，%d 條別名，%d 個表面詞" % (len(textures), len(tex_aliases), len(surface)))
