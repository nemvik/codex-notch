#!/usr/bin/env python3
# Disposable local IPC fixtures; no user Codex data is read or modified.
import socket,struct,json,sqlite3,tempfile,subprocess,threading,os,time,shutil
from pathlib import Path
binary=str(Path(__file__).resolve().parent.parent/'build/Codex Island.app/Contents/MacOS/CodexIsland')
def run(case):
 root=Path(tempfile.mkdtemp(prefix='island-test-',dir='/private/tmp'));(root/'ipc').mkdir(mode=0o700)
 db=sqlite3.connect(root/'state_5.sqlite');db.executescript("CREATE TABLE threads (id TEXT,source TEXT,archived INTEGER,updated_at INTEGER); INSERT INTO threads VALUES ('fixture','vscode',0,1);");db.close()
 server=socket.socket(socket.AF_UNIX);server.bind(str(root/'ipc/ipc.sock'));os.chmod(root/'ipc/ipc.sock',0o600);server.listen(1)
 errors=[];follow_count=[]
 def serve():
  try:
   peer,_=server.accept();peer.settimeout(14)
   def send(v):
    body=json.dumps(v).encode();raw=struct.pack('<I',len(body))+body
    peer.sendall(raw[:2]);peer.sendall(raw[2:])
   def recv():
    head=b''
    while len(head)<4:
     b=peer.recv(4-len(head))
     if not b:return None
     head+=b
    length=struct.unpack('<I',head)[0];body=b''
    while len(body)<length:body+=peer.recv(length-len(body))
    return json.loads(body)
   def state(rev,status='active',flags=[]):
    return {'type':'broadcast','method':'thread-stream-state-changed','version':99 if case=='bad-version' else 11,'sourceClientId':'fixture-owner','params':{'hostId':'local','conversationId':'fixture','change':{'type':'snapshot','revision':rev,'conversationState':{'id':'fixture','title':'Fixture','updatedAt':1000,'threadRuntimeStatus':{'type':status,'activeFlags':flags},'requests':[],'turns':[]}}}}
   while True:
    m=recv()
    if m is None:break
    if m.get('method')=='initialize':send({'type':'response','requestId':m['requestId'],'method':'initialize','resultType':'success','result':{'clientId':'fixture-observer'}})
    elif m.get('method')=='thread-stream-following-changed':
     follow_count.append(m)
     if len(follow_count)==1:
      send(state(1));time.sleep(.4)
      if case=='gap':send({'type':'broadcast','method':'thread-stream-state-changed','version':11,'sourceClientId':'fixture-owner','params':{'hostId':'local','conversationId':'fixture','change':{'type':'patches','baseRevision':2,'revision':3,'patches':[]}}})
      elif case=='live':send(state(2,flags=['waitingOnUserInput']))
     elif case=='gap':send(state(3,flags=['waitingOnUserInput']))
    elif m.get('type')=='request':raise AssertionError('Observer attempted an unexpected request: '+m.get('method',''))
   peer.close()
  except Exception as e:errors.append(str(e))
 thread=threading.Thread(target=serve,daemon=True);thread.start()
 env=dict(os.environ,CODEX_HOME=str(root))
 result=subprocess.run([binary,'--diagnose'],env=env,text=True,capture_output=True,timeout=20)
 thread.join(timeout=2);server.close();shutil.rmtree(root)
 assert not errors,errors
 print(case,result.returncode,result.stdout.strip())
 if case=='bad-version':assert result.returncode==1 and 'connection=incompatible' in result.stdout
 else:assert result.returncode==0 and 'waiting=1' in result.stdout
 if case=='gap':assert len(follow_count)>=2 and 'Obnovuji živý stav' in result.stdout
for case in ['live','gap','bad-version']:run(case)
print('All 3 desktop adapter scenarios passed.')
