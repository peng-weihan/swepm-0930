import json,subprocess,time
from pathlib import Path
R=Path('/data/swepmv2-harbor-runtime');C=R/'campaigns/v2-0930-max300-nomcp'
manifest=json.loads((C/'manifest.json').read_text());path=C/'recovery-state.json';state=json.loads(path.read_text()) if path.exists() else {}
while True:
    for row in manifest['models']:
        model=row['model']
        if model in state:continue
        job=Path(row['job_dir']);result=job/'result.json'
        if not result.exists() or not json.loads(result.read_text()).get('finished_at'):continue
        tasks=[]
        for p in job.glob('*/result.json'):
            x=json.loads(p.read_text());e=x.get('exception_info') or {};msg=e.get('exception_message','')
            if e.get('exception_type')=='RuntimeError' and ('all predefined address pools' in msg or 'declared as external, but could not be found' in msg):
                tasks.append({'path':x['config']['task']['path']})
        if not tasks:
            state[model]={'needed':False};path.write_text(json.dumps(state,indent=2)+'\n');continue
        cfg=json.loads(Path(row['config']).read_text());cfg.pop('datasets',None);cfg['tasks']=tasks;cfg['job_name']=row['job_name']+'-network-recovery';cfgpath=C/(model+'.recovery.json');cfgpath.write_text(json.dumps(cfg,indent=2)+'\n')
        cmd=['sudo','-u','ray','-H','env','PYTHONDONTWRITEBYTECODE=1','PYTHONPATH='+str(C),str(R/'bin/harbor'),'run','--config',str(cfgpath),'--env-file',str(R/'.env.deepseek-v4-flash-siflow'),'--plugin','trial_networks:TrialNetworks','--yes']
        with (C/(model+'.recovery.launch.log')).open('a') as log:
            proc=subprocess.Popen(cmd,cwd=C,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        state[model]={'needed':True,'count':len(tasks),'tasks':tasks,'pid':proc.pid,'job_dir':str(R/'jobs'/cfg['job_name'])};path.write_text(json.dumps(state,indent=2)+'\n');print('RECOVERY_STARTED',model,len(tasks),proc.pid,flush=True)
    if len(state)==len(manifest['models']):break
    time.sleep(10)
print('ALL_RECOVERIES_SCHEDULED',flush=True)
