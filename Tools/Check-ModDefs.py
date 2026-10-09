#!/usr/bin/env python3
"""Check-ModDefs.py - static cross-reference checker for the mod tree. Read-only.

The CLOUD FALLBACK for Tools/Test-ModDefs.ps1, not a replacement. It needs no
game install and no PowerShell, so a session without either can still catch
the fault classes that do not need the vanilla index: malformed XML, unresolved
RR_ references, ParentName chains, folder-gated references, missing RR_
textures (graphic-class aware), DefOf names, Keyed strings, LoadFolders
coverage. It cannot see vanilla, so a vanilla defName typo passes here and
fails in Test-ModDefs.ps1. Run the PowerShell validator before calling anything
finished; run this one when that is impossible.

Usage:  python3 Tools/Check-ModDefs.py [repo-root]
Exit 1 on any ERROR line. Needs lxml and Pillow.
"""
import os, re, sys, glob, json
from collections import defaultdict
from lxml import etree
from PIL import Image

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = []
def rep(kind, msg): out.append((kind, msg))

# ---------------------------------------------------------------- gating
def gate_of(path):
    rel = os.path.relpath(path, ROOT)
    m = re.match(r'1\.6/Mods/([^/]+)/', rel)
    return m.group(1) if m else None

GATE_PKG = {'CombatExtended': 'CETeam.CombatExtended', 'Exosuit': 'Aoba.Exosuit.Framework',
            'Vehicles': 'SmashPhil.VehicleFramework', 'AlphaAnimals': 'sarg.alphaanimals',
            'RealisticBody': 'nals.realisticbody'}

xml_files = sorted(glob.glob(ROOT + '/1.6/**/*.xml', recursive=True))
defs = {}            # (type, defName) -> (file, line, gate)
abstracts = {}       # (type, Name) -> (file, line, gate)
by_name = defaultdict(list)   # defName -> [(type, file, line, gate)]
parent_refs = []     # (type, ParentName, file, line)
trees = {}
patch_files = []

for f in xml_files:
    try:
        tree = etree.parse(f)
    except Exception as e:
        rep('ERROR', f'malformed XML {f}: {e}'); continue
    trees[f] = tree
    root = tree.getroot()
    g = gate_of(f)
    if root.tag == 'Patch':
        patch_files.append(f); continue
    if root.tag != 'Defs':
        rep('WARN', f'{f}: root is <{root.tag}>'); continue
    for d in root:
        if not isinstance(d.tag, str): continue
        dn = d.find('defName')
        name = d.get('Name'); parent = d.get('ParentName'); abstract = d.get('Abstract')
        if name:
            key = (d.tag, name)
            if key in abstracts: rep('ERROR', f'duplicate abstract Name {key} in {f}:{d.sourceline} and {abstracts[key][0]}:{abstracts[key][1]}')
            abstracts[key] = (f, d.sourceline, g)
        if dn is not None and dn.text:
            key = (d.tag, dn.text.strip())
            if key in defs: rep('ERROR', f'duplicate defName {key} in {f}:{d.sourceline} and {defs[key][0]}:{defs[key][1]}')
            defs[key] = (f, d.sourceline, g)
            by_name[dn.text.strip()].append((d.tag, f, d.sourceline, g))
        elif not (abstract and abstract.lower() == 'true'):
            rep('ERROR', f'{f}:{d.sourceline} <{d.tag}> has no defName and is not Abstract')
        if parent:
            parent_refs.append((d.tag, parent, f, d.sourceline, g))

# ParentName resolution (only for RR_ parents; vanilla ones listed)
vanilla_parents = set()
for t, p, f, ln, g in parent_refs:
    if (t, p) in abstracts:
        pg = abstracts[(t, p)][2]
        if pg and pg != g: rep('ERROR', f'{f}:{ln} ParentName {p} lives in gated folder {pg} but def is in {g}')
    elif p.startswith('RR_'):
        rep('ERROR', f'{f}:{ln} unresolved RR_ ParentName {p} for <{t}>')
    else:
        vanilla_parents.add((t, p))

