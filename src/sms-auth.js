// SMS authentication for the WebView. Never treat saved profile data as a session.
(() => {
 const SESSION_KEY='chemiUbaniVerifiedSession';
 window.getActivitySession=async()=>{const token=await accessToken();return token&&session?.user?.id?{token,userId:session.user.id}:null};
 let session=null, refreshing=null, activeFlow=null, sessionEpoch=0, restoring=null;
 const nativeFetch=window.fetch.bind(window);
 async function requestJSON(url,options){
  const controller=new AbortController();let timer;
  const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new Error('კავშირის დრო ამოიწურა. შეამოწმე ინტერნეტი და სცადე ხელახლა.'));},15000)});
  try{return await Promise.race([(async()=>{const response=await nativeFetch(url,{...options,signal:controller.signal});const data=await response.json().catch(()=>({}));return{response,data}})(),timeout]);}
  finally{clearTimeout(timer)}
 }

 function e164(value){const p=normalizePhone(value);if(!/^5\d{8}$/.test(p))throw new Error('შეიყვანე ქართული მობილურის 9-ნიშნა ნომერი');return '+995'+p;}
 function saveSession(value){if(!value)sessionEpoch++;session=value;try{if(value)localStorage.setItem(SESSION_KEY,JSON.stringify(value));else localStorage.removeItem(SESSION_KEY)}catch{}}
 async function authCall(path,body,token){
  const {response,data}=await requestJSON(SUPABASE_URL+'/auth/v1/'+path,{method:'POST',headers:{apikey:SUPABASE_ANON_KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
  if(!response.ok){const error=new Error(response.status===429?'ცოტა ხანში სცადე თავიდან.':path==='verify'?'კოდი არასწორია ან ვადა გაუვიდა.':data.error_code==='phone_provider_disabled'?'SMS-ით შესვლა ჯერ არ არის ჩართული.':'მოთხოვნა ვერ შესრულდა. სცადე თავიდან.');error.status=response.status;throw error;}
  return data;
 }
 async function accessToken(force=false){
  if(!session)return null;
  if(!force&&session.expires_at>Date.now()/1000+60)return session.access_token;
  if(!refreshing){
   const snapshot=session,epoch=sessionEpoch;
   const task=authCall('token?grant_type=refresh_token',{refresh_token:snapshot.refresh_token}).then(data=>{
    if(epoch!==sessionEpoch||session!==snapshot)throw new Error('Session changed');
    if(!data.access_token||!data.refresh_token)throw new Error('Session refresh unavailable');
    saveSession({...data,expires_at:data.expires_at||Date.now()/1000+data.expires_in});return data.access_token;
   }).catch(error=>{if(epoch===sessionEpoch&&session===snapshot&&(error.status===400||error.status===401))saveSession(null);throw error}).finally(()=>{if(refreshing===task)refreshing=null});
   refreshing=task;
  }
  return refreshing;
 }
 window.fetch=async function(input,init={}){
  const url=typeof input==='string'?input:input.url;
  if(url.startsWith(SUPABASE_URL+'/rest/v1/')||url.startsWith(SUPABASE_URL+'/storage/v1/')||url.startsWith(SUPABASE_URL+'/functions/v1/')){
   const token=await accessToken();
   const headers=new Headers(init.headers||(typeof input!=='string'?input.headers:undefined));
   headers.set('Authorization','Bearer '+(token||SUPABASE_ANON_KEY));
   return nativeFetch(input,{...init,headers});
  }
  return nativeFetch(input,init);
 };
 const dialog=document.createElement('dialog');
 dialog.setAttribute('aria-labelledby','smsTitle');
 dialog.style.cssText='border:0;border-radius:20px;padding:24px;max-width:360px;width:calc(100% - 48px);box-sizing:border-box;background:#fff;color:#183d2d';
 dialog.innerHTML='<form method="dialog"><h2 id="smsTitle">ნომრის დადასტურება</h2><p id="smsPhone"></p><label for="smsCode">SMS-კოდი</label><input id="smsCode" inputmode="numeric" autocomplete="one-time-code" maxlength="10" style="width:100%;box-sizing:border-box;margin:12px 0;padding:12px"/><p id="smsStatus" role="status" aria-live="polite"></p><button id="smsVerify" type="button">დადასტურება</button><button id="smsResend" type="button">კოდის თავიდან გაგზავნა</button><button id="smsCancel" type="button">გაუქმება</button></form>';
 document.body.append(dialog);
 const status=dialog.querySelector('#smsStatus'), code=dialog.querySelector('#smsCode'), verify=dialog.querySelector('#smsVerify'), resend=dialog.querySelector('#smsResend');
 dialog.addEventListener('close',()=>{if(activeFlow){activeFlow.resolve(false);activeFlow=null}});
 async function sendCode(){
  const flow=activeFlow;if(!flow||flow.busy)return;
  if(Date.now()<flow.nextSend){status.textContent='თავიდან გაგზავნამდე ცოტა ხანს დაელოდე.';return;}
  flow.busy=true;verify.disabled=resend.disabled=true;status.textContent='კოდი იგზავნება…';
  try{await authCall('otp',{phone:flow.phone,channel:'sms',create_user:!flow.force});if(activeFlow!==flow)return;flow.sent=true;flow.nextSend=Date.now()+60000;status.textContent='შეიყვანე SMS-ით მიღებული კოდი.';code.focus()}catch(e){if(activeFlow===flow)status.textContent=e.message}finally{flow.busy=false;if(activeFlow===flow){verify.disabled=!flow.sent;resend.disabled=false}}
 }
 resend.onclick=sendCode;
 dialog.querySelector('#smsCancel').onclick=()=>dialog.close();
 dialog.querySelector('form').onsubmit=e=>{e.preventDefault();verify.click()};
 verify.onclick=async()=>{
  const flow=activeFlow;if(!flow||flow.busy||!flow.sent)return;
  if(!/^\d{6,10}$/.test(code.value.trim())){status.textContent='შეიყვანე SMS-კოდი.';return;}
  flow.busy=true;verify.disabled=resend.disabled=true;
  try{
   const data=await authCall('verify',{phone:flow.phone,token:code.value.trim(),type:'sms'});
   if(activeFlow!==flow)return;
   if(!data.access_token||!data.refresh_token)throw new Error('შესვლა ვერ დასრულდა.');
   if(flow.expectedUser&&data.user?.id!==flow.expectedUser)throw Error('ანგარიში შეიცვალა. თავიდან შედი.');
   saveSession({...data,expires_at:data.expires_at||Date.now()/1000+data.expires_in});
   activeFlow=null;dialog.close();flow.resolve(true);
  }catch(e){if(activeFlow===flow)status.textContent=e.message}finally{flow.busy=false;if(activeFlow===flow)verify.disabled=resend.disabled=false}
 };
 async function confirmPhone(phone,force=false){
  let full;try{full=e164(phone)}catch(e){alert(e.message);return false}
  if(activeFlow)return false;
  if(!force&&session&&normalizePhone(session.user?.phone)===normalizePhone(phone)&&await accessToken())return true;
  if(!force)saveSession(null);
  return new Promise(resolve=>{activeFlow={phone:full,force,expectedUser:force?session?.user?.id:null,resolve,nextSend:0,busy:false,sent:false};code.value='';dialog.querySelector('#smsPhone').textContent=full;dialog.showModal();sendCode()});
 }
 window.reauthenticateForDeletion436=()=>confirmPhone(st.phone,true);
 async function ownProfile(){
  const epoch=sessionEpoch;
  let token=await accessToken();if(!token)throw new Error('Session unavailable');
  const read=token=>requestJSON(SUPABASE_URL+'/rest/v1/rpc/get_verified_profile',{method:'POST',headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:'{}'});
  let result=await read(token);
  if(result.response.status===401){token=await accessToken(true);result=await read(token)}
  const {response,data:profile}=result;
  if(epoch!==sessionEpoch)throw new Error('Session changed');
  if(!response.ok){if(response.status===401||response.status===403)saveSession(null);throw new Error('პროფილის ჩატვირთვა ვერ მოხერხდა.')}
  if(epoch!==sessionEpoch)throw new Error('Session changed');return profile;
 }
 // Remove both demo-admin and local-profile fallback paths.
 loginUser=async function(){
  const phone=document.getElementById('loginPhone')?.value||'';
  try{if(!await confirmPhone(phone))return;const profile=await ownProfile();if(!profile){alert('ამ ნომერზე პროფილი ჯერ არ არის. გაიარე რეგისტრაცია.');return}applyRemoteProfile(profile,phone);await finishLogin()}catch(e){alert(e.message)}
 };
 const previousReg=reg;
 reg=async function(){if(!nm.value.trim())return alert('შეიყვანე სახელი');try{if(await confirmPhone(ph.value))await previousReg()}catch(e){alert(e.message)}};
 supabasePhoneExists=async function(phone){if(!session||normalizePhone(session.user?.phone)!==normalizePhone(phone))return null;try{return !!await ownProfile()}catch{return null}};
 registerProfileRemote=async function(){const r=await sbRpc('sms_register_profile',{p_full_name:st.name,p_district:st.district||null,p_neighborhood:st.neigh||null});return r.ok?r.data:{ok:false,error:r.error}};
 const previousFinish=finishLogin;
 finishLogin=async function(){
  if(!session||normalizePhone(session.user?.phone)!==normalizePhone(st.phone)||!await accessToken()){go('welcome');return}
  if(!st._pendingRemoteRegistration){const profile=await ownProfile();if(!profile){go('welcome');return}applyRemoteProfile(profile,st.phone)}
  await previousFinish();
 };
 const previousLogout=logoutUser;
 logoutUser=async function(){
  const token=session?.access_token;
  saveSession(null);refreshing=null;
  if(activeFlow){activeFlow.resolve(false);activeFlow=null;dialog.close()}
  restorePanel.classList.add('hide');previousLogout();
  // Local logout is immediate, even offline. Use the captured token for cleanup.
  if(token){
   await Promise.allSettled([requestJSON(SUPABASE_URL+'/rest/v1/rpc/unregister_my_push_devices',{method:'POST',headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:'{}'}),authCall('logout',{},token)]);
  }
 };
 const restorePanel=document.createElement('div');
 restorePanel.className='hide';
 restorePanel.style.cssText='position:fixed;inset:0;z-index:99999;background:#f7fafc;display:grid;place-content:center;padding:24px;text-align:center';
 restorePanel.id='sessionRestorePanel';
 restorePanel.innerHTML='<style>@keyframes sessionSpin{to{transform:rotate(360deg)}}#sessionRestoreSpinner{width:30px;height:30px;border:3px solid #dcebe2;border-top-color:#087a4b;border-radius:50%;margin:12px auto;animation:sessionSpin .9s linear infinite}#sessionRestoreLogo{width:110px;height:110px;object-fit:cover;border-radius:26px;margin:0 auto 14px}#sessionRestorePanel h2{color:#087a4b;margin:0 0 8px}</style><img id="sessionRestoreLogo" alt="ჩემი უბანი"><h2>ჩემი უბანი</h2><div id="sessionRestoreSpinner" aria-hidden="true"></div><p id="sessionRestoreStatus" role="status">შენი უბანი იტვირთება…</p><button id="sessionRestoreRetry" class="btn hide">ხელახლა ცდა</button><button id="sessionRestoreLogout" class="small hide">გასვლა ანგარიშიდან</button>';
 restorePanel.querySelector('#sessionRestoreLogo').src=document.getElementById('welcome')?.querySelector('img')?.getAttribute?.('src')||'';
 function restoreLoading(busy){restorePanel.setAttribute('aria-busy',String(busy));for(const id of ['#sessionRestoreRetry','#sessionRestoreLogout'])restorePanel.querySelector(id).classList[busy?'add':'remove']('hide');restorePanel.querySelector('#sessionRestoreSpinner').classList[busy?'remove':'add']('hide')}

 document.body.append(restorePanel);
 const restoreStatus=restorePanel.querySelector('#sessionRestoreStatus');
 restorePanel.querySelector('#sessionRestoreRetry').onclick=()=>window.restoreVerifiedLogin();
 restorePanel.querySelector('#sessionRestoreLogout').onclick=()=>logoutUser();
 window.restoreVerifiedLogin=function(){
  if(restoring)return restoring;
  if(!session){try{const saved=JSON.parse(localStorage.getItem(SESSION_KEY)||'null');if(saved?.access_token&&saved?.refresh_token)session=saved}catch{saveSession(null)}}
  if(!session){go('welcome');return Promise.resolve()}
  const epoch=sessionEpoch;
  restorePanel.classList.remove('hide');restoreLoading(true);restoreStatus.textContent='შენი უბანი იტვირთება…';
  restoring=(async()=>{
   try{
    const profile=await ownProfile();if(epoch!==sessionEpoch)return;
    if(!profile){restoreLoading(false);restoreStatus.textContent='ამ ნომერზე პროფილი ვერ მოიძებნა. გასვლის შემდეგ გაიარე რეგისტრაცია.';return}
    applyRemoteProfile(profile,profile.phone);await finishLogin();
    if(epoch===sessionEpoch)restorePanel.classList.add('hide');
   }catch{
    if(!session){restorePanel.classList.add('hide');go('welcome')}
    else if(epoch===sessionEpoch){restoreLoading(false);restoreStatus.textContent='შესვლა დამახსოვრებულია. შეამოწმე ინტერნეტი და სცადე ხელახლა.'}
   }
  })().finally(()=>{restoring=null});
  return restoring;
 };
 window.addEventListener('online',()=>{if(session&&!restorePanel.classList.contains('hide'))window.restoreVerifiedLogin()});
 window.restoreVerifiedLogin();
})();
