#!/usr/bin/env python3
"""
FleetPay — converte o export MyPRIO (Transações_Detalhadas .csv/.xlsx) em JSON para fp_importar_prio().

Uso:  python3 -I parse_prio.py <ficheiro>  >  linhas.json
Saída: {"linhas":[{"matricula","data","valor","litros","estacao","duracao_min","card_code","tipo"}, ...],
        "ignoradas": n, "colunas": [...], "total": x}

Replica a deteção de colunas de processarUploadPRIO() do admin.html:
  • matrícula: matr | viatura | veículo | placa | MobileCard | MobileRegistration | License Plate
  • data: Data | Date | StartDate | EntryDate | transac… | opera…   (US M/D/YYYY h:mm:ss AM/PM, PT D/M/YYYY, ISO)
  • valor: TotalValueWithTaxes > Total | Valor | Montante | ChargingTotalValue > outros (valor/montante/amount sem iva/desc/price)
  • litros/energia: Litros | Quant | Qtd | Energy | Energia
  • detalhe E-Charge: IdChargingStation, TotalDuration, CardCode; tipo = electrico se houver Energy/estação
"""
import csv, io, json, re, sys

RX = {
    'mat':  re.compile(r'matr|viatura|ve[ií]culo|placa|mobilecard|mobileregistration|license\s*plate|licenseplate', re.I),
    'data': re.compile(r'^data$|^date$|^dia$|transac|opera|^dt|startdate|start\s*date|entrydate|entry\s*date', re.I),
    'v_iva': re.compile(r'totalvaluewithtaxes|total\s*value\s*with\s*taxes', re.I),
    'v_tot': re.compile(r'^total$|^valor$|^montante$|chargingtotalvalue|charging\s*total', re.I),
    'v_out': re.compile(r'(valor|montante|pre[çc]o|euro|amount)', re.I),
    'v_out_excl': re.compile(r'iva|imposto|desc|duration|energy|energia|price', re.I),
    'lit':  re.compile(r'(^litros?$|quant|qtd|^energy$|^energia$)', re.I),
    'lit_excl': re.compile(r'pre[çc]o|valor', re.I),
    'est':  re.compile(r'idchargingstation|id\s*charging\s*station|estacao|esta[çc][ãa]o|station', re.I),
    'dur':  re.compile(r'totalduration|total\s*duration|dura[çc][ãa]o|duration', re.I),
    'card': re.compile(r'^cardcode$|card\s*code', re.I),
}

def first(keys, rx, excl=None):
    for k in keys:
        if rx.search(k) and not (excl and excl.search(k)): return k
    return None

def clean(v): return '' if v is None else str(v).strip()

def num(s):
    s = clean(s).replace('€', '').replace(' ', '')
    if not s: return None
    if ',' in s and '.' in s: s = s.replace('.', '').replace(',', '.')
    else: s = s.replace(',', '.')
    s = re.sub(r'[^\d.\-]', '', s)
    try: return float(s)
    except ValueError: return None

def parse_data(s):
    s = clean(s)
    m = re.match(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})', s)
    if m: return f'{m[1]}-{int(m[2]):02d}-{int(m[3]):02d}'
    m = re.match(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})', s)
    if m:
        a, b, y = int(m[1]), int(m[2]), m[3]
        if a > 12: d, mo = a, b
        elif b > 12: d, mo = b, a
        elif re.search(r'\b(am|pm)\b', s, re.I): d, mo = b, a   # US M/D (export PRIO E-Charge)
        else: d, mo = a, b
        return f'{y}-{mo:02d}-{d:02d}'
    return None

def read_rows(path):
    if path.lower().endswith(('.xlsx', '.xls', '.xlsm')):
        import openpyxl, warnings
        warnings.filterwarnings('ignore')
        ws = openpyxl.load_workbook(path, data_only=True).worksheets[0]
        table = [[('' if c is None else (c.strftime('%Y-%m-%d %H:%M:%S') if hasattr(c, 'strftime') else str(c))) for c in r] for r in ws.iter_rows(values_only=True)]
    else:
        raw = open(path, 'rb').read()
        for enc in ('utf-8-sig', 'utf-8', 'cp1252', 'latin-1'):
            try: text = raw.decode(enc); break
            except UnicodeDecodeError: continue
        sample = text[:4000]
        delim = ';' if sample.count(';') > sample.count(',') else ('\t' if sample.count('\t') > sample.count(',') else ',')
        table = list(csv.reader(io.StringIO(text), delimiter=delim))
    hidx = next((i for i, r in enumerate(table) if any(RX['mat'].search(str(c)) for c in r)), None)
    if hidx is None: return [], []
    headers = [str(h).strip().lower() for h in table[hidx]]
    rows = [{headers[i]: (r[i] if i < len(r) else '') for i in range(len(headers)) if headers[i]}
            for r in table[hidx + 1:] if any(clean(c) for c in r)]
    return headers, rows

def main(path):
    headers, rows = read_rows(path)
    if not rows:
        print(json.dumps({'linhas': [], 'ignoradas': 0, 'colunas': headers, 'erro': 'sem linhas / cabeçalho não encontrado'})); return
    keys = list(rows[0].keys())
    k_mat = first(keys, RX['mat']); k_data = first(keys, RX['data'])
    k_val = first(keys, RX['v_iva']) or first(keys, RX['v_tot']) or first(keys, RX['v_out'], RX['v_out_excl'])
    k_lit = first(keys, RX['lit'], RX['lit_excl']); k_est = first(keys, RX['est']); k_dur = first(keys, RX['dur']); k_card = first(keys, RX['card'])
    eletrico = bool(k_est) or bool(re.search(r'energia|^energy$|chargingstation', '|'.join(keys), re.I))
    out, ign = [], 0
    for r in rows:
        mat = re.sub(r'[\s\-]', '', clean(r.get(k_mat))).upper() if k_mat else ''
        val = num(r.get(k_val)) if k_val else None
        data = parse_data(r.get(k_data)) if k_data else None
        if not mat or not val or val <= 0 or not data: ign += 1; continue
        out.append({
            'matricula': mat, 'data': data, 'valor': round(val, 2),
            'litros': num(r.get(k_lit)) if k_lit else None,
            'estacao': clean(r.get(k_est)) or None if k_est else None,
            'duracao_min': num(r.get(k_dur)) if k_dur else None,
            'card_code': clean(r.get(k_card)) or None if k_card else None,
            'tipo': 'electrico' if eletrico else 'combustivel',
        })
    print(json.dumps({'linhas': out, 'ignoradas': ign, 'colunas': keys, 'total': round(sum(x['valor'] for x in out), 2)}, ensure_ascii=False))

if __name__ == '__main__':
    main(sys.argv[1])
