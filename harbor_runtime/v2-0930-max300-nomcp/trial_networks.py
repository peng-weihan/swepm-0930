import asyncio,fcntl,ipaddress,json,re,subprocess
from pathlib import Path
C=Path('/data/swepmv2-harbor-runtime/campaigns/v2-0930-max300-nomcp')

def ensure_network(trial_name):
    project=re.sub(r'[^a-z0-9_-]','-',(trial_name+'__env').lower())
    name=project+'_default'
    if subprocess.run(['docker','network','inspect',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:return
    with (C/'network-plugin.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        p=C/'network-plugin-state.json';state=json.loads(p.read_text()) if p.exists() else {'next':0,'networks':{}}
        if subprocess.run(['docker','network','inspect',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:return
        n=state['next'];assert n<1024
        subnet=str(ipaddress.ip_network((int(ipaddress.ip_address('10.253.128.0'))+16*n,28)))
        cmd=['docker','network','create','--driver','bridge','--subnet',subnet,'--label','com.docker.compose.project='+project,'--label','com.docker.compose.network=default','--label','swepm.campaign=v2-0930-max300-nomcp',name]
        subprocess.run(cmd,check=True,stdout=subprocess.DEVNULL,timeout=30)
        state['next']=n+1;state['networks'][name]=subnet;p.write_text(json.dumps(state,indent=2)+'\n')

class TrialNetworks:
    async def on_job_start(self,job):
        job.on_trial_started(self.on_trial_start)
    async def on_trial_start(self,event):
        await asyncio.to_thread(ensure_network,event.trial_name)
    async def on_job_end(self,result):
        pass
