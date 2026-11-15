#!/usr/bin/env python3
"""
FleetPay — converte um ficheiro Via Verde (CSV ou XLSX) em JSON para fp_importar_viaverde().

Uso:  python3 -I parse_viaverde.py <ficheiro>  >  linhas.json
Saída: {"linhas":[{"matricula","data","hora","valor","descricao"}, ...], "ignoradas": n, "colunas": [...]}

Replica a deteção de colunas de processViaVerde() do admin.html:
  • matrícula: matr | placa | viatura | license plate
  • valor: "Liquid Value" (líquido c/ desconto) > valor | value | amount | montante | total
  • data: Data Entrada / Entry Date > Data Saída / Exit Date > Data / Date
  • hora: coluna "Hora Entrada"/"Hora Saída" ou embebida na data
  • descrição: local/descrição/entrada/saída/"Barreira Entrada → Barreira Saída" (+ Tipo de Evento se ≠ Portagem)
Aceita o extrato mensal (EXTRACTO_*.csv, ';', latin1, preâmbulo) e o export semanal de movimentos.
"""
import csv, io, json, re, sys
from datetime import datetime

RX = {
    'mat':   re.compile(r'matr|placa|viatura|license\s*plate|licenseplate', re.I),
    'liq':   re.compile(r'liquid\s*value|liquidvalue|valor\s*l[ií]quido', re.I),
    'val':   re.compile(r'^value$|^valor$|valor(?!.*(iva|imposto|desc|liquid|energia|acesso|tempo|ativa))|amount|montante|^total$|pre[cç]o|euro', re.I),
    'd_ent': re.compile(r'data\s*(de\s*)?entrada|entry\s*date|entrydate|start\s*date|startdate', re.I),
    'd_sai': re.compile(r'data\s*(de\s*)?sa[ií]da|exit\s*date|exitdate|end\s*date|enddate', re.I),
    'd_gen': re.compile(r'^data$|^date$|^dia$|movimento|data\s*(da\s*)?transa', re.I),
    'h_ent': re.compile(r'hora\s*(de\s*)?entrada|entry\s*time', re.I),
    'h_sai': re.compile(r'hora\s*(de\s*)?sa[ií]da|exit\s*time', re.I),
    'local': re.compile(r'local|descri|portagem|esta[çc][ãa]o|entry\s*point|entrypoint|^servi[çc]o$', re.I),
    'b_ent': re.compile(r'barreira\s*entrada|entry\s*(barrier|plaza|point)|^entrada$', re.I),
    'b_sai': re.compile(r'barreira\s*sa[ií]da|exit\s*(barrier|plaza|point)|^sa[ií]da$', re.I),
    'tipo':  re.compile(r'tipo\s*(de\s*)?evento|event\s*type|^tipo$|^servi[çc]o$', re.I),
}

def first(keys, rx):
    for k in keys:
        if rx.search(k): return k
    return None

def clean(v):
    t = (v or '').strip() if isinstance(v, str) else ('' if v is None else str(v).strip())
    return '' if t in ('--', '-') else t

def parse_valor(s):
    s = clean(s).replace('€', '').replace(' ', '')
    if not s: return 0.0
    if ',' in s and '.' in s: s = s.replace('.', '').replace(',', '.')
    else: s = s.replace(',', '.')
    s = re.sub(r'[^\d.\-]', '', s)
    try: return float(s)
    except ValueError: return 0.0

def parse_data(s):
    s = clean(s)
    if isinstance(s, datetime): return s.strftime('%Y-%m-%d')
    m = re.match(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})', s)
    if m: return f'{m[1]}-{int(m[2]):02d}-{int(m[3]):02d}'
    m = re.match(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})', s)
    if m:
        a, b, y = int(m[1]), int(m[2]), m[3]
        if a > 12: d, mo = a, b
        elif b > 12: d, mo = b, a
        elif re.search(r'\b(am|pm)\b', s, re.I): d, mo = b, a   # US M/D
        else: d, mo = a, b                                        # PT D/M
        return f'{y}-{mo:02d}-{d:02d}'
    return None

