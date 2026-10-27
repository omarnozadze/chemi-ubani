import fs from 'node:fs';import assert from 'node:assert/strict';
const {JSDOM,VirtualConsole}=await import(process.env.JSDOM_MODULE||'jsdom');
const {indexedDB}=await import(process.env.INDEXEDDB_MODULE||'fake-indexeddb');
assert.doesNotMatch(fs.readFileSync('App.js','utf8'),/useAudioRecorder|audioPermission432|nativeAudio438/);assert.equal(JSON.parse(fs.readFileSync('package.json')).dependencies['expo-audio'],undefined);assert.match(fs.readFileSync('android/app/src/main/AndroidManifest.xml','utf8'),/RECORD_AUDIO" tools:node="remove"/);
const html=fs.readFileSync('prototype-v4.49.0.html','utf8'),wait=()=>new Promise(r=>setTimeout(r,40)),errors=[];
const id='11111111-1111-4111-8111-111111111111',peer='22222222-2222-4222-8222-222222222222';
async function launch(phone='511111111',theme='light'){
 const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(e.type==='unhandled-exception')errors.push(e.message)});
 const dom=new JSDOM(html,{url:'https://chemi-ubani.local',runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.localStorage.setItem('chemi-theme446',theme);w.indexedDB=indexedDB;w.Headers=Headers;w.fetch=async()=>({ok:false,status:503,json:async()=>({}),text:async()=>''});w.alert=()=>{};w.confirm=()=>true;w.HTMLElement.prototype.scrollIntoView=function(){};w.navigator.geolocation={getCurrentPosition:(_,f)=>f()};}});
 const w=dom.window;await wait();w.testRPC=async()=>({ok:true,data:[]});w.eval(`st.phone='${phone}';sbRpc=(...args)=>window.testRPC(...args);refreshMessagingBadge=()=>{};refreshCloudNotificationBadge=()=>{};`);return dom;
}





const dom=await launch(),w=dom.window,el=id=>w.document.getElementById(id);assert.deepEqual(errors,[]);
assert.equal(el('home').querySelector('.neighborhoodHero'),null);
assert.equal(el('paymentCenter'),null);assert.equal(el('financeAdmin'),null);assert.equal(el('serviceOrder'),null);
assert.ok(![...w.document.querySelectorAll('[onclick*="pickPostType"]')].some(x=>x.textContent.includes('იყიდება')));
assert.equal(el('googlePlaces432'),null);assert.equal(el('refreshBusinessBtn'),null);assert.equal(el('locationControls').querySelectorAll('button').length,2);
let calls=[],opened=[];w.openDirectChat=async(...args)=>opened.push(args);
w.testRPC=async(n,a)=>{calls.push({n,a});return {ok:true,data:{ok:true,id,other:{phone:'522222222',name:'სპეციალისტი'}}}};
await w.openRequest432(id);assert.equal(opened.length,1);assert.equal(calls.at(-1).n,'start_specialist_chat_v444');assert.ok(!calls.some(x=>/create_service|payment/.test(x.n)));assert.match(el('mi').placeholder,/რა გჭირდება/);
let release;w.testRPC=()=>new Promise(r=>release=r);const pending=w.openRequest432(id);const duplicate=w.openRequest432(id);release({ok:true,data:{ok:true,id,other:{name:'სპეციალისტი'}}});await Promise.all([pending,duplicate]);assert.equal(opened.length,2,'double tap opens one thread');
const stale=w.openRequest432(id);w.eval("st.phone='533333333'");release({ok:true,data:{ok:true,id,other:{name:'STALE'}}});await stale;assert.equal(opened.length,2,'account switch suppresses stale chat');w.eval("st.phone='511111111'");
let rows=[{id:'new',title:'ახალი',body:'ტექსტი',created_at:'2026-09-18',pinned:false,can_pin:true},{id:'old',title:'აპინული ძველი',body:'ტექსტი',created_at:'2026-09-01',pinned:true,can_pin:true}];
w.testRPC=async(n,a)=>{calls.push({n,a});return{ok:true,data:n==='list_hot_news'?rows:{ok:true,pinned:a.p_pinned}}};await w.loadHotNews();assert.equal(el('hotNewsFeed').firstElementChild.dataset.newsId,'old');const pin=el('hotNewsFeed').lastElementChild.querySelector('button');pin.click();await wait();assert.equal(el('hotNewsFeed').firstElementChild.dataset.newsId,'new');assert.equal(calls.at(-1).n,'pin_hot_news_v444');assert.equal(calls.at(-1).a.p_expected,false);
rows=rows.map(x=>({...x,can_pin:false}));await w.loadHotNews();assert.equal(el('hotNewsFeed').querySelectorAll('button').length,0);
// Two branches with the same display name keep distinct IDs and coordinates.
w.testRPC=async()=>({ok:true,data:{items:[]}});w.navigator.geolocation.getCurrentPosition=(ok)=>ok({coords:{latitude:41.7,longitude:44.8,accuracy:12}});
w.fetch=async()=>({ok:true,json:async()=>({elements:[{type:'node',id:1,lat:41.7001,lon:44.8,tags:{name:'ერთი სახელი',amenity:'cafe'}},{type:'node',id:2,lat:41.7002,lon:44.8,tags:{name:'ერთი სახელი',amenity:'cafe'}},{type:'node',id:3,lat:90,lon:0,tags:{name:'შორს',amenity:'cafe'}}]})});
await w.requestLocation();assert.match(el('searchOriginLabel').textContent,/±12 მ/);assert.equal(w.eval('businessData.length'),2);w.eval("bizQuickCat='ყველა';openCats.clear();renderGroupedBusinesses()");el('businessList').querySelector('.cathead').click();const cards=el('businessList').querySelectorAll('.businessCard');assert.equal(cards.length,2);let point;w.openBusinessRoute=(...args)=>point=args;cards[1].querySelector('button').click();assert.equal(point[0],41.7002);assert.equal(w.osmAddress({name:'ერთი სახელი'}),'მისამართი წყაროში მითითებული არ არის');

