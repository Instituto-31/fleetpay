import csv, json, sys, re, io
path = sys.argv[1]
raw = open(path, 'rb').read().decode('utf-8-sig')
rows = list(csv.DictReader(io.StringIO(raw)))
def norm(s): return s.strip().lower()
def num(v):
    try: return float(str(v).replace(',', '.').replace('€','').strip() or 0)
    except: return 0.0
out = {}
for r in rows:
    k = {norm(a): b for a, b in r.items()}
    nome = f"{k.get('nome próprio do motorista','')} {k.get('apelido do motorista','')}".strip()
    if not nome: continue
    uuid = k.get('uuid do motorista','')
    pago = num(k.get('pago a si', 0))
    gorj = 0.0
    for a, b in k.items():
        if 'gratifica' in a: gorj += num(b)
    d = out.setdefault(nome, {'uuid': uuid, 'nome': nome, 'pago': 0.0, 'gorjeta': 0.0})
    d['pago'] += pago; d['gorjeta'] += gorj
    if uuid and not d['uuid']: d['uuid'] = uuid
m = re.search(r'(\d{4})(\d{2})(\d{2})', path.split('/')[-1])
semana = f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else None
print(json.dumps({'semana': semana, 'linhas': [dict(x, pago=round(x['pago'],2), gorjeta=round(x['gorjeta'],2)) for x in out.values()]}, ensure_ascii=False))
