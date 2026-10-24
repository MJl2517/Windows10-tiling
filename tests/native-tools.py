"""Native dependency smoke test. Python stdlib only; run after lifecycle.ps1."""
import json,os,subprocess,sys,tomllib
from pathlib import Path

root=Path(sys.argv[1]).resolve();state=json.loads((root/'installed.json').read_text(encoding='utf-8-sig'));paths=state['paths']
fixture=root/'native-tools';fixture.mkdir(exist_ok=True)
stream=b'0.15 0.1 0.25 rg 0 0 200 200 re f 1 1 1 rg BT /F1 22 Tf 20 100 Td (PDF preview) Tj ET'
objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream']
data=b'%PDF-1.4\n';offsets=[0]
for n,obj in enumerate(objects,1):offsets.append(len(data));data+=f'{n} 0 obj\n'.encode()+obj+b'\nendobj\n'
xref=len(data);data+=b'xref\n0 6\n0000000000 65535 f \n'+b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets[1:])+f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
pdf=fixture/'Preview test.pdf';pdf.write_bytes(data)
def run(name,*args):
    p=subprocess.run([paths[name],*map(str,args)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=40)
    assert p.returncode==0,(name,p.stderr.decode(errors='replace'));return p.stdout
results={}
for name in ['yazi','alacritty']:results[name]=run(name,'--version').decode(errors='replace').strip()
assert run('file','--mime-type','--brief',pdf).strip()==b'application/pdf'
run('poppler','-singlefile','-scale-to','800','-png',pdf,fixture/'preview')
png=fixture/'preview.png';assert png.read_bytes().startswith(b'\x89PNG')
assert run('file','--mime-type','--brief',png).strip()==b'image/png'
preview=run('chafa','--format=symbols','--colors=full','--size=50x20',png)
assert b'\x1b[' in preview and len(preview)>200
(fixture/'preview.ansi').write_bytes(preview)
config=tomllib.loads((root/'config/alacritty.toml').read_text(encoding='utf-8-sig'))
assert config['terminal']['shell']['program']==paths['yazi']
keymap=tomllib.loads((Path(state['profile'])/'AppData/Roaming/yazi/config/keymap.toml').read_text(encoding='utf-8-sig'))
keys={r['on']:r['run'] for r in reversed(keymap['mgr']['prepend_keymap']) if isinstance(r['on'],str)}
assert keys['t']==keys['е'] and keys['n']==keys['т'] and keys['N']==keys['Т']
assert 'RosePineCenter.exe' in keys['t']
results.update(pdfPreview=True,pngMime=True,russianAliases=True,profile=str(state['profile']),ok=True)
(fixture/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(results,ensure_ascii=False))
