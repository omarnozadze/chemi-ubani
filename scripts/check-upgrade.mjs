import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=fs.readFileSync('prototype-v4.22.0.html','utf8');
for(const [i,m]of [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].entries())new vm.Script(m[1],{filename:`inline-${i}`});
const embedded=fs.readFileSync('src/appHtml.js','utf8');assert.equal(JSON.parse(embedded.slice(embedded.indexOf('=')+1).trim().replace(/;$/,'')),html);
assert.equal((html.match(/<!-- V423 START -->/g)||[]).length,1);
const source=fs.readFileSync('src/upgrade-v423.js','utf8');
const elements=new Map();
function element(){return {textContent:'',innerHTML:'',value:'',style:{},className:'',classList:{add(){},toggle(){},contains(){return false}},append(){},replaceChildren(){},setAttribute(){},querySelector(){return element()},querySelectorAll(){return []},lastElementChild:{scrollIntoView(){}}}}
const el=id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id)};
let gpsCalls=0,osmCalls=0,resolveGPS;
const calls=[];
const noop=()=>{};
const context={console,JSON,Math,Number,String,Set,Promise,Date,Error,document:{hidden:false,head:element(),body:element(),documentElement:{scrollHeight:1000},createElement:element,createTextNode:x=>x,getElementById:el,querySelector:el,querySelectorAll:()=>[],addEventListener:noop},navigator:{geolocation:{getCurrentPosition(ok){gpsCalls++;resolveGPS=()=>ok({coords:{latitude:41.7,longitude:44.8}})}}},setInterval:noop,setTimeout:noop,clearTimeout:noop,alert:noop,window:null,
 st:{phone:'555111222'},currentDirectThreadId:'thread-a',currentCloudChatId:'',currentChatMessageImage:'',directChatsCache:[],businessData:[],cloudBusinesses:[],openCats:new Set(),userCoords:{lat:0,lng:0},maxRadiusKm:2,
 normalizePhone:x=>String(x||'').replace(/\D/g,''),esc:x=>String(x||''),formatCloudDate:x=>x,normalizeBusinessCategory:x=>x,renderGroupedBusinesses:noop,refreshBusinessList:noop,requestLocation:noop,startBusinessLocationWatch:noop,setRadius:noop,setRadiusV413:noop,
 fetchOpenStreetMapBusinesses:async()=>{osmCalls++},fetchPublicBusinesses:async()=>[],renderBusinessBanners:async()=>{},sbRpc:async(name,args)=>{calls.push({name,args});return {ok:true,data:[]}},
 reportUserByPhone:noop,loadDirectMessages:noop,loadCloudChatMessages:noop,openDirectChat:noop,openCloudChat:noop,send:noop,clearChatMessageImage:noop,pickChatMessageImage:noop,logoutUser:noop,go:noop,refreshPublicProfileSafety:noop,openPublicProfileByPhone:noop,finishLogin:noop,requestPushFoundation:noop,refreshMessagingBadge:noop,refreshCloudNotificationBadge:noop,renderCloudNotifications:noop,loadCloudChatMemberCount:noop,sbListNotifications:async()=>[],sbMarkNotificationRead:noop,openCloudNotification:noop,setMessageTab:noop};
context.window=context;context.innerHeight=800;context.scrollY=0;context.toggleAppNotifications=noop;context.appNotificationsEnabled=true;
vm.createContext(context);vm.runInContext(source,context);
const a=context.refreshBusinessList(),b=context.refreshBusinessList();assert.equal(a,b);assert.equal(gpsCalls,1);assert.equal(osmCalls,0);resolveGPS();await a;assert.equal(osmCalls,1);assert.equal(context.userCoords.lat,41.7);
// A response for the previous conversation must never render or mark read.
let resolveMessages;
context.sbRpc=(name,args)=>new Promise(resolve=>{resolveMessages=resolve});
const pending=context.loadDirectMessages();context.currentDirectThreadId='thread-b';el('msgs').innerHTML='new-thread';resolveMessages({ok:true,data:[{body:'old-thread',created_at:'2026-01-01T00:00:00Z'}]});await pending;assert.equal(el('msgs').innerHTML,'new-thread');
// Read watermark is the newest fetched message, not client time.
context.sbRpc=async(name,args)=>{calls.push({name,args});return {ok:true,data:name==='list_direct_messages'?[{body:'hello',sender_phone:'other',created_at:'2026-01-01T00:00:00Z'}]:[]}};
await context.loadDirectMessages();const mark=calls.find(x=>x.name==='mark_conversation_read_v423');assert.equal(mark.args.p_through,'2026-01-01T00:00:00Z');
context.logoutUser();assert.equal(context.currentDirectThreadId,'');assert.equal(context.currentCloudChatId,'');
console.log('PASS: inline JS syntax; embedded HTML parity; one upgrade block; GPS before fetch; refresh coalescing; stale chat suppression; read watermark; logout cleanup.');
