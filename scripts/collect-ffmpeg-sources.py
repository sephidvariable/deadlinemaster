#!/usr/bin/env python3
"""Collect hash-verified upstream sources recorded by installed package SBOMs.
This is evidence collection, not an automatic declaration of GPL compliance.
Review formula patches/resources and build dependencies before distributing.
"""
import concurrent.futures, hashlib, json, subprocess, sys, re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
runtime=root/'build/FFmpegFull'
out=root/'build/FFmpegSources';out.mkdir(exist_ok=True)
entries=json.loads((runtime/'provenance/sources-required.json').read_text())
proxy_args=[]
if '--system-proxy' in sys.argv:
    settings=subprocess.check_output(['scutil','--proxy'],text=True)
    host=re.search(r'HTTPSProxy\s*:\s*(\S+)',settings)
    port=re.search(r'HTTPSPort\s*:\s*(\d+)',settings)
    enabled=re.search(r'HTTPSEnable\s*:\s*1',settings)
    if not (enabled and host and port): raise SystemExit('No system HTTPS proxy configured')
    proxy_args=['--proxy','http://'+host.group(1)+':'+port.group(1)]
def collect(entry):
    source=entry['source'];url=source.get('downloadLocation','')
    sha=next((c['checksumValue'] for c in source.get('checksums',[]) if c['algorithm']=='SHA256'),None)
    result={'package':entry['installed'],'url':url,'sha256':sha}
    if not url.startswith('https://') or not sha:
        return result|{'status':'needs manual source retrieval'}
    dest=out/(entry['installed']+'-'+sha[:12]+'.source')
    if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest()==sha:
        return result|{'status':'verified','file':dest.name}
    temporary=dest.with_suffix('.download')
    p=subprocess.run(['curl',*proxy_args,'--fail','--location','--connect-timeout','5','--max-time','25','--silent','--show-error','--output',str(temporary),url],capture_output=True,text=True)
    if p.returncode:
        temporary.unlink(missing_ok=True)
        return result|{'status':'download failed','reason':p.stderr[-300:]}
    if hashlib.sha256(temporary.read_bytes()).hexdigest()!=sha:
        temporary.unlink(missing_ok=True)
        return result|{'status':'checksum mismatch'}
    temporary.replace(dest)
    return result|{'status':'verified','file':dest.name}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    results=list(pool.map(collect,entries))
report={'redistribution_ready':False,'reason':'Review complete corresponding sources, formula patches/resources, build dependencies and notices before release.','sources':results}
(out/'source-status.json').write_text(json.dumps(report,indent=2))
print(f"Verified {sum(r['status']=='verified' for r in results)}/{len(results)} source archives. See {out/'source-status.json'}")
