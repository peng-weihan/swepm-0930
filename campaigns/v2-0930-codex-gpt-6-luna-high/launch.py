import json,os,subprocess
from pathlib import Path
R=Path('/data/swepmv2-harbor-runtime')
C=R/'campaigns/v2-0930-codex-gpt-6-luna-high'
m=json.loads((C/'manifest.json').read_text())
assert not m.get('full_started'), 'Campaign already started'
s=R/'jobs'/m['smoke_job_name']
assert json.loads((s/'result.json').read_text()).get('finished_at'), 'Smoke still running'
results=list(s.glob('*/result.json'));assert len(results)==1
assert not json.loads(results[0].read_text()).get('exception_info')
events=[]
for f in s.glob('*/agent/codex.txt'):
    for line in f.read_text().splitlines():
        try: events.append(json.loads(line))
        except ValueError: pass
assert any(e.get('type')=='turn.completed' for e in events)
assert not any(e.get('type') in ['error','turn.failed'] or e.get('item',{}).get('type')=='error' for e in events)
assert any(e.get('item',{}).get('type')=='command_execution' and e['item'].get('exit_code')==0 and e['item'].get('aggregated_output')=='LUNA_HIGH_HARBOR_OK' for e in events)
context=[]
for f in s.glob('*/agent/sessions/*/*/*/*.jsonl'):
    for line in f.read_text().splitlines():
        e=json.loads(line)
        if e.get('type')=='turn_context': context.append(e['payload'])
assert context and all(x.get('model')=='gpt-6-luna' and x.get('effort')=='high' for x in context)
assert not Path(m['job_dir']).exists(), 'Job directory already exists'
env=os.environ.copy();env['PYTHONPATH']=str(C)
for k in ['OPENAI_API_KEY','OPENAI_BASE_URL','CODEX_API_KEY','ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','ANTHROPIC_BASE_URL']:
    env.pop(k,None)
cmd=[str(R/'bin/harbor'),'run','-c',str(C/'full.json'),'--plugin','trial_networks:TrialNetworks']
subprocess.run(cmd+['--dry-run'],env=env,cwd=C,check=True)
with (C/'full.launch.log').open('w') as log:
    p=subprocess.Popen(cmd,env=env,cwd=C,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
m.update(full_started=True,launcher_pid=p.pid,smoke_tool_execution_verified=True)
(C/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print(json.dumps(m,indent=2))
