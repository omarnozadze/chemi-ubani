import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
let now=0,id=0;const timers=new Map(),listeners={};
const c={document:{hidden:false,addEventListener:(n,f)=>listeners[n]=f},navigator:{onLine:true},setTimeout:(f,ms)=>{timers.set(++id,{f,at:now+ms});return id},clearTimeout:id=>timers.delete(id),Math:Object.assign(Object.create(Math),{random:()=>0})};c.window=c;c.addEventListener=(n,f)=>listeners[n]=f;vm.createContext(c);vm.runInContext(fs.readFileSync('src/polling-v427.js','utf8'),c);
async function advance(ms){now+=ms;for(const [id,t]of [...timers])if(t.at<=now){timers.delete(id);t.f()}await Promise.resolve();await Promise.resolve()}
let calls=0,resolve;c.appPoll.add('chat',5000,()=>true,()=>{calls++;return new Promise(r=>resolve=r)});
await advance(5000);assert.equal(calls,1);await advance(30000);assert.equal(calls,1);resolve();await advance(0);c.document.hidden=true;await advance(5000);assert.equal(calls,1);
c.document.hidden=false;c.navigator.onLine=false;await advance(5000);assert.equal(calls,1);c.navigator.onLine=true;listeners.online();await advance(250);assert.equal(calls,2);c.appPoll.remove('chat');resolve();await advance(10000);assert.equal(calls,2);
c.appPoll.add('inactive',1000,()=>false,()=>calls++);await advance(1000);assert.equal(calls,2);console.log('PASS: no overlap; hidden/offline pause; online wake; pending removal; inactive screen.');
