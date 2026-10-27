// Bounded, session-scoped registration. No tokens or provider exceptions in user status.
export function createPushRegistration({acquire, deliver, status, active=()=>true, schedule=setTimeout, cancel=clearTimeout, now=Date.now}) {
  let phone='', epoch=0, busy=false, timer=null, retry=0, last=0, state='idle';
  const delays=[3000,15000,60000];
  const clear=()=>{if(timer!==null)cancel(timer);timer=null;};
  const report=s=>{state=s;status(s,phone);};
  async function run(){
    if(!phone||busy||!active())return;
    const owner=phone, generation=epoch;busy=true;last=now();report('connecting');
    try {
      const token=await acquire();
      if(generation!==epoch)return;
      await deliver(token,owner);
      if(generation===epoch){retry=0;report('ready');}
    } catch(error) {
      if(generation!==epoch)return;
      if(error?.code==='permission_denied'){report('denied');return;}
      if(retry<delays.length){const delay=delays[retry++];report('retrying');timer=schedule(()=>{timer=null;run();},delay);}
      else report('unavailable');
    } finally {
      busy=false;
      if(generation!==epoch&&phone)run();
    }
  }
  return {
    request(owner,{manual=false}={}) {
      if(!owner)return;
      if(owner!==phone){clear();epoch++;phone=owner;retry=0;state='idle';}
      if(manual){clear();retry=0;run();}
      else if(!busy&&timer===null&&state==='idle')run();
      else status(state,phone);
    },
    resume(){if(phone&&!busy&&timer===null&&state!=='ready'&&state!=='denied'&&now()-last>=60000){retry=0;run();}},
    stop(){clear();epoch++;phone='';retry=0;state='idle';},
  };
}

// SDK calls cannot be cancelled; stop waiting and ignore late settlement.
export async function withDeadline(task,ms=15000,schedule=setTimeout,cancel=clearTimeout){
 let timer;
 try{return await Promise.race([task,new Promise((_,reject)=>{timer=schedule(()=>reject(new Error('Push service unavailable')),ms)})]);}
 finally{cancel(timer);}
}
