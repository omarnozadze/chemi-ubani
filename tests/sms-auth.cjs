const fs=require('fs'),vm=require('vm'),assert=require('assert');
const elements=new Map(), storage=new Map();let finished=0,sends=0,verified=false;
function element(id){if(!elements.has(id))elements.set(id,{value:'',textContent:'',style:{},setAttribute(){},focus(){},click(){return this.onclick?.()},querySelector:element,addEventListener(name,fn){this[name]=fn},showModal(){this.open=true},close(){this.open=false;this['closeEvent']?.()}});return elements.get(id)}
const dialog=element('dialog');dialog.addEventListener=(event,fn)=>{if(event==='close')dialog.closeEvent=fn};
const ctx={console,Headers,Date,JSON,setTimeout,clearTimeout,AbortController,normalizePhone:v=>String(v).replace(/\D/g,'').replace(/^995/,''),SUPABASE_URL:'https://example.test',SUPABASE_ANON_KEY:'public',localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},document:{createElement:()=>dialog,body:{append(){}},getElementById:element},go(){},alert(){},reg:async()=>{},finishLogin:async()=>{finished++},logoutUser(){},applyRemoteProfile(p){ctx.st.phone=p.phone},st:{},nm:{value:'Test'},ph:{value:'555123456'},sbRpc:async()=>({ok:true,data:{phone:'555123456',full_name:'Test'}})};
ctx.addEventListener=()=>{};dialog.classList={add(){},remove(){},contains(){return true}};ctx.window=ctx;ctx.fetch=async(url)=>{if(url.endsWith('/otp')){sends++;return {ok:true,json:async()=>({})}}if(url.endsWith('/verify'))return {ok:verified,status:verified?200:400,json:async()=>verified?{access_token:'verified-token',refresh_token:'refresh',expires_in:3600,user:{phone:'995555123456'}}:{}};return {ok:true,json:async()=>({phone:'555123456'})}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync('src/sms-auth.js','utf8'),ctx);
const tick=()=>new Promise(r=>setImmediate(r));
(async()=>{
 element('loginPhone').value='500000000';const cancelled=ctx.loginUser();await tick();assert.equal(sends,1);assert.equal(finished,0);dialog.close();await cancelled;
 element('loginPhone').value='555123456';const login=ctx.loginUser();await tick();element('#smsCode').value='123456';await element('#smsVerify').onclick();assert.equal(finished,0);assert.equal(dialog.open,true);
 verified=true;await element('#smsVerify').onclick();await login;assert.equal(finished,1);assert(storage.has('chemiUbaniVerifiedSession'));
 console.log('PASS: demo admin requires OTP; cancel and rejected OTP cannot log in; verified OTP enters profile.');
})().catch(e=>{console.error(e);process.exitCode=1});
