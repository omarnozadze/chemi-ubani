import fs from 'node:fs';import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const {indexedDB}=await import(process.env.INDEXEDDB_MODULE||'fake-indexeddb');
const html=fs.readFileSync('prototype-v4.29.0.html','utf8'),wait=()=>new Promise(r=>setTimeout(r,40)),errors=[];
const id='11111111-1111-4111-8111-111111111111',peer='22222222-2222-4222-8222-222222222222';
async function launch(phone='511111111'){
 const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(e.type==='unhandled-exception')errors.push(e.message)});
 const dom=new JSDOM(html,{url:'https://chemi-ubani.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.indexedDB=indexedDB;w.Headers=Headers;w.fetch=async()=>({ok:false,status:503,json:async()=>({}),text:async()=>''});w.alert=()=>{};w.confirm=()=>true;w.HTMLElement.prototype.scrollIntoView=function(){};w.navigator.geolocation={getCurrentPosition:(_,f)=>f()};}});
 const w=dom.window;await wait();w.testRPC=async()=>({ok:true,data:[]});w.eval(`st.phone='${phone}';sbRpc=(...args)=>window.testRPC(...args);refreshMessagingBadge=()=>{};refreshCloudNotificationBadge=()=>{};`);return dom;
}

let dom=await launch(),w=dom.window;
const message={id:peer,created_at:new Date().toISOString(),body:'quoted <script> text',sender_phone:'522222222',sender_name:'Peer'};
w.testRPC=async(n,a)=>({ok:true,data:n==='conversation_page'?[message]:[]});await w.openCloudChat(id,'Group');
const card=w.document.querySelector('#msgs [data-message-id]');assert.ok(card);[...card.querySelectorAll('button')].find(b=>b.getAttribute('aria-label')==='პასუხის მიწერა').click();assert.match(w.document.getElementById('chatReplyComposer').textContent,/quoted/);
let attempts=[];w.testRPC=async(n,a)=>{if(n==='send_chat_message_v429'){attempts.push(a);return{ok:false}}return{ok:true,data:[]}};
w.document.getElementById('mi').value='reply body';await w.send();assert.equal(attempts[0].p_reply_to,peer);const uuid=attempts[0].p_client_id;await wait();assert.equal((await w.chatDisk.get('511111111')).outbox[0].reply.id,peer);dom.window.close();
dom=await launch();w=dom.window;await w.openCloudChat(id,'Group');assert.match(w.document.querySelector('.pendingMessage').textContent,/quoted/);
w.testRPC=async(n,a)=>{if(n==='send_chat_message_v429'){attempts.push(a);return{ok:true,data:{ok:true}}}return{ok:true,data:[]}};w.document.querySelector('.pendingMessage button').click();await wait();assert.equal(attempts[1].p_client_id,uuid);assert.equal(attempts[1].p_reply_to,peer);
w.setChatReply(message);w.document.getElementById('mi').value='draft';w.document.getElementById('mi').dispatchEvent(new w.Event('input'));await wait();await w.openCloudChat(peer,'Other');assert.ok(w.document.getElementById('chatReplyComposer').hidden);await w.openCloudChat(id,'Group');assert.match(w.document.getElementById('chatReplyComposer').textContent,/quoted/);
let calls=[];w.testRPC=async(n,a)=>{calls.push([n,a]);return{ok:true,data:n==='post_target'?{id:peer,content:'<img onerror=bad()>',author_name:'Peer',created_at:message.created_at}:n==='conversation_target'?message:n==='search_conversation'?[message]:n==='list_direct_chats'?[{id,other_name:'Unread',unread_count:2,last_message:'preview'},{id:peer,other_name:'Read',unread_count:0}]:[]}};
await w.openPostTarget(peer);assert.match(w.document.getElementById('postDetail').textContent,/<img onerror=bad\(\)>/);assert.equal(w.document.querySelector('#postDetail img'),null);
await w.focusChatMessage(peer);assert.match(w.document.querySelector('.chatTarget').textContent,/quoted/);
const search=w.document.querySelector('.conversationTools input');search.value='quoted';search.dispatchEvent(new w.Event('input'));await new Promise(r=>setTimeout(r,470));assert.ok(calls.some(([n,a])=>n==='search_conversation'&&a.p_query==='quoted'));assert.match(w.document.querySelector('.conversationTools').textContent,/1 შედეგი/);
await w.renderDirectChats();assert.equal(w.document.querySelectorAll('#directChatList article').length,2);const checkbox=w.document.getElementById('directChatsPanel').previousElementSibling.querySelector('input');checkbox.checked=true;checkbox.dispatchEvent(new w.Event('change'));await wait();assert.equal(w.document.querySelectorAll('#directChatList article').length,1);assert.match(w.document.getElementById('directChatList').textContent,/preview/);
await w.openCloudChat(peer,'Other');assert.equal(search.value,'');assert.equal(w.document.querySelector('.chatTarget'),null);

// Delayed exact-target results must never surface in another conversation.
let resolveTarget;w.testRPC=async n=>n==='conversation_target'?await new Promise(r=>resolveTarget=r):{ok:true,data:[]};const pending=w.focusChatMessage(id);await w.openCloudChat(id,'New');resolveTarget({ok:true,data:message});await pending;assert.equal(w.document.querySelector('.chatTarget'),null);
// Notification identifiers route directly, and locked/expired photos reveal no images.
const note='33333333-3333-4333-8333-333333333333';let route={screen:'chat',kind:'group',id,name:'Group',messageId:peer};
w.testRPC=async n=>({ok:true,data:n==='resolve_notification'?route:n==='conversation_target'?message:n==='daily_target'?{created_at:new Date().toISOString(),locked:true,back_image_url:'https://example.test/private.jpg'}:[]});await w.openActivity(note);assert.ok(w.document.querySelector('.chatTarget'));
await w.openDailyTarget(peer);assert.equal(w.document.querySelector('#dailyTarget img'),null);
w.testRPC=async()=>({ok:true,data:{created_at:'2020-01-01T10:00:00Z',locked:false,back_image_url:'https://example.test/expired.jpg'}});await w.openDailyTarget(peer);assert.equal(w.document.querySelector('#dailyTarget img'),null);assert.match(w.document.getElementById('dailyTarget').textContent,/აღარ არის/);
w.logoutUser();await wait();dom.window.close();assert.deepEqual(errors,[]);console.log('PASS reply draft/outbox restart and retry identity; conversation isolation; safe exact post/message; bounded search UI; unread inbox filter.');