// Feedback action uses the verified server destination; rapid taps never send duplicate requests/messages.
assert.equal(el('supportHome445'),null);
w.eval("st.phone='559111111'");let supportCalls=0;w.testRPC=async n=>{assert.equal(n,'start_support_chat_v445');supportCalls++;return{ok:true,data:{ok:true,id,other:{phone:'500000000',name:'ადმინისტრატორი'}}}};
await Promise.all([w.openSupportChat445(),w.openSupportChat445()]);assert.equal(supportCalls,1);assert.equal(opened.at(-1)[1].name,'ადმინისტრატორი');assert.match(el('mi').placeholder,/იდეა/);
const openedBefore=opened.length;w.testRPC=()=>new Promise(r=>release=r);const supportStale=w.openSupportChat445();w.eval("st.phone='559222222'");release({ok:true,data:{ok:true,id,other:{name:'STALE'}}});await supportStale;assert.equal(opened.length,openedBefore);
// Ordinary account receives cloud businesses even while the independent map provider is down.
let network=0;w.fetch=async()=>{network++;return{ok:false,status:503,json:async()=>({})}};
w.testRPC=async n=>({ok:true,data:n==='nearby_businesses'?{items:[{id:'approved',name:'დადასტურებული კაფე',category:'კვება',lat:42,lng:43}],has_more:false}:[]});
await w.setLocationOrigin(42,43);assert.equal(network,2,'one fallback after the primary provider fails');assert.equal(w.eval('cloudBusinesses[0].id'),'approved');w.eval("bizQuickCat='ყველა';openCats.clear();renderGroupedBusinesses()");el('businessList').querySelector('.cathead').click();assert.match(el('businessList').textContent,/დადასტურებული კაფე/);
await w.refreshBusinessList();await w.refreshBusinessList();assert.equal(network,2,'polling respects failure cooldown');assert.match(el('locationLoadStatus').textContent,/ავტომატურად/);
const clock=w.Date.now;let now=clock()+130000;w.Date.now=()=>now;w.fetch=async url=>{network++;return url.includes('private.coffee')?{ok:false,status:503}:{ok:true,json:async()=>({elements:[{type:'node',id:8,lat:42,lon:43,tags:{name:'აღდგენილი',amenity:'cafe'}}]})}};
await w.refreshBusinessList();assert.equal(w.eval('businessData[0].name'),'აღდგენილი');const callsAfterRecovery=network;await w.refreshBusinessList();assert.equal(network,callsAfterRecovery,'successful results are cached');
// Tiny GPS drift preserves visible rows and cache instead of blanking and refetching.
w.navigator.geolocation.getCurrentPosition=ok=>ok({coords:{latitude:42.000001,longitude:43,accuracy:8}});await w.requestLocation();assert.equal(network,callsAfterRecovery);assert.equal(w.eval('businessData[0].name'),'აღდგენილი');
now+=130000;w.fetch=async()=>{network++;return{ok:false,status:429}};const before429=network;await w.refreshBusinessList();assert.equal(network,before429+1,'rate limiting never causes a fallback retry');assert.equal(w.eval('businessData[0].name'),'აღდგენილი','outage retains previous map rows');await w.refreshBusinessList();assert.equal(network,before429+1);
w.Date.now=clock;
console.log('PASS 445 feedback chat duplicate/session guards; regular-user cloud rendering during map outage; fallback, cooldown/cache/recovery/GPS-drift and 429 handling.');