# ---------------------------------------------------------------- references
TYPE_BY_TAG = {
    'researchPrerequisite': 'ResearchProjectDef', 'prerequisites': 'ResearchProjectDef',
    'hiddenPrerequisites': 'ResearchProjectDef', 'researchPrerequisites': 'ResearchProjectDef',
    'abilityDef': 'AbilityDef', 'projectileDef': 'ThingDef', 'defaultProjectile': 'ThingDef',
    'hediffDef': 'HediffDef', 'sealHediff': 'HediffDef', 'stimHediff': 'HediffDef', 'hediff': 'HediffDef',
    'addsHediff': 'HediffDef', 'xenotype': 'XenotypeDef', 'xenotypes': 'XenotypeDef', 'color': 'XenotypeDef',
    'kind': 'PawnKindDef', 'faction': 'FactionDef', 'factionDef': 'FactionDef',
    'meme': 'MemeDef', 'otherMeme': 'MemeDef', 'requiredMemes': 'MemeDef', 'conflictingMemes': 'MemeDef',
    'issue': 'IssueDef', 'soundCast': 'SoundDef', 'soundLaunch': 'SoundDef', 'soundDef': 'SoundDef',
    'genes': 'GeneDef', 'thingToSpawn': None, 'buildDef': None, 'eventDef': 'HistoryEventDef',
    'thought': 'ThoughtDef', 'awardThought': 'ThoughtDef', 'lostThought': 'ThoughtDef',
    'leaderTitle': None, 'preceptDef': 'PreceptDef', 'precept': 'PreceptDef', 'thingDef': 'ThingDef',
    'skyfaller': 'ThingDef', 'leavingSkyfaller': 'ThingDef', 'worldObjectDef': 'WorldObjectDef',
    'nameMaker': 'RulePackDef', 'nameMakerFemale': 'RulePackDef', 'pawnNameMaker': 'RulePackDef',
    'settlementNameMaker': 'RulePackDef', 'factionNameMaker': 'RulePackDef', 'playerInitialSettlementNameMaker': 'RulePackDef',
    'biome': 'BiomeDef', 'recipe': 'RecipeDef', 'recipes': 'RecipeDef', 'storyteller': 'StorytellerDef',
    'turretDef': None, 'def': None, 'damageDef': 'DamageDef', 'statDef': 'StatDef',
    'ammoSet': None, 'eyeGene': 'GeneDef', 'geneDef': 'GeneDef', 'mustHaveGene': 'GeneDef',
    'ingredient': 'ThingDef', 'product': 'ThingDef', 'costList': 'ThingDef', 'ingredients': 'ThingDef',
    'items': 'ThingDef', 'things': 'ThingDef', 'weapons': 'ThingDef', 'apparel': None,
}
TAG_CONTEXT = {'tags', 'weaponTags', 'apparelTags', 'tradeTags', 'techHediffsTags', 'royalTitleTags',
               'thingSetMakerTags', 'styleTags', 'exclusionTags', 'apparelRequired', 'weaponClasses',
               'backstoryFilters', 'backstoryCategories', 'thingCategories', 'categories'}
TYPE_ALIASES = {'ThingDef': {'ThingDef', 'Vehicles.VehicleDef', 'Vehicles.VehicleBuildDef'}}

unresolved = defaultdict(list)
cross_gate = []
typed_mismatch = []
texture_refs = []   # (file, line, tagname, path, graphicClass, def_tag, defName, layers)
sound_refs = []

def def_context(el):
    cur = el
    while cur is not None and cur.getparent() is not None and cur.getparent().tag != 'Defs':
        cur = cur.getparent()
    return cur

def path_of(el):
    parts = []
    cur = el
    while cur is not None:
        parts.append(cur.tag if isinstance(cur.tag, str) else '?')
        cur = cur.getparent()
    return '/'.join(reversed(parts))

