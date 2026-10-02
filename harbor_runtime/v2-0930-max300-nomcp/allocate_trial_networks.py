import ipaddress,json,re,subprocess,time
from pathlib import Path
C=Path('/data/swepmv2-harbor-runtime/campaigns/v2-0930-max300-nomcp')
manifest=json.loads((C/'manifest.json').read_text())
rows=manifest['models'];known=set();allocated=json.loads((C/'allocated-networks.json').read_text()) if (C/'allocated-networks.json').exists() else {};pool=iter(ipaddress.ip_network('10.253.0.0/18').subnets(new_prefix=28))
existing=json.loads(subprocess.check_output(['docker','network','inspect',*subprocess.check_output(['docker','network','ls','-q'],text=True).split()],text=True))
used=[ipaddress.ip_network(p['Subnet']) for n in existing for p in (n['IPAM'].get('Config') or []) if p.get('Subnet') and ':' not in p['Subnet']]
while True:
    rows=json.loads((C/'manifest.json').read_text())['models']
    known=set(subprocess.check_output(['docker','network','ls','--format','{{.Name}}'],text=True).splitlines())
    finished=0
    for row in rows:
        job=Path(row['job_dir']);p=job/'result.json'
        if p.exists() and json.loads(p.read_text()).get('finished_at'):
            finished+=1
            continue
        for d in job.iterdir():
            if not d.is_dir() or (d/'result.json').exists():continue
            project=re.sub(r'[^a-z0-9_-]','-',(d.name+'__env').lower());network=project+'_default'
            if network in known:continue
            check=subprocess.run(['docker','network','inspect',network],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            if check.returncode==0:
                known.add(network);continue
            subnet=next(pool)
            while any(subnet.overlaps(u) for u in used):subnet=next(pool)
            command=['docker','network','create','--driver','bridge','--subnet',str(subnet),'--label','com.docker.compose.project='+project,'--label','com.docker.compose.network=default','--label','swepm.campaign=v2-0930-max300-nomcp',network]
            result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            if result.returncode==0:
                known.add(network);used.append(subnet);allocated[network]=str(subnet);(C/'allocated-networks.json').write_text(json.dumps(allocated,indent=2)+'\n');print('ALLOCATED',network,str(subnet),flush=True)
            else:print('CREATE_ERROR',network,result.stderr.strip(),flush=True)
    if finished==len(rows):break
    time.sleep(0.2)
print('ALL_JOBS_FINISHED',flush=True)
