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

const dom=await launch(),w=dom.window;let preference=null,fail=false,calls=[],native=[];
w.ReactNativeWebView={postMessage:m=>native.push(JSON.parse(m))};
w.testRPC=async(name,args)=>{if(name!=='daily_reminder_preference')return{ok:true,data:[]};calls.push(args.p_enabled);if(fail)return{ok:false};if(args.p_enabled!==null)preference={enabled:args.p_enabled};return{ok:true,data:preference}};
await w.syncDailyPhotoReminder();assert.deepEqual(calls,[null,true]);assert.equal(w.eval('dailyPhotoReminderEnabled'),true);assert.match(w.document.getElementById('settingsPhotoReminderState').textContent,/08:00.*20:00/);assert.ok(native.every(m=>m.type==='setDailyPhotoReminder'&&m.enabled===false));
await w.toggleDailyPhotoReminder();assert.equal(preference.enabled,false);assert.equal(w.localStorage.getItem('chemiUbaniDailyPhotoReminder:511111111'),'off');
fail=true;await w.toggleDailyPhotoReminder();assert.equal(w.eval('dailyPhotoReminderEnabled'),false,'failed save retains setting');fail=false;
await w.toggleDailyPhotoReminder();assert.equal(w.eval('dailyPhotoReminderEnabled'),true);
// Late preference reads must never apply to a different logged-in account.
let release;w.eval("st.phone='522222222'");w.testRPC=(name)=>name==='daily_reminder_preference'?new Promise(r=>release=r):Promise.resolve({ok:true,data:[]});
const late=w.syncDailyPhotoReminder();await wait();w.logoutUser();w.eval("st.phone='533333333'");w.testRPC=async()=>({ok:true,data:{enabled:false}});await w.syncDailyPhotoReminder();release({ok:true,data:{enabled:true}});await late;assert.equal(w.eval('dailyPhotoReminderEnabled'),false,'late result ignored after logout');
let opened=0;w.eval('openDailyMoment=()=>window.recordDaily()');w.recordDaily=()=>opened++;w.openDailyPhotoReminder();assert.equal(opened,1);
assert.deepEqual(errors,[]);dom.window.close();
// Execute the actual native cancellation helper with a fake Expo notification API.
const app=fs.readFileSync('App.js','utf8'),helper=app.slice(app.indexOf('async function setDailyPhotoReminder()'),app.indexOf('export default function App()'));
const {runInNewContext}=await import('node:vm');const cancelled=[];
const nativeFn=runInNewContext(helper+';setDailyPhotoReminder',{PHOTO_REMINDER_ID_KEY:'daily-photo-reminder',Notifications:{getAllScheduledNotificationsAsync:async()=>[{identifier:'old',content:{data:{kind:'daily-photo-reminder'}}},{identifier:'other',content:{data:{kind:'unrelated'}}}],cancelScheduledNotificationAsync:async id=>cancelled.push(id),scheduleNotificationAsync:()=>{throw Error('Local unconditional reminders forbidden')}}});
const result=await nativeFn();assert.deepEqual(cancelled,['old']);assert.equal(result.serverManaged,true);assert.ok(app.includes('useEffect(() => { setDailyPhotoReminder().catch(() => {}); }, []);'));
console.log('PASS account-bound preference initialization and toggle; failed save preservation; logout/stale response isolation; reminder tap; legacy local cancellation without rescheduling.');
