import fs from 'node:fs';import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const {indexedDB}=await import(process.env.INDEXEDDB_MODULE||'fake-indexeddb');
const html=fs.readFileSync('prototype-v4.28.0.html','utf8'),wait=()=>new Promise(r=>setTimeout(r,40)),errors=[];
const id='11111111-1111-4111-8111-111111111111',peer='22222222-2222-4222-8222-222222222222';
async function launch(phone='511111111'){
 const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(e.type==='unhandled-exception')errors.push(e.message)});
 const dom=new JSDOM(html,{url:'https://chemi-ubani.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.indexedDB=indexedDB;w.Headers=Headers;w.fetch=async()=>({ok:false,status:503,json:async()=>({}),text:async()=>''});w.alert=()=>{};w.confirm=()=>true;w.HTMLElement.prototype.scrollIntoView=function(){};w.navigator.geolocation={getCurrentPosition:(_,f)=>f()};}});
 const w=dom.window;await wait();w.testRPC=async()=>({ok:true,data:[]});w.eval(`st.phone='${phone}';sbRpc=(...args)=>window.testRPC(...args);refreshMessagingBadge=()=>{};refreshCloudNotificationBadge=()=>{};`);return dom;
}
let dom=await launch(),w=dom.window,saved;
w.testRPC=async(n,a)=>{if(n==='get_privacy_preferences')return {ok:true,data:{messages:'friends'}};if(n==='set_privacy_preferences'){saved=a;return {ok:true,data:{messages:a.p_messages}}}return {ok:true,data:[]}};
w.go('privacySettings');await wait();const select=w.document.querySelector('#privacySettings select');assert.equal(select.value,'friends');select.value='nobody';const save=[...w.document.querySelectorAll('#privacySettings button')].find(b=>b.textContent==='შენახვა');await save.onclick();assert.equal(saved.p_messages,'nobody');
w.openPostCreator();const text=w.document.getElementById('newPostText');text.value='ჩემი მონახაზი';text.dispatchEvent(new w.Event('input'));text.value='';w.openPostCreator();assert.equal(text.value,'ჩემი მონახაზი');w.logoutUser();assert.equal(w.localStorage.getItem('post-draft-v428:511111111'),null);assert.equal(text.value,'');dom.window.close();assert.deepEqual(errors,[]);console.log('PASS persisted privacy selection, text draft reopen and logout cleanup');