def parse_hora(*cands):
    for s in cands:
        m = re.search(r'(\d{1,2}):(\d{2})(?::(\d{2}))?', clean(s))
        if m: return f'{int(m[1]):02d}:{m[2]}:{m[3] or "00"}'
    return '00:00:00'

def read_rows(path):
    if path.lower().endswith(('.xlsx', '.xls', '.xlsm')):
        import openpyxl, warnings
        warnings.filterwarnings('ignore')
        # sem read_only: o xlsx da Via Verde não declara dimensões e em read_only só devolve a 1.ª célula
        ws = openpyxl.load_workbook(path, data_only=True).worksheets[0]
        table = [[('' if c is None else (c.strftime('%Y-%m-%d %H:%M:%S') if hasattr(c, 'strftime') else str(c))) for c in r] for r in ws.iter_rows(values_only=True)]
    else:
        raw = open(path, 'rb').read()
        for enc in ('utf-8-sig', 'utf-8', 'cp1252', 'latin-1'):
            try: text = raw.decode(enc); break
            except UnicodeDecodeError: continue
        sample = text[:4000]
        delim = ';' if sample.count(';') > sample.count(',') else ','
        table = list(csv.reader(io.StringIO(text), delimiter=delim))
    # cabeçalho = primeira linha com uma coluna de matrícula
    hidx = next((i for i, r in enumerate(table) if any(RX['mat'].search(str(c)) for c in r)), None)
    if hidx is None: return [], []
    headers = [str(h).strip().lower() for h in table[hidx]]
    rows = []
    for r in table[hidx + 1:]:
        if not any(clean(c) for c in r): continue
        rows.append({headers[i]: (r[i] if i < len(r) else '') for i in range(len(headers)) if headers[i]})
    return headers, rows

def main(path):
    headers, rows = read_rows(path)
    if not rows:
        print(json.dumps({'linhas': [], 'ignoradas': 0, 'colunas': headers, 'erro': 'sem linhas / cabeçalho não encontrado'})); return
    keys = list(rows[0].keys())
    k_mat = first(keys, RX['mat']); k_liq = first(keys, RX['liq']); k_val = first(keys, RX['val'])
    k_dent = first(keys, RX['d_ent']); k_dsai = first(keys, RX['d_sai']); k_dgen = first(keys, RX['d_gen'])
    k_hent = first(keys, RX['h_ent']); k_hsai = first(keys, RX['h_sai'])
    k_loc = first(keys, RX['local']); k_bent = first(keys, RX['b_ent']); k_bsai = first(keys, RX['b_sai']); k_tipo = first(keys, RX['tipo'])
    out, ign = [], 0
    for r in rows:
        mat = re.sub(r'[\s\-]', '', clean(r.get(k_mat, ''))).upper() if k_mat else ''
        val = parse_valor(r.get(k_liq)) if k_liq and clean(r.get(k_liq)) else parse_valor(r.get(k_val)) if k_val else 0.0
        draw = next((clean(r.get(k)) for k in (k_dent, k_dsai, k_dgen) if k and clean(r.get(k))), '')
        data = parse_data(draw)
        if not mat or not val or not data: ign += 1; continue
        hora = parse_hora(r.get(k_hent) if k_hent else '', r.get(k_hsai) if k_hsai else '', draw)
        desc = ''
        if k_bent or k_bsai:
            be = clean(r.get(k_bent)) if k_bent else ''; bs = clean(r.get(k_bsai)) if k_bsai else ''
            desc = be if be == bs else ' → '.join(x for x in (be, bs) if x)
        if not desc and k_loc: desc = clean(r.get(k_loc))
        tipo = clean(r.get(k_tipo)) if k_tipo else ''
        if tipo and not re.match(r'^portage(m|ns)$', tipo, re.I) and tipo != desc:
            desc = f'{tipo} · {desc}' if desc else tipo
        out.append({'matricula': mat, 'data': data, 'hora': hora, 'valor': round(val, 2), 'descricao': desc[:200]})
    print(json.dumps({'linhas': out, 'ignoradas': ign, 'colunas': keys, 'total': round(sum(x['valor'] for x in out), 2)}, ensure_ascii=False))

if __name__ == '__main__':
    main(sys.argv[1])
