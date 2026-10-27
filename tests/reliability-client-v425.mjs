import fs from 'node:fs';import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const {indexedDB}=await import(process.env.INDEXEDDB_MODULE||'fake-indexeddb');
const html=fs.readFileSync('prototype-v4.25.0.html','utf8'),wait=()=>new Promise(r=>setTimeout(r,40)),errors=[];
const id='11111111-1111-4111-8111-111111111111',peer='22222222-2222-4222-8222-222222222222';
async function launch(phone='511111111'){
 const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(e.type==='unhandled-exception')errors.push(e.message)});
 const dom=new JSDOM(html,{url:'https://chemi-ubani.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.indexedDB=indexedDB;w.Headers=Headers;w.fetch=async()=>({ok:false,status:503,json:async()=>({}),text:async()=>''});w.alert=()=>{};w.confirm=()=>true;w.HTMLElement.prototype.scrollIntoView=function(){};w.navigator.geolocation={getCurrentPosition:(_,f)=>f()};}});
 const w=dom.window;await wait();w.testRPC=async()=>({ok:true,data:[]});w.eval(`st.phone='${phone}';sbRpc=(...args)=>window.testRPC(...args);refreshMessagingBadge=()=>{};refreshCloudNotificationBadge=()=>{};`);return dom;
}
let dom=await launch(),w=dom.window,attempts=[];await w.openCloudChat(id,'Group');
w.testRPC=async(n,a)=>{if(n==='send_chat_message_verified'){attempts.push(a);return{ok:false}}return{ok:true,data:[]}};
w.document.getElementById('mi').value='durable outgoing';await w.send();const firstId=attempts[0].p_client_id;
const input=w.document.getElementById('mi');input.value='durable next draft';input.dispatchEvent(new w.Event('input'));await wait();assert.equal((await w.chatDisk.get('511111111')).outbox[0].body,'durable outgoing');dom.window.close();
// A fresh WebView instance with the same device database restores both independent values.
dom=await launch();w=dom.window;await w.openCloudChat(id,'Group');assert.match(w.document.querySelector('.pendingMessage').textContent,/durable outgoing/);assert.equal(w.document.getElementById('mi').value,'durable next draft');
w.testRPC=async(n,a)=>{if(n==='send_chat_message_verified'){attempts.push(a);return{ok:true,data:{ok:true}}}return{ok:true,data:[]}};
w.document.querySelector('.pendingMessage button').click();await wait();assert.equal(attempts[1].p_client_id,firstId);assert.equal(w.document.querySelector('.pendingMessage'),null);assert.equal(w.document.getElementById('mi').value,'durable next draft');
await w.openCloudChat(peer,'Other');assert.equal(w.document.getElementById('mi').value,'');await w.openCloudChat(id,'Group');assert.equal(w.document.getElementById('mi').value,'durable next draft');
// Cached pagination must keep the older-page button when reopening a conversation.
const page=Array.from({length:50},(_,i)=>({id:String(i+1).padStart(36,'0'),created_at:'2026-09-15T12:00:00Z',body:'line '+i,sender_phone:'522222222',sender_name:'Peer'}));
w.testRPC=async(n,a)=>({ok:true,data:n==='conversation_page'?(a.p_before?[]:page):[]});await w.loadCloudChatMessages();let older=[...w.document.querySelectorAll('#chat button')].find(b=>b.textContent==='ძველი შეტყობინებები');assert.equal(older.hidden,false);await w.openCloudChat(peer,'Other');await w.openCloudChat(id,'Group');assert.equal(older.hidden,false);older.click();await wait();assert.equal(older.hidden,true);
// Category settings submit structured fields, including the overnight Georgia window.
const prefs={enabled:true,messages:false,daily_photo:true,reactions:true,friends:true,hot_news:true,services:true,other:true,quiet_enabled:true,quiet_start:1380,quiet_end:480};let saved;
w.testRPC=async(n,a)=>{if(n==='get_notification_preferences')return{ok:true,data:prefs};if(n==='set_notification_preferences'){saved=a.p_settings;return{ok:true,data:saved}}return{ok:true,data:[]}};w.eval('requestPushFoundation=()=>{}');w.go('notificationSettings');await wait();assert.equal(w.document.getElementById('pref-messages').checked,false);assert.equal(w.document.getElementById('pref-quiet_start').value,'23:00');[...w.document.querySelectorAll('#notificationSettings button')].find(b=>b.textContent==='შენახვა').click();await wait();assert.equal(saved.messages,false);assert.equal(saved.quiet_start,1380);
w.logoutUser();await wait();assert.equal(await w.chatDisk.get('511111111'),undefined);dom.window.close();
await indexedDB.databases();dom=await launch('522222222');w=dom.window;await w.openCloudChat(id,'Group');assert.equal(w.document.querySelector('.pendingMessage'),null);assert.equal(w.document.getElementById('mi').value,'');dom.window.close();assert.deepEqual(errors,[]);
console.log('PASS: restart restores outbox and draft; retry UUID unchanged; conversation isolation; older-page reopen; settings; explicit logout clears device records.');