for f, tree in trees.items():
    g = gate_of(f)
    for el in tree.iter():
        if not isinstance(el.tag, str): continue
        txt = (el.text or '').strip()
        parent = el.getparent()
        ptag = parent.tag if parent is not None else ''
        tagname = el.tag if el.tag != 'li' else ptag
        # def-reference candidates
        if re.fullmatch(r'RR_[A-Za-z0-9_]+', txt) and el.tag != 'defName' and not el.get('Name'):
            if ptag in TAG_CONTEXT or el.tag in TAG_CONTEXT:
                continue
            if ptag in ('spawnCategories', 'categories'):
                continue  # BackstoryDef spawn categories are free strings, not defs
            if txt in by_name:
                targets = by_name[txt]
                tgates = {t[3] for t in targets}
                mayreq = el.get('MayRequire')
                if g not in tgates and not (None in tgates):
                    # referenced def exists only in gated folders not matching this file
                    needed = {GATE_PKG.get(x, x) for x in tgates if x}
                    if not (mayreq and any(m.lower() in mayreq.lower() for m in needed)):
                        cross_gate.append(f'{f}:{el.sourceline} <{path_of(el).split("/",2)[-1]}> = {txt} defined only in gate {tgates}; this file gate={g}; MayRequire={mayreq}')
                want = TYPE_BY_TAG.get(tagname)
                if want:
                    types = {t[0] for t in targets}
                    ok = types & TYPE_ALIASES.get(want, {want})
                    if not ok: typed_mismatch.append(f'{f}:{el.sourceline} <{tagname}> = {txt} is {types}, expected {want}')
            else:
                unresolved[txt].append(f'{f}:{el.sourceline} <{path_of(el).split("/",2)[-1]}>')
        # texture refs
        if el.tag in ('texPath', 'iconPath', 'texture', 'portraitLarge', 'portraitTiny', 'wornGraphicPath',
                      'uiIconPath', 'iconTexPath', 'expandingIconTexture', 'settlementTexturePath',
                      'graphicPath', 'texturePath', 'iconTexturePath', 'path', 'pathEast', 'pathNorth', 'pathSouth',
                      'texPathEast', 'texPathNorth', 'texPathSouth', 'uiIcon', 'icon', 'iconGizmo', 'modIconPath',
                      'wornGraphicPaths', 'iconPaths', 'portrait', 'texPathMask', 'maskPath'):
            if txt and '/' in txt:
                gc = None
                gd = parent if el.tag == 'texPath' else None
                if gd is not None:
                    gce = gd.find('graphicClass')
                    gc = gce.text.strip() if gce is not None and gce.text else None
                dctx = def_context(el)
                dn = dctx.find('defName') if dctx is not None else None
                layers = []
                if dctx is not None:
                    ap = dctx.find('apparel')
                    if ap is not None:
                        layers = [l.text.strip() for l in ap.findall('layers/li') if l.text]
                        bpg = [l.text.strip() for l in ap.findall('bodyPartGroups/li') if l.text]
                    else: bpg = []
                texture_refs.append((f, el.sourceline, el.tag, txt, gc, dctx.tag if dctx is not None else None,
                                     dn.text.strip() if dn is not None and dn.text else dctx.get('Name') if dctx is not None else None,
                                     layers, bpg, g))
        if el.tag == 'clipPath' and txt:
            sound_refs.append((f, el.sourceline, txt))
        # worn graphic also via <apparel><wornGraphicPath> handled above (tag wornGraphicPath)

# ---------------------------------------------------------------- patches
for f in patch_files:
    tree = trees[f]; g = gate_of(f)
    for xp in tree.iter('xpath'):
        t = (xp.text or '').strip()
        for m in re.finditer(r'defName\s*=\s*"([^"]+)"', t):
            n = m.group(1)
            if n.startswith('RR_') and n not in by_name:
                rep('ERROR', f'{f}:{xp.sourceline} patch xpath targets undefined RR_ def {n}')
            elif n.startswith('RR_'):
                tg = {x[3] for x in by_name[n]}
                if g not in tg and None not in tg:
                    rep('ERROR', f'{f}:{xp.sourceline} patch targets {n} which lives in gate {tg}; patch gate {g}')
    # patch value refs
    for el in tree.iter():
        if not isinstance(el.tag, str): continue
        txt = (el.text or '').strip()
        if re.fullmatch(r'RR_[A-Za-z0-9_]+', txt) and el.tag != 'defName':
            ptag = el.getparent().tag if el.getparent() is not None else ''
            if ptag in TAG_CONTEXT or el.tag in TAG_CONTEXT: continue
            if txt not in by_name: unresolved[txt].append(f'{f}:{el.sourceline} (patch) <{path_of(el)[-60:]}>')

