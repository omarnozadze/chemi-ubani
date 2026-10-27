const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('src/sms-auth.js','utf8');
const saved={access_token:'old',refresh_token:'refresh',expires_at:1,user:{phone:'+995555123456'}};
function setup(storage=new Map(),fetchImpl){
 const elements=new Map();const el=id=>{if(!elements.has(id)){const classes=new Set();elements.set(id,{value:'',style:{},classList:{add:c=>classes.add(c),remove:c=>classes.delete(c),contains:c=>classes.has(c)},setAttribute(){},querySelector:el,addEventListener(){},showModal(){},close(){},focus(){}})}return elements.get(id)};
 let finished=0,screen='';const listeners={};
 const ctx={console,Headers,Date,JSON,setTimeout,normalizePhone:v=>String(v).replace(/\D/g,'').replace(/^995/,''),SUPABASE_URL:'https://test',SUPABASE_ANON_KEY:'anon',localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},document:{createElement:()=>el('element'+elements.size),body:{append(){}},getElementById:el},go:s=>screen=s,alert(){},reg:async()=>{},finishLogin:async()=>{finished++;screen='home'},logoutUser(){screen='welcome';ctx.st.phone=''},applyRemoteProfile:p=>{ctx.st.phone=p.phone},st:{},nm:{value:''},ph:{value:''},sbRpc:async()=>({ok:true}),addEventListener:(n,f)=>listeners[n]=f,fetch:fetchImpl};ctx.window=ctx;
 vm.createContext(ctx);vm.runInContext(source,ctx);return {ctx,storage,elements,listeners,get finished(){return finished},get screen(){return screen}};
}
const reply=(data,status=200)=>({ok:status<400,status,json:async()=>data});
const tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 const storage=new Map([['chemiUbaniVerifiedSession',JSON.stringify(saved)]]);let refreshes=0;
 const fetchOk=async url=>url.includes('/token?')?(refreshes++,reply({...saved,access_token:'new',refresh_token:'rotated',expires_in:3600,expires_at:Date.now()/1000+3600})):reply({phone:'555123456'});
 let app=setup(storage,fetchOk);await app.ctx.restoreVerifiedLogin();assert.equal(app.finished,1);assert.equal(refreshes,1);assert.equal(JSON.parse(storage.get('chemiUbaniVerifiedSession')).refresh_token,'rotated');
 // New JS context simulates app/process restart with the same persistent storage.
 app=setup(storage,fetchOk);await app.ctx.restoreVerifiedLogin();assert.equal(app.screen,'home');assert.equal(refreshes,1);
 app=setup(storage,async()=>{throw Error('offline')});await app.ctx.restoreVerifiedLogin();assert(storage.has('chemiUbaniVerifiedSession'));assert.equal(app.finished,0);assert.equal(app.elements.get('#sessionRestoreRetry').classList.contains('hide'),false);assert.equal(app.elements.get('#sessionRestoreSpinner').classList.contains('hide'),true);
 app.ctx.fetch; // retry uses original fetch, simulate network availability via mutable stub below.
 let offline=true;app=setup(storage,async(...args)=>{if(offline)throw Error('offline');return fetchOk(...args)});await app.ctx.restoreVerifiedLogin();offline=false;await app.ctx.restoreVerifiedLogin();assert.equal(app.finished,1);
 // The receipt endpoint gets the session token; unrelated external fetches do not.
 let checkedHeaders;app=setup(storage,async(url,init)=>{if(url.includes('/functions/')){checkedHeaders=init.headers;return reply({checked:0})}return fetchOk(url)});await app.ctx.restoreVerifiedLogin();await app.ctx.fetch('https://test/functions/v1/activity-push',{method:'POST',body:'{}'});assert.equal(checkedHeaders.get('Authorization'),'Bearer new');
 // Logout must clear immediately even when server cleanup never answers.
 app=setup(storage,async url=>url.includes('unregister')?new Promise(()=>{}):fetchOk(url));await app.ctx.restoreVerifiedLogin();app.ctx.logoutUser();assert(!storage.has('chemiUbaniVerifiedSession'));assert.equal(app.screen,'welcome');
 // A late refresh response must not resurrect a logged-out session.
 storage.set('chemiUbaniVerifiedSession',JSON.stringify(saved));let resolveRefresh;
 app=setup(storage,url=>url.includes('/token?')?new Promise(r=>resolveRefresh=r):Promise.resolve(reply({})));await tick();assert.equal(app.elements.get('#sessionRestoreRetry').classList.contains('hide'),true);assert.equal(app.elements.get('#sessionRestoreLogout').classList.contains('hide'),true);assert.equal(app.elements.get('#sessionRestoreSpinner').classList.contains('hide'),false);app.ctx.logoutUser();resolveRefresh(reply({...saved,access_token:'late',refresh_token:'late',expires_in:3600}));await tick();assert(!storage.has('chemiUbaniVerifiedSession'));assert.equal(app.finished,0);
 storage.set('chemiUbaniVerifiedSession',JSON.stringify(saved));app=setup(storage,async()=>reply({},400));await app.ctx.restoreVerifiedLogin();assert(!storage.has('chemiUbaniVerifiedSession'));assert.equal(app.screen,'welcome');
 console.log('PASS: restart restore, token rotation, offline preservation/retry, immediate offline logout, no late-refresh resurrection, invalid session rejected.');
})().catch(e=>{console.error(e);process.exitCode=1});
