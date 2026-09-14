// Real Chrome smoke test. All annotations go to a disposable database.
import {spawn} from 'node:child_process';
import {mkdtemp,copyFile,readFile,writeFile,mkdir,rm,cp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const root=dirname(fileURLToPath(import.meta.url)),state=process.env.REVIEW_TEST_STATE||'/var/lib/handwriting-annotation',temp=await mkdtemp(join(tmpdir(),'handwriting-review-test-'));
let server,chrome,socket;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn){for(let i=0;i<150;i++){try{const x=await fn();if(x)return x}catch{}await delay(100)}throw Error('Timed out')}
try{
 await copyFile(join(state,'tasks.json'),join(temp,'tasks.json'));
 await cp(join(state,'evidence'),join(temp,'evidence'),{recursive:true});
 server=spawn('python3',[join(root,'review.py'),'--state',temp,'serve','--port','0']);
 let output='';server.stdout.on('data',b=>output+=b);server.stderr.on('data',b=>process.stderr.write(b));
 const url=await until(()=>output.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0]);
 chrome=spawn('/etc/profiles/per-user/tom/bin/google-chrome',['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--remote-debugging-port=0','--user-data-dir='+join(temp,'chrome'),'about:blank'],{stdio:'ignore'});
 const port=await until(async()=>Number((await readFile(join(temp,'chrome/DevToolsActivePort'),'utf8')).split('\n')[0]));
 const targets=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
 socket=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise(r=>socket.onopen=r);
 let id=0,pending=new Map(),exceptions=[];
 socket.onmessage=e=>{let m=JSON.parse(e.data);if(m.id){let p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result)}else if(m.method==='Runtime.exceptionThrown')exceptions.push(m.params)};
 const call=(method,params={})=>new Promise((resolve,reject)=>{let n=++id;pending.set(n,{resolve,reject});socket.send(JSON.stringify({id:n,method,params}))});
 const js=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};
 await call('Runtime.enable');await call('Page.enable');await call('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});await call('Page.navigate',{url});
 await until(()=>js('typeof loaded!=="undefined" && loaded'));
 assert.equal(await js('view'),'home');
 assert.equal(await js("$('review').classList.contains('hidden')"),true);
 await js("openReview('priority','pending')");
 await until(()=>js('current && img && img.complete'));
 assert.ok(await js('data.tasks.length>=107'));
 const first=await js('current.id');
 const shot=await call('Page.captureScreenshot',{format:'png'});await writeFile(join(tmpdir(),'handwriting-review-preview.png'),Buffer.from(shot.data,'base64'));
 await js(`$('literal').value='TEST ONLY';$('example_text').value='m';$('reuse').checked=true;['left','top','right','bottom'].forEach((id,i)=>{$(id).value=[10,10,40,50][i];$(id).dispatchEvent(new Event('change'))});$('form').requestSubmit()`);
 await until(async()=>((await (await fetch(url+'/api/events')).text()).trim().split('\n').length===1 && (await fetch(url+'/api/events')).headers.get('content-type')==='application/x-ndjson'));
 let events=(await (await fetch(url+'/api/events')).text()).trim().split('\n').filter(Boolean).map(JSON.parse);
 assert.equal(events.length,1);assert.equal(events[0].literal,'TEST ONLY');assert.equal(events[0].example_text,'m');
 await js('window.testReloadMarker=true');await call('Page.reload');await until(()=>js(`window.testReloadMarker!==true && typeof loaded!=="undefined" && loaded && data.tasks.find(t=>t.id===${JSON.stringify(first)})?.review?.literal==='TEST ONLY'`));
 assert.equal(await js(`data.tasks.find(t=>t.id===${JSON.stringify(first)}).review.literal`),'TEST ONLY');
 await js(`openReview('priority','all');select(data.tasks.find(t=>t.id===${JSON.stringify(first)}),true);$('reopen').click()`);
 await until(async()=>{let raw=await (await fetch(url+'/api/events')).text();return raw.trim().split('\n').length===2});
 events=(await (await fetch(url+'/api/events')).text()).trim().split('\n').map(JSON.parse);assert.equal(events[1].action,'reopened');
 await until(()=>js('!saving'));
 // Isolate one pending priority item in the browser, with all writes still in the disposable server.
 await js(`data.tasks=[data.tasks.find(t=>t.id===${JSON.stringify(first)})];openReview('priority','pending')`);
 await until(()=>js('img && img.complete'));
 await js("$('literal').value='TEST FINAL';$('reuse').checked=false;save('resolved')");
 await until(()=>js("!saving && current===null"));
 assert.equal(await js("$('review-empty').classList.contains('hidden')"),false);
 assert.equal(await js("$('empty-title').textContent"),"You're all caught up");
 assert.equal(await js("document.querySelector('.form-pane').classList.contains('hidden')"),true);
 await js("$('empty-home').click()");
 assert.equal(await js("$('home-title').textContent"),"You're all caught up");
 // A deferred item remains open, including crossed-out text.
 await js("data.tasks[0].review={action:'deferred'};data.tasks[0].cancelled=true;renderHome()");
 assert.notEqual(await js("$('home-title').textContent"),"You're all caught up");
 assert.ok((await js("$('home-summary').textContent")).includes('1 set aside'));
 await js("openReview('all','deferred')");
 assert.equal(await js('visible().length'),1);
 // Completing priority does not falsely clear the Qwen backlog.
 await js("data.tasks[0].review={action:'resolved'};data.tasks.push({...data.tasks[0],id:'fixture-qwen',origin:'qwen_uncertainty',review:null});showHome(true)");
 assert.equal(await js("$('home-title').textContent"),'Priority review complete');
 const homeShot=await call('Page.captureScreenshot',{format:'png'});await writeFile(join(tmpdir(),'handwriting-menu-preview.png'),Buffer.from(homeShot.data,'base64'));
 assert.ok((await js("$('home-summary').textContent")).includes('1 item needs review'));
 await js("openReview('priority','pending')");
 assert.equal(await js('current'),null);
 assert.equal(await js("$('empty-title').textContent"),'Priority review complete');
 await js("openReview('all','pending');$('search').value='NO SUCH READING';$('search').dispatchEvent(new Event('input'))");
 assert.equal(await js('current'),null);
 assert.equal(await js("$('empty-title').textContent"),'No items in this view');
 // Whole-capture review keeps multiline text and capture completeness visible.
 await js("data.tasks=[{...data.tasks[0],id:'fixture-page',origin:'page_review',raw:'first line\\nsecond line',transcription:'first line\\nsecond line',review:null,capture_completeness:'unknown'}];showHome(true);openReview('page_review','pending')");
 assert.equal(await js("$('literal').tagName"),'TEXTAREA');
 assert.equal(await js("$('literal').rows"),18);
 assert.ok((await js("$('notice').textContent")).includes('Capture completeness: unknown'));
 assert.equal(await js("$('literal').value"),'first line\nsecond line');
 await js("data.tasks=[];showHome(true)");
 assert.equal(await js("$('home-title').textContent"),"You're all caught up");
 assert.equal(exceptions.length,0);
 console.log('Chrome passed: home, queue, image/crop/save, reload persistence, revisions, last-save empty state, deferred/crossed-out work, priority completion with Qwen backlog, filtered empty and zero tasks. Writes isolated.');
}finally{
 if(socket)socket.close();if(chrome){chrome.kill('SIGTERM');await delay(500)}if(server)server.kill('SIGTERM');await delay(200);await rm(temp,{recursive:true,force:true,maxRetries:5});
}