# ---------------------------------------------------------------- textures
TEX_ROOTS = [ROOT + '/Textures'] + sorted(glob.glob(ROOT + '/1.6/Mods/*/Textures'))
def find_tex(path):
    hits = []
    for r in TEX_ROOTS:
        for ext in ('.png', '.jpg', '.jpeg', '.psd', '.dds'):
            p = os.path.join(r, path + ext)
            if os.path.exists(p): hits.append(p)
    return hits
def find_dir(path):
    hits = []
    for r in TEX_ROOTS:
        p = os.path.join(r, path)
        if os.path.isdir(p):
            imgs = [x for x in os.listdir(p) if x.lower().endswith(('.png', '.jpg'))]
            if imgs: hits.append((p, sorted(imgs)))
    return hits
def img_size(p):
    try:
        with Image.open(p) as im: return im.size, im.mode
    except Exception as e: return None, str(e)

COLLECTION = {'Graphic_StackCount', 'Graphic_Random', 'Graphic_Indexed', 'Graphic_Appearances', 'Graphic_Collection'}
MULTI = {'Graphic_Multi', 'Vehicles.Graphic_Vehicle', 'Graphic_Multi_AgeSecondary'}
tex_report = []
BODY = ['Male', 'Female', 'Thin', 'Hulk', 'Fat']
for (f, ln, tag, path, gc, dtag, dname, layers, bpg, g) in texture_refs:
    leaf = path.rsplit('/', 1)[-1]
    ours = 'RR_' in path
    if not ours:
        tex_report.append(('vanilla', f'{f}:{ln} {dname} {tag}={path} (vanilla/other-mod path, cannot verify)'))
        continue
    if tag == 'wornGraphicPath':
        overhead = any(l in ('Overhead', 'EyeCover') for l in layers) or (bpg and set(bpg) <= {'FullHead', 'UpperHead', 'Eyes', 'Teeth'})
        # Exosuit Framework parts are not body-typed: one <leaf>_<facing> set per part (CLAUDE.md, StarShell).
        if g == 'Exosuit': overhead = True
        missing = []; sizes = defaultdict(list)
        facings = ['north', 'east', 'south']
        if overhead:
            for fc in facings:
                hits = find_tex(f'{path}_{fc}')
                if not hits: missing.append(f'{leaf}_{fc}')
                for h in hits: sizes[img_size(h)[0]].append(os.path.relpath(h, ROOT))
        else:
            for b in BODY:
                for fc in facings:
                    hits = find_tex(f'{path}_{b}_{fc}')
                    if not hits: missing.append(f'{leaf}_{b}_{fc}')
                    for h in hits: sizes[img_size(h)[0]].append(os.path.relpath(h, ROOT))
        if missing: tex_report.append(('ERROR', f'{f}:{ln} {dname} wornGraphicPath {path} missing: {missing} (overhead={overhead} layers={layers})'))
        if len(sizes) > 1: tex_report.append(('WARN', f'{dname} worn textures have mixed sizes: ' + '; '.join(f'{k}: {len(v)} files' for k, v in sizes.items())))
        else: tex_report.append(('ok', f'{dname} worn: {list(sizes.keys())} x{sum(len(v) for v in sizes.values())} files (overhead={overhead})'))
        continue
    if gc in COLLECTION:
        hits = find_dir(path)
        if not hits: tex_report.append(('ERROR', f'{f}:{ln} {dname} {gc} texPath {path} is not a folder with images'))
        else:
            for p, imgs in hits:
                szs = {img_size(os.path.join(p, i))[0] for i in imgs}
                tex_report.append(('ok', f'{dname} {gc} {path}: {imgs} sizes {szs}'))
        continue
    if gc in MULTI:
        missing = []; szs = {}
        for fc in ('north', 'east', 'south'):
            hits = find_tex(f'{path}_{fc}')
            if not hits: missing.append(fc)
            for h in hits: szs[fc] = img_size(h)[0]
        if missing: tex_report.append(('ERROR', f'{f}:{ln} {dname} {gc} {path} missing facings {missing}'))
        else: tex_report.append(('ok', f'{dname} {gc} {path}: {szs}'))
        continue
    hits = find_tex(path)
    if not hits:
        # maybe a directory for Graphic_Single? no. report
        d = find_dir(path)
        tex_report.append(('ERROR', f'{f}:{ln} {dname} {tag}={path} (graphicClass={gc}) no file found' + (f'; but folder exists with {d[0][1]}' if d else '')))
    else:
        for h in hits:
            sz, mode = img_size(h)
            tex_report.append(('ok', f'{dname} {tag}={path} -> {os.path.relpath(h, ROOT)} {sz} {mode}'))