const theme=el('themeToggle446');assert.equal(theme.getAttribute('aria-checked'),'false');theme.click();assert.equal(w.document.documentElement.dataset.theme,'dark');assert.equal(w.localStorage.getItem('chemi-theme446'),'dark');assert.equal(theme.getAttribute('aria-checked'),'true');theme.click();assert.equal(w.document.documentElement.dataset.theme,'light');
assert.ok(el('marketHome444').querySelector('svg'));assert.ok(w.document.querySelector('.civicIntro434 svg'));
w.eval("cloudSpecialistAnnouncements=[{id:'phone-test',owner:'Test',phone:'598123456',title:'Test',text:'Body',targetDistricts:['ვაკე']}]");w.testRPC=async()=>({ok:true,data:[]});await w.openAnnouncementSpecialistProfile('phone-test');assert.equal(w.document.querySelector('.specialistPhone446 bdi').textContent,'598123456');
const plus=w.document.querySelector('[aria-controls="chatAttachmentMenu432"]');el('chatAttachmentMenu432').hidden=true;plus.click();assert.equal(el('chatAttachmentMenu432').hidden,false);assert.equal(el('chatAttachmentMenu432').parentElement.id,'chatDock446');assert.equal(el('chatDock446').lastElementChild.id,'chatComposeRow435');
el('mi').value='აბგ';el('mi').setSelectionRange(1,1);el('mi').dispatchEvent(new w.Event('select'));el('emojiPicker446').querySelector('button').click();assert.equal(el('mi').value,'ა👋ბგ');assert.equal(el('mi').selectionStart,3);assert.equal(el('chatAttachmentMenu432').hidden,true);
w.eval("dailyMemories=[{id:'memory-test',back_image_url:'https://example.test/back.png',front_image_url:'https://example.test/front.png',caption:'<safe>'}]");w.openDailyMemory('memory-test');let large=w.document.querySelector('.memoryMain446 img'),little=w.document.querySelector('.memoryThumb446 img');assert.match(large.src,/back.png/);w.document.querySelector('.memoryThumb446').click();assert.match(large.src,/front.png/);assert.match(little.src,/back.png/);w.document.querySelector('.memoryMain446').click();assert.match(large.src,/back.png/);assert.equal(w.document.querySelector('.memory446 safe'),null);w.handleNativeBack439();assert.equal(w.document.querySelector('.memory446'),null);
w.openDailyMemory('memory-test');w.document.querySelector('.memory446').dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true}));assert.equal(w.document.querySelector('.memory446'),null);
const restored=await launch('559111111','dark');assert.equal(restored.window.document.documentElement.dataset.theme,'dark');assert.equal(restored.window.document.getElementById('themeToggle446').getAttribute('aria-checked'),'true');restored.window.close();
console.log('PASS 446 persisted theme switch; home icons; specialist phone; upward attachment dock; emoji insertion at cursor; two-frame swap on either image; escape/native-back close.');

