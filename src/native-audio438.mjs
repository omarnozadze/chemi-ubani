// Native recorder transport: no network, credentials or user content in diagnostics.
export function createAudioBridge({recorder,permission,mode,read,remove,emit,closeCamera,active=()=>true,schedule=setTimeout,unschedule=clearTimeout}){
 let queue=Promise.resolve(),epoch=0,current=null,timer=null,disposed=false,requestingPermission=false;
 const valid=id=>typeof id==='string'&&/^[a-zA-Z0-9_-]{1,80}$/.test(id);
 const notify=(id,state,extra={})=>{if(!disposed)emit({id,state,...extra})};
 async function clean(){unschedule(timer);timer=null;try{await recorder.stop()}catch{};try{if(recorder.uri)await remove(recorder.uri)}catch{};try{await mode(false)}catch{};current=null}
 function enqueue(fn){queue=queue.then(fn).catch(()=>{});return queue}
 function cancel(){epoch++;return enqueue(async()=>{const id=current?.id;await clean();if(id)notify(id,'cancelled')})}
 function handle(msg){
  if(msg.action==='cancel')return cancel();
  if(!valid(msg.id)||disposed)return Promise.resolve();
  const generation=epoch;
  return enqueue(async()=>{
   if(disposed||generation!==epoch)return;
   if(msg.action==='start'){
    if(current){notify(msg.id,'error',{code:'busy'});return}
    current={id:msg.id};
    try{
     await closeCamera();
     requestingPermission=true;let granted;try{granted=await permission()}finally{requestingPermission=false}
     if(!granted)throw Object.assign(Error(),{code:'permission'});
     if(generation!==epoch||!active()){await clean();notify(msg.id,'cancelled');return}
     await mode(true);await recorder.prepareToRecordAsync();
     if(generation!==epoch||!active()){await clean();notify(msg.id,'cancelled');return}
     recorder.record();notify(msg.id,'recording');
     timer=schedule(()=>handle({action:'stop',id:msg.id}),60000);
    }catch(e){await clean();notify(msg.id,'error',{code:e.code==='permission'?'permission':'recording'})}
   }else if(msg.action==='stop'&&current?.id===msg.id){
    unschedule(timer);timer=null;
    try{
     await recorder.stop();const data=await read(recorder.uri);
     if(typeof data!=='string'||!data.length||data.length>2800000)throw Error('size');
     if(generation===epoch&&active())notify(msg.id,'complete',{base64:data,mime:'audio/mp4'});
    }catch{if(generation===epoch)notify(msg.id,'error',{code:'recording'})}
    finally{await clean()}
   }
  });
 }
 return{handle,cancel,get requestingPermission(){return requestingPermission},dispose(){disposed=true;return cancel()}};
}