# sounds
for f, ln, clip in sound_refs:
    hits = glob.glob(f'{ROOT}/Sounds/{clip}.*')
    if not hits: rep('ERROR', f'{f}:{ln} clipPath {clip} not found under Sounds/')
    else: rep('ok', f'sound {clip} -> {[os.path.relpath(h, ROOT) for h in hits]}')

# ---------------------------------------------------------------- C# cross-checks
cs_files = sorted(glob.glob(ROOT + '/Source/RimRising/*.cs'))
cs = {f: open(f, encoding='utf-8', errors='replace').read() for f in cs_files}
cs_all = '\n'.join(cs.values())
classes = set(re.findall(r'\b(?:class|struct)\s+([A-Za-z_][A-Za-z0-9_]*)', cs_all))

# DefOf
for f, src in cs.items():
    for m in re.finditer(r'\[DefOf\]\s*public static class (\w+)\s*\{(.*?)\n\s*static \1\(', src, re.S):
        body = m.group(2)
        for fm in re.finditer(r'public static (\w+)\s+(\w+)\s*;', body):
            typ, nm = fm.groups()
            if (typ, nm) not in defs:
                rep('ERROR', f'{os.path.basename(f)} DefOf {m.group(1)}.{nm} : no <{typ}> with defName {nm}')
            else:
                dg = defs[(typ, nm)][2]
                if dg: rep('ERROR', f'{os.path.basename(f)} DefOf {m.group(1)}.{nm} points at def in gated folder {dg} - DefOf fails when that mod is absent')
                else: rep('ok', f'DefOf {m.group(1)}.{nm} -> {typ}')
# GetNamed literals
for f, src in cs.items():
    for m in re.finditer(r'DefDatabase<(\w+)>\.GetNamed(?:SilentFail)?\("([^"]+)"\)', src):
        typ, nm = m.groups()
        if nm.startswith('RR_') and (typ, nm) not in defs: rep('ERROR', f'{os.path.basename(f)} GetNamed {typ} {nm} undefined')
# string literal def names in TestScene arrays etc. -> skip (optional)

# Class references from XML
xml_class_refs = []
for f, tree in trees.items():
    for el in tree.iter():
        if not isinstance(el.tag, str): continue
        v = el.get('Class')
        cands = []
        if v: cands.append((v, 'Class attr'))
        if el.tag in ('workerClass', 'compClass', 'thingClass', 'biomeWorker', 'hediffClass', 'abilityClass',
                      'verbClass', 'skyfallerClass', 'worldObjectClass', 'conditionClass', 'questClass',
                      'royalTitleInheritanceWorkerClass', 'pawnGroupMakerClass', 'thoughtClass', 'projectileClass',
                      'jobClass', 'giverClass', 'commandClass', 'class', 'modExtensionClass') and el.text:
            cands.append((el.text.strip(), el.tag))
        for c, how in cands:
            short = c.split('.')[-1]
            if c.startswith('RimRising.') or short in classes:
                if short not in classes: rep('ERROR', f'{f}:{el.sourceline} {how} {c}: no such class in Source/')
                else: xml_class_refs.append(short)
            # vanilla/other-mod classes cannot be verified here
