// Readiness only. No page loading layer, page mutation, navigation or pause.
const fs=require('node:fs'),path=require('node:path');
const [identityPath,configPath]=process.argv.slice(2),folder=path.dirname(identityPath);let ws,id=0,closed=false;const pending=new Map(),sessions=new Map(),busy=new Set();
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function log(event,data={}){try{fs.appendFileSync(path.join(folder,'ready-monitor.jsonl'),JSON.stringify({utc:new Date().toISOString(),event,...data})+'\n');}catch{}}
function call(method,params={},sessionId){return new Promise((resolve,reject)=>{if(closed||!ws||ws.readyState!==WebSocket.OPEN)return reject(Error('Readiness channel closed'));const n=++id,timer=setTimeout(()=>{pending.delete(n);reject(Error('Readiness request timeout'));},1300);pending.set(n,{resolve,reject,timer});ws.send(JSON.stringify({id:n,method,params,...sessionId?{sessionId}:{}}));});}
async function attach(t){if(t.type!=='page'||busy.has(t.targetId)||!t.url.startsWith('app://-/index.html')||t.url.includes('avatar-overlay'))return;busy.add(t.targetId);try{const {sessionId}=await call('Target.attachToTarget',{targetId:t.targetId,flatten:true});sessions.set(t.targetId,{sessionId,stableSince:0});}catch{busy.delete(t.targetId);}}
function inspectReady(){const r=window.__CODEX_DREAM_SKIN_STATE__;const style=r?.styleMode==='adopted'?[...document.adoptedStyleSheets].includes(r.styleSheet):!!r?.styleNode&&document.getElementById('codex-dream-skin-style')===r.styleNode;return{themeId:r?.themeId,ready:document.documentElement?.getAttribute('data-dream-skin')==='active'&&style&&document.readyState!=='loading'&&innerWidth>250&&innerHeight>150&&!!document.querySelector('[data-ds-part="composer"],textarea,[contenteditable="true"],[role="main"]'),documentHidden:document.hidden,url:location.href};}
(async()=>{
 const config=JSON.parse(fs.readFileSync(configPath,'utf8').replace(/^\uFEFF/,'')),identity=JSON.parse(fs.readFileSync(identityPath,'utf8').replace(/^\uFEFF/,''));const u=new URL(identity.webSocketDebuggerUrl);
 if(u.protocol!=='ws:'||u.hostname!=='127.0.0.1'||Number(u.port)!==identity.port||u.pathname!=='/devtools/browser/'+identity.browserId)throw Error('Invalid verified readiness endpoint');
 ws=new WebSocket(u.href);ws.onmessage=({data})=>{let m;try{m=JSON.parse(String(data));}catch{return;}if(m.id){const p=pending.get(m.id);if(p){clearTimeout(p.timer);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}return;}if(m.method==='Target.targetCreated'||m.method==='Target.targetInfoChanged')void attach(m.params.targetInfo);if(m.method==='Target.targetDestroyed')sessions.delete(m.params.targetId);};
 ws.onclose=()=>{closed=true;for(const p of pending.values()){clearTimeout(p.timer);p.reject(Error('Browser exited'));}pending.clear();};
 await new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(Error('Readiness connect timeout')),2500);ws.onopen=()=>{clearTimeout(t);resolve();};ws.onerror=()=>{clearTimeout(t);reject(Error('Readiness websocket error'));};});
 log('connected',{pid:identity.pid});await call('Target.setDiscoverTargets',{discover:true});for(const t of (await call('Target.getTargets')).targetInfos)void attach(t);
 const expression='('+inspectReady.toString()+')()';
 let confirmed=false;const until=Date.now()+26000;
 while(!closed&&!confirmed&&Date.now()<until&&!fs.existsSync(config.pausePath)){
  for(const [targetId,item]of sessions)try{
   const result=await call('Runtime.evaluate',{expression,returnByValue:true},item.sessionId);if(result.exceptionDetails){log('evaluation-error',{text:result.exceptionDetails.text});continue;}const s=result.result?.value;
   if(!s?.ready||s.themeId!==config.themeId||!s.url.startsWith('app://-/index.html')||s.url.includes('avatar-overlay')){item.stableSince=0;continue;}
   if(!item.stableSince){item.stableSince=Date.now();continue;}if(Date.now()-item.stableSince<400)continue;
   const settled=await call('Runtime.evaluate',{expression:'new Promise(resolve=>{let done=false;const finish=(kind)=>{if(!done){done=true;resolve(kind)}};requestAnimationFrame(()=>requestAnimationFrame(()=>finish("two-animation-frames")));setTimeout(()=>finish("occluded-frame-timeout"),350)})',awaitPromise:true,returnByValue:true},item.sessionId);
   const ready={ready:true,pid:identity.pid,browserId:identity.browserId,targetId,themeId:s.themeId,documentHidden:s.documentHidden,frameSettlement:settled.result?.value,checked:new Date().toISOString()};const temp=path.join(folder,'ready.tmp');fs.writeFileSync(temp,JSON.stringify(ready));fs.renameSync(temp,path.join(folder,'ready.json'));log('theme-ready',ready);confirmed=true;break;
  }catch{}await sleep(100);
 }
 if(confirmed)await sleep(900);
 for(const item of sessions.values())try{await call('Target.detachFromTarget',{sessionId:item.sessionId});}catch{}
 if(!closed){try{await call('Target.setDiscoverTargets',{discover:false});}catch{}ws.close();}log('complete',{confirmed});
})().catch(e=>{log('error',{message:e.message});if(ws)ws.close();process.exitCode=1;});
