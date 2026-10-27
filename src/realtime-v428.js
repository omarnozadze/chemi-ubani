// Private broadcast only invalidates views. All data still passes verified RPC authorization.
// Supabase Realtime protocol 1.0.0; no CDN dependency and no message bodies in broadcasts.
(()=>{
 let socket=null,epoch=0,retry=null,heartbeat=null,deadline=null,attempt=0,connecting=false,ref=0,topic='',joinRef='',lastToken='',awaiting=null;
 const available=()=>!!st.phone&&!document.hidden&&navigator.onLine!==false&&window.appNativeActive!==false;
 function healthy(value){window.activityConnected=value;for(const name of ['direct-chat','group-chat'])window.appPoll?.interval(name,value?60000:5000);window.appPoll?.interval('badges',value?120000:30000)}
 function stop(){epoch++;connecting=false;clearTimeout(retry);clearTimeout(deadline);clearInterval(heartbeat);retry=heartbeat=deadline=null;awaiting=null;const old=socket;socket=null;if(old){old.onclose=old.onmessage=old.onopen=old.onerror=null;old.close()}healthy(false)}
 function fail(){stop();if(available())retry=setTimeout(()=>{retry=null;connect()},Math.min(60000,1000*2**Math.min(attempt++,6))*(.8+Math.random()*.4))}
 function send(event,payload,t=topic){const id=String(++ref);socket.send(JSON.stringify({topic:t,event,payload,ref:id,join_ref:t==='phoenix'?null:joinRef}));return id}
 async function connect(){if(!available()){stop();return}if(socket||connecting||retry)return;connecting=true;const version=epoch;
 try{const session=await window.getActivitySession?.();if(version!==epoch||!available())return;if(!session){connecting=false;return}lastToken=session.token;topic='realtime:activity:'+session.userId;joinRef=String(++ref);
 const ws=new WebSocket(SUPABASE_URL.replace(/^http/,'ws')+'/realtime/v1/websocket?apikey='+encodeURIComponent(SUPABASE_ANON_KEY)+'&vsn=1.0.0');socket=ws;connecting=false;deadline=setTimeout(fail,10000);
 ws.onopen=()=>{if(socket!==ws)return;ws.send(JSON.stringify({topic,event:'phx_join',payload:{config:{private:true,broadcast:{ack:false,self:false},presence:{enabled:false},postgres_changes:[]},access_token:lastToken},ref:joinRef,join_ref:joinRef}))};
 ws.onmessage=e=>{if(socket!==ws)return;let m;try{m=JSON.parse(e.data)}catch{return}if(m.event==='phx_reply'&&m.ref===joinRef){if(m.payload?.status!=='ok'){fail();return}clearTimeout(deadline);healthy(true);attempt=0;window.handleActivitySignal?.();heartbeat=setInterval(async()=>{if(!available()){stop();return}if(awaiting){fail();return}try{const fresh=await window.getActivitySession?.();if(socket!==ws)return;if(!fresh||'realtime:activity:'+fresh.userId!==topic){fail();return}if(fresh.token!==lastToken){lastToken=fresh.token;send('access_token',{access_token:lastToken})}awaiting=send('heartbeat',{},'phoenix')}catch{if(socket===ws)fail()}},20000)}
 else if(m.event==='phx_reply'&&m.ref===awaiting)awaiting=null;
 else if(m.topic===topic&&m.event==='broadcast'&&m.payload?.event==='activity')window.handleActivitySignal?.();
 else if(m.event==='phx_error'||m.event==='phx_close')fail()};ws.onerror=()=>{if(socket===ws)fail()};ws.onclose=()=>{if(socket===ws)fail()};
 }catch{if(version===epoch)fail()}finally{if(version===epoch)connecting=false}}
 window.activityConnection=()=>{if(!available())stop();else connect()};document.addEventListener('visibilitychange',window.activityConnection);window.addEventListener('online',window.activityConnection);window.addEventListener('offline',window.activityConnection);
 const navigate=go;go=function(id){navigate(id);window.activityConnection()};const logout=logoutUser;logoutUser=function(){stop();attempt=0;logout()};
})();
