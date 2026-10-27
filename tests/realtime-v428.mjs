import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
let frames=[],sockets=[],timers=[],listeners={},intervals=[],signals=0;
class Socket{constructor(url){this.url=url;sockets.push(this)}send(s){frames.push(JSON.parse(s))}close(){this.closed=true}}
const w={appNativeActive:true,appPoll:{interval:(...a)=>intervals.push(a)},getActivitySession:async()=>({userId:'user1',token:'private-token'}),handleActivitySignal:()=>signals++,addEventListener:(e,f)=>listeners[e]=f};
const ctx={window:w,st:{phone:'111'},document:{hidden:false,addEventListener:(e,f)=>listeners[e]=f},navigator:{onLine:true},WebSocket:Socket,SUPABASE_URL:'https://test.supabase.co',SUPABASE_ANON_KEY:'public-key',go:()=>{},logoutUser:()=>{},setTimeout:(fn)=>{timers.push(fn);return timers.length},clearTimeout:()=>{},setInterval:fn=>{timers.push(fn);return timers.length},clearInterval:()=>{},Math};vm.createContext(ctx);vm.runInContext(fs.readFileSync('src/realtime-v428.js','utf8'),ctx);
w.activityConnection();await new Promise(r=>setImmediate(r));const ws=sockets[0];ws.onopen();assert.equal(frames[0].payload.config.private,true);assert.equal(frames[0].topic,'realtime:activity:user1');assert.ok(!ws.url.includes('private-token'));
ws.onmessage({data:JSON.stringify({event:'phx_reply',ref:frames[0].ref,payload:{status:'ok'}})});assert.equal(w.activityConnected,true);assert.ok(intervals.some(x=>x[1]===60000));
ws.onmessage({data:JSON.stringify({topic:'realtime:activity:other',event:'broadcast',payload:{event:'activity'}})});assert.equal(signals,1);
ws.onmessage({data:JSON.stringify({topic:'realtime:activity:user1',event:'broadcast',payload:{event:'activity'}})});assert.equal(signals,2);
ctx.document.hidden=true;listeners.visibilitychange();assert.equal(ws.closed,true);assert.equal(w.activityConnected,false);
ctx.document.hidden=false;w.activityConnection();await new Promise(r=>setImmediate(r));ctx.logoutUser();assert.equal(sockets.at(-1).closed,true);console.log('PASS private channel, no JWT in URL, event isolation, reconciliation cadence, background/logout disconnect');