used_classes = set(xml_class_refs)

# Translate keys
keyed = {}
kf = ROOT + '/Languages/English/Keyed/RimRising.xml'
kt = etree.parse(kf)
for el in kt.getroot():
    if isinstance(el.tag, str): keyed[el.tag] = el.sourceline
used_keys = set(re.findall(r'"(RR_[A-Za-z0-9_]+)"\s*\.Translate', cs_all))
used_keys |= set(re.findall(r'messageKey\s*=\s*"(RR_[A-Za-z0-9_]+)"', cs_all))
used_keys |= set(re.findall(r'FormCaravan\("(RR_[A-Za-z0-9_]+)"\)', cs_all))
for k in sorted(used_keys):
    if k not in keyed: rep('ERROR', f'C# translates key {k} which is not in Keyed/RimRising.xml')
for k in sorted(keyed):
    if k not in used_keys and k not in cs_all: rep('WARN', f'Keyed string {k} (line {keyed[k]}) is not referenced from C# (may be used from XML labelKey?)')
# check labelKey usage in XML
for f, tree in trees.items():
    for el in tree.iter('labelKey'):
        # Only our own keys can be checked; a non-RR_ labelKey is a vanilla or DLC string.
        if el.text and el.text.strip().startswith('RR_') and el.text.strip() not in keyed: rep('ERROR', f'{f}:{el.sourceline} labelKey {el.text} not in Keyed')

# ---------------------------------------------------------------- LoadFolders
lf = etree.parse(ROOT + '/LoadFolders.xml')
for li in lf.iter('li'):
    p = (li.text or '').strip()
    if p and p != '/' and not os.path.isdir(os.path.join(ROOT, p)): rep('ERROR', f'LoadFolders.xml lists missing folder {p}')
gated_dirs = {os.path.basename(d) for d in glob.glob(ROOT + '/1.6/Mods/*')}
listed = {(li.text or '').strip().split('/')[-1] for li in lf.iter('li')}
for d in gated_dirs - listed: rep('ERROR', f'1.6/Mods/{d} exists but is not listed in LoadFolders.xml (it will NEVER load)')

# ---------------------------------------------------------------- summary
print(f'XML files: {len(xml_files)} ({len(patch_files)} patch files); defs: {len(defs)}; abstracts: {len(abstracts)}')
types = defaultdict(int)
for (t, n) in defs: types[t] += 1
print('def counts:', dict(sorted(types.items())))
print('\n=== vanilla/other-mod ParentNames used (unverifiable here) ===')
for t, p in sorted(vanilla_parents): print(f'  {t} <- {p}')
print('\n=== UNRESOLVED RR_ references (text matched RR_* but no def with that name) ===')
for k, v in sorted(unresolved.items()):
    print(f'  {k}:'); [print('     ', x) for x in v]
print('\n=== cross-gate references ===')
for x in cross_gate: print('  ', x)
print('\n=== typed mismatches ===')
for x in typed_mismatch: print('  ', x)
print('\n=== TEXTURES ===')
for k, m in tex_report:
    if k != 'ok': print(f'  [{k}] {m}')
print('  -- ok --')
for k, m in tex_report:
    if k == 'ok': print(f'  {m}')
print('\n=== MESSAGES ===')
for k, m in out:
    if k != 'ok': print(f'  [{k}] {m}')
print('  -- ok --')
for k, m in out:
    if k == 'ok': print(f'  {m}')
print('\n=== C# classes referenced from XML:', sorted(used_classes))
print('=== C# classes defined:', sorted(classes))

errors = [m for k, m in out if k == 'ERROR']
warns = [m for k, m in out if k == 'WARN']
print(f'\n  {len(errors)} error(s), {len(warns)} warning(s)')
sys.exit(1 if errors else 0)
