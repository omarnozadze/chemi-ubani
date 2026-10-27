import fs from 'node:fs';import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const {indexedDB}=await import(process.env.INDEXEDDB_MODULE||'fake-indexeddb');
const html=fs.readFileSync('prototype-v4.32.0.html','utf8'),wait=()=>new Promise(r=>setTimeout(r,40)),errors=[];
const id='11111111-1111-4111-8111-111111111111',peer='22222222-2222-4222-8222-222222222222';
async function launch(phone='511111111'){
 const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(e.type==='unhandled-exception')errors.push(e.message)});
 const dom=new JSDOM(html,{url:'https://chemi-ubani.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.indexedDB=indexedDB;w.Headers=Headers;w.fetch=async()=>({ok:false,status:503,json:async()=>({}),text:async()=>''});w.alert=()=>{};w.confirm=()=>true;w.HTMLElement.prototype.scrollIntoView=function(){};w.navigator.geolocation={getCurrentPosition:(_,f)=>f()};}});
 const w=dom.window;await wait();w.testRPC=async()=>({ok:true,data:[]});w.eval(`st.phone='${phone}';sbRpc=(...args)=>window.testRPC(...args);refreshMessagingBadge=()=>{};refreshCloudNotificationBadge=()=>{};`);return dom;
}



const dom=await launch(),w=dom.window,el=id=>w.document.getElementById(id);let attempts=[],fail=true,rows=[];w.testRPC=async(name,args)=>{if(name==='send_chat_attachment_v432'){attempts.push(args);if(fail)return{ok:false,error:'offline'};rows=[{id:peer,sender_phone:'511111111',sender_name:'Me',created_at:new Date().toISOString(),body:'მდებარეობა',attachment:args.p_attachment}];return{ok:true,data:{ok:true,id:peer}}}return{ok:true,data:name==='conversation_page'?rows:name==='service_thread_v432'?null:[]}};
await w.openDirectChat(id,{name:'Peer',phone:'522222222'});w.chatAttachment432.restore({kind:'location',lat:41.7,lng:44.8});await w.send();assert.equal(attempts.length,1);assert.equal(w.chatAttachment432.get(),null);assert.match(el('chat').textContent,/ხელახლა გაგზავნა/);fail=false;const retry=[...el('chat').querySelectorAll('button')].find(b=>b.textContent==='↻ ხელახლა გაგზავნა');await retry.onclick();assert.equal(attempts.length,2);assert.equal(attempts[0].p_client_id,attempts[1].p_client_id);assert.match(el('msgs').textContent,/მდებარეობის ნახვა/);assert.equal(el('chat').querySelectorAll('.pendingMessage').length,0);
w.chatAttachment432.restore({kind:'location',lat:1,lng:2});el('chatAttachmentPreview432').querySelector('button').click();assert.equal(w.chatAttachment432.get(),null);
const uploaded=[];w.fetch=async(url,args)=>{uploaded.push({url,args});return{ok:true}};const request={phone:'511111111',clientId:id,attachment:{kind:'file',mime:'application/pdf',name:'test.pdf',blob:new Blob(['PDF'],{type:'application/pdf'})}};const a=await w.uploadChatAttachment432(request);assert.equal(a.path,'511111111/'+id+'.pdf');assert.equal(uploaded.length,1);assert.equal(uploaded[0].args.headers['x-upsert'],'false');
assert.deepEqual(errors,[]);dom.window.close();console.log('PASS attachment composer removal, durable failed-message retry with same request ID, sent location rendering, private file upload path/no overwrite');
