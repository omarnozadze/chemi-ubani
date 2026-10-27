import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const tick=()=>new Promise(r=>setImmediate(r));
function boot(saved=null){
 const elements=new Map(),storage=new Map(),timers=new Map();let timerId=0,mode='hang',oldResolve,finished=0;
 if(saved)storage.set('chemiUbaniVerifiedSession',JSON.stringify(saved));
 function el(id){if(!elements.has(id)){const classes=new Set();elements.set(id,{value:'',textContent:'',style:{},classList:{add:x=>classes.add(x),remove:x=>classes.delete(x),contains:x=>classes.has(x)},setAttribute(){},focus(){},querySelector:el,addEventListener(n,f){this[n]=f},showModal(){this.open=true},close(){this.open=false;this.closeEvent?.()}})}return elements.get(id)}
 const dialog=el('dialog');dialog.addEventListener=(n,f)=>{if(n==='close')dialog.closeEvent=f};
 const c={console,Headers,AbortController,Date,JSON,setTimeout:(fn,ms)=>{timers.set(++timerId,{fn,ms});return timerId},clearTimeout:id=>timers.delete(id),normalizePhone:v=>String(v).replace(/\D/g,'').replace(/^995/,''),SUPABASE_URL:'https://example.test',SUPABASE_ANON_KEY:'public',localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},document:{createElement:()=>dialog,body:{append(){}},getElementById:el},go(){},alert(){},reg:async()=>{},finishLogin:async()=>{finished++},logoutUser(){},applyRemoteProfile(p){c.st.phone=p.phone},st:{},nm:{value:'Test'},ph:{value:'555123456'},sbRpc:async()=>({ok:true,data:{}}),addEventListener(){}};
 c.window=c;c.fetch=async(url)=>{if(mode==='hang')return new Promise(()=>{});if(mode==='defer'){mode='ok';return new Promise(r=>oldResolve=r)}return{ok:true,json:async()=>url.endsWith('get_verified_profile')?{phone:'555123456'}:{}}};vm.createContext(c);vm.runInContext(fs.readFileSync('src/sms-auth.js','utf8'),c);
 return{c,el,storage,timers,mode:m=>mode=m,resolve:()=>oldResolve({ok:true,json:async()=>({})}),finished:()=>finished};
}
const saved={access_token:'test',refresh_token:'test-refresh',expires_at:Date.now()/1000+3600,user:{id:'test-user',phone:'995555123456'}};
const a=boot(saved);await tick();assert.equal(a.timers.size,1);for(const t of [...a.timers.values()])t.fn();await tick();assert.match(a.el('#sessionRestoreStatus').textContent,/ინტერნეტი/);assert.ok(a.storage.has('chemiUbaniVerifiedSession'),'network timeout must not delete remembered login');a.mode('ok');await a.c.restoreVerifiedLogin();assert.equal(a.finished(),1);assert.equal(a.timers.size,0);
// Cancelling an old OTP request must not mutate the new verification dialog.
const b=boot();b.mode('defer');b.el('loginPhone').value='555123456';const oldLogin=b.c.loginUser();await tick();b.el('dialog').close();await oldLogin;b.el('loginPhone').value='555987654';const newLogin=b.c.loginUser();await tick();b.el('#smsStatus').textContent='new-flow-status';b.resolve();await tick();assert.equal(b.el('#smsStatus').textContent,'new-flow-status');b.el('dialog').close();await newLogin;
// Hanging OTP request releases controls with a useful error and can be cancelled.
const d=boot();d.el('loginPhone').value='555123456';const pending=d.c.loginUser();await tick();for(const t of [...d.timers.values()])t.fn();await tick();assert.equal(d.el('#smsResend').disabled,false);assert.match(d.el('#smsStatus').textContent,/დრო ამოიწურა/);d.el('dialog').close();await pending;
console.log('PASS auth timeout preserves session and recovers; cancelled OTP cannot change a new dialog; hanging OTP unlocks retry.');