assert.equal(el('marketplace').querySelector('.top').firstElementChild.tagName,'BUTTON');
w.eval("marketListings=[{id:'market-test',title:'Test',description:'Body',owner_phone:'598123456',created_at:new Date().toISOString()}]");w.openMarketDetail('market-test');assert.match(el('marketDetailBody').textContent,/ტელეფონი: 598123456/);
let reactionState={id:'a4700000-0000-4000-8000-000000000001',reaction:null,count:0};let writes=0;
w.testRPC=async(n,a)=>{if(n==='reaction_summaries_v447')return{ok:true,data:[reactionState]};if(n==='set_reaction_v447'){writes++;reactionState={...reactionState,reaction:a.p_reaction,count:a.p_reaction?1:0};return{ok:true,data:{...reactionState,ok:true}};}return{ok:true,data:[]};};
const post=w.document.createElement('article');post.dataset.postId=reactionState.id;post.innerHTML='<div class="postActions"><span onclick="toggleLike(this)">♡ მოწონება</span><span onclick="commentPost(this)">◯ კომენტარი</span><button class="report440">გასაჩივრება</button></div>';el('feed').append(post);await wait();const like=post.querySelector('.reaction447');assert.ok(like);await new Promise(r=>setTimeout(r,110));like.click();await wait();assert.equal(writes,1);assert.equal(like.getAttribute('aria-pressed'),'true');assert.ok(like.classList.contains('liked'));
like.dispatchEvent(new w.MouseEvent('contextmenu',{bubbles:true,cancelable:true}));assert.equal(w.document.querySelectorAll('.reactionsPopup447 button').length,6);w.document.querySelectorAll('.reactionsPopup447 button')[2].click();await wait();assert.equal(reactionState.reaction,'😂');assert.match(like.textContent,/😂/);assert.equal(w.document.querySelector('.reactionsPopup447'),null);assert.ok(post.querySelector('.commentSymbol447'));assert.ok(post.querySelector('.report440'));
// Leaving during the first GPS request must not disable acquisition on the next entry.
w.logoutUser();await wait();w.eval("st.phone='559111111'");let gps447=0,firstGPS;w.navigator.geolocation.getCurrentPosition=ok=>{gps447++;if(gps447===1)firstGPS=ok;else ok({coords:{latitude:41.7,longitude:44.8,accuracy:10}});};w.fetch=async()=>({ok:true,json:async()=>({elements:[]})});w.testRPC=async n=>({ok:true,data:n==='nearby_businesses'?{items:[]}:[]});w.go('business');w.go('home');w.go('business');await wait();assert.equal(gps447,2);assert.equal(w.businessLocationReady(),true);firstGPS({coords:{latitude:42,longitude:43}});await wait();assert.equal(w.eval('userCoords.lat'),41.7);
console.log('PASS 447 marketplace header/phone, persisted reaction selection/green state/picker/comment icon, and automatic GPS re-entry after cancellation.');
assert.equal(el('districtLiveStat').parentElement.id,'home');assert.equal(el('home').querySelector('.civicIntro434').getAttribute('role'),'button');
w.eval("currentDirectThreadId='11111111-1111-4111-8111-111111111111';currentCloudChatId=null;st.phone='559111111'");
let prefs448=[];w.testRPC=async(name,p)=>{if(name==='message_preferences_v448'){if(p.p_action)prefs448=[{id:p.p_message_id,pinned:p.p_action==='pin',hidden:p.p_action==='hide'}];return {ok:true,data:prefs448};}return{ok:true,data:[]}};
const m448={id:'33333333-3333-4333-8333-333333333333',body:'გამარჯობა',sender_phone:'559111111',sender_name:'სახელი',created_at:new Date().toISOString()};
el('msgs').innerHTML='<div class="msg mine" data-message-id="'+m448.id+'"><b>სახელი</b><br>გამარჯობა<div class="meta">დრო</div></div>';
w.decorateConversationRows([m448]);await wait();const row448=el('msgs').firstElementChild;assert.ok(row448.classList.contains('direct448'));row448.click();assert.ok(row448.classList.contains('showTime448'));row448.querySelector('.messageMore448').click();assert.equal(w.document.querySelectorAll('.messageMenu448 button').length,4);w.document.querySelectorAll('.messageMenu448 button')[1].click();await wait();assert.equal(w.document.querySelector('.privatePin448').hidden,false);row448.querySelector('.messageMore448').click();w.eval('appConfirm433=async()=>true');w.document.querySelectorAll('.messageMenu448 button')[3].click();await wait();assert.equal(row448.hidden,true);assert.equal(w.document.querySelector('.privatePin448').hidden,true);
console.log('PASS 448 compact home, removed feedback, detached registered count; contextual four-action menu, time reveal, persistent private pin and hide.');
assert.deepEqual(errors,[]);w.eval("st.phone=''");dom.window.close();console.log('PASS 444: direct chat/idempotent tap/session switch; no payment screens; market placement; pin ordering and rights; automatic GPS; duplicate branch identity and coordinate routing.');
