import assert from 'node:assert/strict';
import {createPushRegistration,withDeadline} from '../src/push-registration-v442.mjs';
const tick=()=>new Promise(r=>setImmediate(r));
let jobs=new Map(),key=0,states=[],calls=0,deliveries=[],active=true,clock=0;
const options={schedule:(fn,ms)=>{jobs.set(++key,{fn,ms});return key},cancel:id=>jobs.delete(id),now:()=>clock,active:()=>active,status:(s,p)=>states.push([s,p]),acquire:async()=>{calls++;if(calls<3)throw Error('SERVICE_NOT_AVAILABLE');return'test-token'},deliver:async(t,p)=>deliveries.push([t,p])};
const c=createPushRegistration(options);c.request('A');await tick();assert.equal(states.at(-1)[0],'retrying');assert.equal(jobs.size,1);
async function timer(){const [k,v]=jobs.entries().next().value;jobs.delete(k);clock+=v.ms;v.fn();await tick();}
await timer();await timer();assert.equal(calls,3);assert.deepEqual(deliveries,[['test-token','A']]);assert.equal(states.at(-1)[0],'ready');assert.equal(jobs.size,0);
c.request('A');await tick();assert.equal(calls,3);c.stop();
// Exhaustion is bounded, rather than permanently retrying in the background.
calls=0;states=[];const exhausted=createPushRegistration({...options,acquire:async()=>{calls++;throw Error('offline')}});exhausted.request('A');await tick();for(let i=0;i<3;i++)await timer();assert.equal(calls,4);assert.equal(jobs.size,0);assert.equal(states.at(-1)[0],'unavailable');exhausted.stop();
// An old account cannot receive or register a delayed token.
let resolve;deliveries=[];calls=0;const switched=createPushRegistration({...options,acquire:()=>{calls++;return calls===1?new Promise(r=>resolve=r):Promise.resolve('new-token')}});switched.request('old');switched.stop();switched.request('new');resolve('old-token');await tick();assert.deepEqual(deliveries,[['new-token','new']]);switched.stop();
// Permission denial has no retry; logout cancels pending timers.
const denied=createPushRegistration({...options,acquire:async()=>{throw Object.assign(Error(),{code:'permission_denied'})}});denied.request('A');await tick();assert.equal(states.at(-1)[0],'denied');assert.equal(jobs.size,0);denied.stop();
const stopped=createPushRegistration({...options,acquire:async()=>{throw Error()}});stopped.request('A');await tick();assert.equal(jobs.size,1);stopped.stop();assert.equal(jobs.size,0);
console.log('PASS push transient recovery, bounded exhaustion, logout/account race, permission denial and timer cleanup.');

let expire,cleared=false;const hung=withDeadline(new Promise(()=>{}),15,fn=>{expire=fn;return 1},()=>cleared=true);expire();await assert.rejects(()=>hung,/unavailable/);assert.equal(cleared,true);assert.equal(await withDeadline(Promise.resolve('token'),15), 'token');console.log('PASS native SDK token deadline releases a hung request and clears timers.');
