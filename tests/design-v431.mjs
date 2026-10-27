import fs from 'node:fs';import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const {indexedDB}=await import(process.env.INDEXEDDB_MODULE||'fake-indexeddb');
const html=fs.readFileSync('prototype-v4.31.0.html','utf8'),wait=()=>new Promise(r=>setTimeout(r,40)),errors=[];
const id='11111111-1111-4111-8111-111111111111',peer='22222222-2222-4222-8222-222222222222';
async function launch(phone='511111111'){
 const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(e.type==='unhandled-exception')errors.push(e.message)});
 const dom=new JSDOM(html,{url:'https://chemi-ubani.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.indexedDB=indexedDB;w.Headers=Headers;w.fetch=async()=>({ok:false,status:503,json:async()=>({}),text:async()=>''});w.alert=()=>{};w.confirm=()=>true;w.HTMLElement.prototype.scrollIntoView=function(){};w.navigator.geolocation={getCurrentPosition:(_,f)=>f()};}});
 const w=dom.window;await wait();w.testRPC=async()=>({ok:true,data:[]});w.eval(`st.phone='${phone}';sbRpc=(...args)=>window.testRPC(...args);refreshMessagingBadge=()=>{};refreshCloudNotificationBadge=()=>{};`);return dom;
}

const dom=await launch(),w=dom.window,el=id=>w.document.getElementById(id);const nav=el('nav');assert.equal(nav.children.length,6);assert.equal(nav.querySelectorAll('svg').length,6);assert.deepEqual([...nav.children].map(b=>b.textContent),['მთავარი','ახლოს','დღის ფოტო','ამბები','სერვისები','პროფილი']);
for(const [index,screen]of [[0,'home'],[1,'business'],[3,'hotNews'],[4,'specialists'],[5,'profile']]){nav.children[index].click();await wait();assert.ok(!el(screen).classList.contains('hide'),screen);assert.equal(nav.children[index].getAttribute('aria-current'),'page');assert.equal(nav.querySelectorAll('[aria-current="page"]').length,1)}
assert.equal(el('home').querySelectorAll('#districtLiveStat').length,1);assert.ok(el('home').querySelector('.neighborhoodHero #districtRegisteredCount'));assert.equal(el('profile').querySelectorAll('#profilePhotoInput').length,1);assert.equal(el('profile').querySelector('.profilePhotoEdit').getAttribute('for'),'profilePhotoInput');assert.ok(el('rolePanel'));assert.ok(el('profileAccountType'));assert.ok(el('myPostsCount'));assert.equal(el('profile').querySelectorAll('.menurow[role="button"]').length,8);
let opened=0;w.eval('openMyPosts=()=>window.recordOpen()');w.recordOpen=()=>opened++;el('profile').querySelector('.menurow').dispatchEvent(new w.KeyboardEvent('keydown',{key:'Enter',bubbles:true}));assert.equal(opened,1);w.go('chat');await wait();assert.ok(nav.classList.contains('hide'));assert.deepEqual(errors,[]);dom.window.close();console.log('PASS six navigation destinations and active state; counters/role/photo controls retained; keyboard profile action; chat hides nav; HTML startup');
