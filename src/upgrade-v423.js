// Phone-based prototype compatibility. No OTP or email login is introduced.
// This source is embedded by scripts/embed-html.mjs in both deliverables.
(()=>{
 const style=document.createElement('style');
 style.textContent=`:root{--brand:#087958;--brandSoft:#e5f5ee;--m:#60746c}body{background:#edf2f6}.phone{background:#f7fafc}.card{border:1px solid #e3eaf0;border-radius:20px;box-shadow:0 3px 16px #233e5210}.top h1{letter-spacing:-.6px}.btn{border-radius:14px;box-shadow:0 4px 12px #08795820}.inp{border:1px solid #d9e3e9;border-radius:13px;font-size:16px}.small{min-height:42px;border-radius:12px}.nav{background:#ffffffed;border-top:1px solid #e3eaf0;box-shadow:0 -5px 24px #233e520a}.nav button{min-height:56px}.msg{border-radius:18px 18px 18px 5px;overflow-wrap:anywhere;white-space:pre-wrap}.msg.mine{border-radius:18px 18px 5px 18px;background:#def4e8}.profileActionGrid{grid-template-columns:1fr 1fr}.profileActionGrid .btn{grid-column:1/-1}.chatavatar{flex-shrink:0}.chatSide{max-width:95px}.chatSide .meta{font-size:12px}.publicProfileHero{background:linear-gradient(135deg,#e5f6ee,#e8f0fd);border:1px solid #dfebed;border-radius:24px;padding:24px 16px}.cathead{border-radius:15px}.upgradeActions{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.upgradeActions button{flex:1}button:disabled{opacity:.55;cursor:wait}button:focus-visible,input:focus-visible,textarea:focus-visible{outline:3px solid #398cd9;outline-offset:2px}.upgradeError{color:#a83131}.reportDetails{white-space:pre-wrap;overflow-wrap:anywhere}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;animation:none!important;transition:none!important}}`;
 document.head.append(style);
 document.title='ჩემი უბანი v4.23.0';
 document.querySelectorAll('.appVersionBadge').forEach(x=>x.textContent='v4.23.0');
 document.querySelectorAll('.headerChatDot').forEach(x=>{x.textContent='';x.classList.add('hide')});
 const range=document.getElementById('radiusRange');if(range){range.value='2';range.max='5';range.setAttribute('aria-label','ბიზნესის ძიების რადიუსი კილომეტრებში')}
 document.getElementById('radiusLabel').textContent='2';document.getElementById('radiusHint').textContent='ნაჩვენებია ყველაფერი 2 კმ-ის ფარგლებში.';
 const blockButton=document.getElementById('publicProfileBlockBtn');if(blockButton)blockButton.textContent='⊘ დაბლოკვა';
 document.querySelector('[onclick="reportCurrentPublicProfile()"]')?.replaceChildren(document.createTextNode('⚑ საჩივარი'));
 // Load once, after location resolves; concurrent callers share the same promise.
 let refreshPromise=null,locationPromise=null,gpsReady=false;
 const locate=()=>{
  if(locationPromise)return locationPromise;
  locationPromise=new Promise((resolve,reject)=>{
   if(!navigator.geolocation)return reject(new Error('მდებარეობა მიუწვდომელია'));
   navigator.geolocation.getCurrentPosition(p=>{userCoords={lat:p.coords.latitude,lng:p.coords.longitude};gpsReady=true;resolve()},()=>reject(new Error('ბიზნესების საჩვენებლად ჩართე მდებარეობაზე წვდომა.')),{enableHighAccuracy:true,timeout:15000,maximumAge:30000});
  }).finally(()=>{locationPromise=null});return locationPromise;
 };
 window.businessLocationReady=()=>gpsReady;
 const oldRenderBusinesses=renderGroupedBusinesses;
 renderGroupedBusinesses=function(){
  if(!gpsReady){document.getElementById('businessList').innerHTML='<div class="card">მდებარეობის მოლოდინში…</div>';return}
  oldRenderBusinesses();
 };
 refreshBusinessList=function(){
  if(refreshPromise)return refreshPromise;
  refreshPromise=(async()=>{
   const status=document.getElementById('gpsStatus');status.textContent='მდებარეობისა და ობიექტების ჩატვირთვა…';
   try{await locate();await Promise.allSettled([fetchOpenStreetMapBusinesses(true),fetchPublicBusinesses(),renderBusinessBanners()]);renderGroupedBusinesses()}
   catch(e){status.textContent=e.message;document.getElementById('businessList').innerHTML='<div class="card"><p>ჩართე GPS და მიეცი აპს მდებარეობის გამოყენების უფლება.</p><button class="small" onclick="requestLocation()">ხელახლა ცდა</button></div>'}
  })().finally(()=>{refreshPromise=null});return refreshPromise;
 };
 requestLocation=refreshBusinessList;
 // Avoid the old watch + three navigation timers racing an initial GPS lookup.
 startBusinessLocationWatch=function(){};
 const baseRadius=setRadiusV413;
 setRadius=function(value){baseRadius(value);clearTimeout(window.__osmRadiusTimer);window.__osmRadiusTimer=setTimeout(async()=>{if(refreshPromise)await refreshPromise;refreshBusinessList()},450)};

 function screen(id,title,back){const el=document.createElement('section');el.id=id;el.className='s hide app';el.innerHTML=`<div class="top"><button class="small" onclick="go('${back}')">← უკან</button><h1>${title}</h1></div><div id="${id}Body"></div>`;document.querySelector('.phone').append(el)}
 screen('blockedUsers','დაბლოკილები','settings');screen('reportAdmin','საჩივრები','superPanel');
 const row=document.createElement('button');row.className='small';row.style.width='100%';row.textContent='⊘ დაბლოკილი მომხმარებლები';row.onclick=()=>go('blockedUsers');document.querySelector('#settings .card').append(row);
 const adminButton=document.createElement('button');adminButton.className='btn';adminButton.textContent='⚑ მომხმარებლების საჩივრები';adminButton.onclick=()=>go('reportAdmin');document.getElementById('superPanel').append(adminButton);
 async function rpc(name,args){const r=await sbRpc(name,{p_phone:normalizePhone(st.phone),...args});if(!r.ok||r.data?.ok===false)throw new Error(r.data?.message||r.error||'მოქმედება ვერ შესრულდა');return r.data}
 const failure=(el,e)=>{el.innerHTML=`<div class="card upgradeError">${esc(e.message)}<p>თუ განახლება ჯერ არ გაგიშვია, გაუშვი v4.23.0 SQL.</p></div>`};
 window.loadBlockedUsers=async function(){const el=document.getElementById('blockedUsersBody');el.textContent='იტვირთება…';try{const rows=await rpc('list_blocked_users',{});el.innerHTML='';if(!rows.length)el.innerHTML='<div class="card">დაბლოკილი მომხმარებელი არ გყავს.</div>';for(const u of rows){const card=document.createElement('div');card.className='card';card.innerHTML=`<b>${esc(u.full_name)}</b><div class="upgradeActions"></div>`;const actions=card.lastElementChild;const profile=document.createElement('button');profile.className='small';profile.textContent='პროფილი';profile.onclick=()=>openPublicProfileByPhone(u.phone);const unblock=document.createElement('button');unblock.className='small';unblock.textContent='განბლოკვა';unblock.onclick=async()=>{unblock.disabled=true;try{await rpc('set_user_block',{p_other_phone:u.phone,p_blocked:false});await loadBlockedUsers()}catch(e){alert(e.message);unblock.disabled=false}};actions.append(profile,unblock);el.append(card)}}catch(e){failure(el,e)}};
 window.loadReportAdmin=async function(){const el=document.getElementById('reportAdminBody');el.textContent='იტვირთება…';try{const rows=await rpc('list_user_reports_admin',{});el.innerHTML='';if(!rows.length)el.innerHTML='<div class="card">საჩივარი ჯერ არ არის.</div>';for(const r of rows){const card=document.createElement('div');card.className='card';card.innerHTML=`<b>${esc(r.reported_name)}</b><div class="meta">ავტორი: ${esc(r.reporter_name)} • ${esc(formatCloudDate(r.created_at))}</div><p>${esc(({spam:'სპამი',harassment:'შევიწროება',fraud:'თაღლითობა',inappropriate:'შეუსაბამო კონტენტი',other:'სხვა'})[r.category]||r.category)}</p><p class="reportDetails">${esc(r.details||'')}</p>`;const select=document.createElement('select');select.className='inp';select.setAttribute('aria-label','საჩივრის სტატუსი');for(const [value,label]of Object.entries({open:'ახალი',reviewing:'განიხილება',resolved:'დასრულებული',dismissed:'უარყოფილი'})){const o=document.createElement('option');o.value=value;o.textContent=label;select.append(o)}select.value=r.status;const save=document.createElement('button');save.className='small';save.textContent='სტატუსის შენახვა';save.onclick=async()=>{save.disabled=true;try{await rpc('review_user_report',{p_id:r.id,p_status:select.value});save.textContent='შენახულია'}catch(e){alert(e.message)}finally{save.disabled=false}};card.append(select,save);el.append(card)}}catch(e){failure(el,e)}};
 // Report form uses explicit confirmation; cancelling never submits a report.
 window.reportUserByPhone=function(phone,name){const sheet=document.createElement('div');sheet.className='sheet';sheet.innerHTML=`<div class="sheetbox"><h2>საჩივარი: ${esc(name||'მომხმარებელი')}</h2><label>მიზეზი<select class="inp"><option value="spam">სპამი</option><option value="harassment">შევიწროება</option><option value="fraud">თაღლითობა</option><option value="inappropriate">შეუსაბამო კონტენტი</option><option value="other">სხვა</option></select></label><label>აღწერა<textarea class="inp" maxlength="2000"></textarea></label><div class="upgradeActions"><button class="small">გაუქმება</button><button class="btn">გაგზავნა</button></div></div>`;const buttons=sheet.querySelectorAll('button');buttons[0].onclick=()=>sheet.remove();buttons[1].onclick=async()=>{buttons[1].disabled=true;try{await rpc('report_user',{p_other_phone:normalizePhone(phone),p_category:sheet.querySelector('select').value,p_details:sheet.querySelector('textarea').value.trim()||null});sheet.remove();alert('საჩივარი შენახულია განხილვისთვის.')}catch(e){alert(e.message);buttons[1].disabled=false}};document.body.append(sheet)};
 // Snapshot request identities. Do not paint an earlier conversation over a new one.
 let chatBusy=false,lastMessageSignature='',replyTarget=null;
 const replyBox=document.createElement('div');replyBox.className='card';replyBox.id='chatReplyComposer';replyBox.hidden=true;document.getElementById('mi').parentElement.before(replyBox);
 function paintReply(){replyBox.replaceChildren();replyBox.hidden=!replyTarget;if(!replyTarget)return;const text=document.createElement('p');text.textContent='პასუხი: '+(replyTarget.sender_name||'მომხმარებელი')+' — '+(replyTarget.body||'📷 ფოტო');const cancel=document.createElement('button');cancel.className='small';cancel.textContent='პასუხის გაუქმება';cancel.onclick=()=>{replyTarget=null;paintReply();saveDraft()};replyBox.append(text,cancel)}
 window.setChatReply=function(message){replyTarget={id:message.id,sender_name:String(message.sender_name||'').slice(0,100),body:String(message.body||'').slice(0,300)};paintReply();saveDraft();document.getElementById('mi').focus()};
 const uploadControllers=new Map();
 const outbox=new Map(),readWatermarks=new Map(),loads=new Map(),drafts=new Map();let diskOwner='',restoringDisk=null,diskChain=Promise.resolve(),clearingComposer=false;
 const conversationKey=()=>String(!!currentDirectThreadId)+':'+(currentDirectThreadId||currentCloudChatId||'');
 function diskWarning(){let warning=document.getElementById('chatDiskWarning');if(!warning){warning=document.createElement('div');warning.id='chatDiskWarning';warning.className='meta';document.getElementById('mi').parentElement.before(warning)}window.reportAppIssue?.('storage_failed');warning.textContent='მონახაზის ტელეფონში შენახვა ვერ მოხერხდა.'}
 function persistDisk(){if(!diskOwner)return Promise.resolve();const phone=diskOwner,snapshot={outbox:[...outbox.values()].map(r=>({...r,sending:false})),drafts:[...drafts]};diskChain=diskChain.catch(()=>{}).then(()=>window.chatDisk.put(phone,snapshot)).catch(()=>diskWarning());return diskChain}
 async function restoreDisk(){const phone=normalizePhone(st.phone);if(!phone||phone===diskOwner)return;if(restoringDisk)await restoringDisk;const task=(async()=>{const state=await window.chatDisk.get(phone).catch(()=>{diskWarning();return null});if(phone!==normalizePhone(st.phone))return;outbox.clear();drafts.clear();diskOwner=phone;for(const r of state?.outbox||[])if(r.phone===phone&&r.clientId&&r.id)outbox.set(r.clientId,{...r,sending:false});for(const [key,value]of state?.drafts||[])drafts.set(key,value)})();restoringDisk=task;try{await task}finally{if(restoringDisk===task)restoringDisk=null}}
 function saveDraft(){if(clearingComposer||!diskOwner||diskOwner!==normalizePhone(st.phone)||!(currentDirectThreadId||currentCloudChatId))return;drafts.set(conversationKey(),{body:document.getElementById('mi').value,photo:currentChatMessageImage||'',attachment:window.chatAttachment432?.get()||null,reply:replyTarget});return persistDisk()}
 window.saveChatDraft432=saveDraft;
 function restoreDraft(){const draft=drafts.get(conversationKey());if(!draft)return;window.chatAttachment432?.restore(draft.attachment);replyTarget=draft.reply||null;paintReply();document.getElementById('mi').value=draft.body||'';currentChatMessageImage=draft.photo||'';const preview=document.getElementById('chatMessageImagePreview');preview.replaceChildren();if(draft.photo){const img=document.createElement('img');img.className='uploadPreview';img.src=draft.photo;const remove=document.createElement('button');remove.className='small';remove.textContent='ფოტოს მოშორება';remove.onclick=()=>{clearChatMessageImage();saveDraft()};preview.append(img,remove)}}
 document.getElementById('mi').addEventListener('input',saveDraft);document.addEventListener('visibilitychange',()=>{if(document.hidden)saveDraft()});window.addEventListener('pagehide',saveDraft);
 new MutationObserver(()=>{if(!clearingComposer&&!document.getElementById('chat').classList.contains('hide'))saveDraft()}).observe(document.getElementById('chatMessageImagePreview'),{childList:true});
 const chat=document.getElementById('chat'),box=document.getElementById('msgs');
 const delivery=document.createElement('div');delivery.className='chatDelivery';delivery.setAttribute('role','status');box.after(delivery);
 const active=r=>r.phone===normalizePhone(st.phone)&&r.id===(r.direct?currentDirectThreadId:currentCloudChatId);
 function paintOutbox(){
  delivery.replaceChildren();
  for(const r of outbox.values())if(active(r)){
   const card=document.createElement('div');card.className='msg mine pendingMessage';card.dataset.clientId=r.clientId;
   if(r.reply){const quote=document.createElement('blockquote');quote.textContent='პასუხი: '+(r.reply.body||'📷 ფოტო');card.append(quote)}const body=document.createElement('div');body.textContent=r.body;card.append(body);
   if(r.photo){const img=document.createElement('img');img.className='uploadPreview';img.src=r.image||r.photo;img.alt='გასაგზავნი ფოტო';card.append(img)}
   if(r.attachment){const p=document.createElement('p');p.textContent=r.attachment.name||'📍 მდებარეობა';card.append(p)}
   const state=document.createElement('div');state.className='meta uploadState434';state.textContent=r.sending?(r.uploading?'იტვირთება… '+(r.progress||0)+'%':'იგზავნება…'):(r.paused?'შეჩერებულია • დანართი შენახულია':'ვერ გაიგზავნა');card.append(state);
   if(r.sending&&r.uploading){const progress=document.createElement('progress');progress.max=100;progress.value=r.progress||0;progress.setAttribute('aria-label','დანართის ატვირთვა');const cancel=document.createElement('button');cancel.className='small';cancel.textContent='ატვირთვის შეჩერება';cancel.onclick=()=>{r.paused=true;uploadControllers.get(r.clientId)?.abort()};card.append(progress,cancel)}
   if(!r.sending){const retry=document.createElement('button');retry.className='small';retry.textContent='↻ ხელახლა გაგზავნა';retry.disabled=chatBusy;retry.onclick=()=>transmit(r);card.append(retry)}
   delivery.append(card);
  }
 }
 const erasing436=new Set();
 const history=new Map(),hasOlder=new Map(),browsingHistory=new Set();const latest=document.createElement('button');latest.className='small';latest.textContent='ბოლო შეტყობინებებზე დაბრუნება';latest.hidden=true;box.before(latest);const older=document.createElement('button');older.className='small';older.textContent='ძველი შეტყობინებები';box.before(older);
 async function messages(direct,previous=false){
  const id=direct?currentDirectThreadId:currentCloudChatId,phone=normalizePhone(st.phone),key=phone+':'+direct+':'+id;
  if(!id||!phone||document.hidden||erasing436.has(key))return;if(!previous&&browsingHistory.has(key))return;if(loads.has(key))return loads.get(key);
  const task=(async()=>{
   const cached=history.get(key)||[],first=cached[0];if(previous&&!first)return;
   const r=await sbRpc('conversation_page',{p_kind:direct?'direct':'group',p_id:id,p_before:previous?first.created_at:null,p_before_id:previous?first.id:null});
   if(!active({direct,id,phone})||chat.classList.contains('hide'))return;
   if(!r.ok)return; // Polling failures never overwrite the conversation or pending messages.
   const page=Array.isArray(r.data)?r.data:[],overlap=!cached.length||page.some(m=>m.id===cached.at(-1)?.id),retained=previous?cached:page.length===50&&!overlap?[]:cached.filter(m=>!page.length||m.created_at<page[0].created_at),byId=new Map(retained.map(m=>[m.id,m]));for(const m of page)byId.set(m.id,m);const rows=[...byId.values()].sort((a,b)=>a.created_at.localeCompare(b.created_at)||String(a.id).localeCompare(String(b.id)));if(rows.length>200){if(previous)rows.splice(200);else rows.splice(0,rows.length-200)}history.delete(key);history.set(key,rows);while(history.size>6){const oldest=history.keys().next().value;history.delete(oldest);hasOlder.delete(oldest);readWatermarks.delete(oldest);browsingHistory.delete(oldest)}if(previous)browsingHistory.add(key);latest.hidden=!browsingHistory.has(key);if(previous||cached.length===0||!hasOlder.has(key)||!overlap)hasOlder.set(key,page.length===50);older.hidden=!hasOlder.get(key);const signature=key+JSON.stringify(rows);
   if(signature!==lastMessageSignature){
    const scroller=document.getElementById('chatDock446')?box:chat,height=scroller.scrollHeight,top=scroller.scrollTop,nearBottom=!previous&&(!lastMessageSignature||scroller.scrollHeight-scroller.scrollTop-scroller.clientHeight<180);lastMessageSignature=signature;
    box.innerHTML=rows.map(m=>`<div data-message-id="${esc(m.id)}" class="msg ${normalizePhone(m.sender_phone)===phone?'mine':''}"><b>${esc(m.sender_name)}</b>${m.body?'<br>'+esc(m.body):''}${m.image_url?`<img class="uploadPreview" src="${esc(m.image_url)}" alt="ჩატის ფოტო">`:''}<div class="meta">${esc(formatCloudDate(m.created_at))}${normalizePhone(m.sender_phone)===phone?(m.peer_read?' • ✓✓ წაკითხულია':' • ✓ გაგზავნილია'):''}</div></div>`).join('')||'<div class="msg">დაწერე პირველი შეტყობინება.</div>';
    window.decorateConversationRows?.(rows);paintOutbox();if(previous)scroller.scrollTop=top+scroller.scrollHeight-height;else if(nearBottom)scroller.scrollTop=scroller.scrollHeight;
   }
   const through=rows.at(-1)?.created_at;
   if(through&&readWatermarks.get(key)!==through){const marked=await sbRpc('mark_conversation_read_v423',{p_phone:phone,p_kind:direct?'direct':'group',p_id:id,p_through:through});if(marked.ok){readWatermarks.set(key,through);refreshMessagingBadge()}}
  })().catch(()=>{}).finally(()=>loads.delete(key));loads.set(key,task);return task;
 }
 latest.onclick=()=>{const key=normalizePhone(st.phone)+':'+!!currentDirectThreadId+':'+(currentDirectThreadId||currentCloudChatId);browsingHistory.delete(key);history.delete(key);latest.hidden=true;return messages(!!currentDirectThreadId)};
 older.onclick=async()=>{older.disabled=true;try{await messages(!!currentDirectThreadId,true)}finally{older.disabled=false}};
 loadDirectMessages=()=>messages(true);loadCloudChatMessages=()=>messages(false);
 const oldDirect=openDirectChat;
 function clearComposer(){window.chatAttachment432?.clear();replyTarget=null;paintReply();window.clearConversationTools?.();browsingHistory.clear();latest.hidden=true;clearingComposer=true;older.hidden=true;delivery.replaceChildren();clearChatMessageImage();document.getElementById('mi').value='';box.textContent='იტვირთება…';lastMessageSignature=''}
 openDirectChat=async function(id,other){await restoreDisk();await saveDraft();clearComposer();await oldDirect(id,other);restoreDraft();clearingComposer=false;paintOutbox()};
 openCloudChat=async function(id,name){await restoreDisk();await saveDraft();clearComposer();currentDirectThreadId='';currentCloudChatId=String(id);currentCloudChatName=name||'ჯგუფური ჩათი';document.getElementById('chatTitle').textContent=currentCloudChatName;document.getElementById('chatInfoTitle').textContent=currentCloudChatName;document.getElementById('chatPhotoPreview').textContent=currentCloudChatName.slice(0,2);go('chat');restoreDraft();clearingComposer=false;paintOutbox();await Promise.all([messages(false),loadCloudChatMemberCount()])};
 async function transmit(request){
  if(chatBusy||request.phone!==normalizePhone(st.phone))return;
  chatBusy=true;request.sending=true;request.paused=false;request.uploading=false;request.progress=0;const controller=new AbortController();uploadControllers.set(request.clientId,controller);const options={signal:controller.signal,onProgress:n=>{request.progress=n;for(const card of delivery.children)if(card.dataset.clientId===request.clientId){const progress=card.querySelector('progress');if(progress)progress.value=n;const state=card.querySelector('.uploadState434');if(state&&request.uploading)state.textContent='იტვირთება… '+n+'%'}}};const button=document.querySelector('#chatSend432, #chat > .btn');button.disabled=true;button.textContent='იგზავნება…';paintOutbox();
  try{
   if(request.photo&&!request.image){request.uploading=true;paintOutbox();request.image=await window.uploadChatPhoto434(request,options);await persistDisk()}
   if(request.phone!==normalizePhone(st.phone))return;
   if(request.attachment){request.uploading=!!request.attachment.blob&&!request.attachment.path;paintOutbox();request.attachment=await window.uploadChatAttachment432(request,options);await persistDisk()}
   request.uploading=false;paintOutbox();if(controller.signal.aborted||request.phone!==normalizePhone(st.phone))return;
   const r=request.attachment?await sbRpc('send_chat_attachment_v432',{p_kind:request.direct?'direct':'group',p_id:request.id,p_body:request.body||null,p_attachment:request.attachment,p_client_id:request.clientId,p_reply_to:request.reply?.id||null}):await sbRpc(request.reply?'send_chat_message_v429':'send_chat_message_verified',{...(request.reply?{p_reply_to:request.reply.id}:{}),p_kind:request.direct?'direct':'group',p_id:request.id,p_body:request.body||null,p_image_url:request.image,p_client_id:request.clientId});
   if(!r.ok||r.data?.ok===false)throw Error('Send failed');
   outbox.delete(request.clientId);await persistDisk();if(active(request)){browsingHistory.clear();latest.hidden=true;lastMessageSignature='';await messages(request.direct)}
  }catch(e){request.sending=false;if(e.name==='AbortError')request.paused=true}
  finally{uploadControllers.delete(request.clientId);chatBusy=false;request.sending=false;request.uploading=false;await persistDisk();button.disabled=false;button.textContent='გაგზავნა';paintOutbox()}
 }
 send=async function(){
  if(chatBusy||erasing436.size)return;await restoreDisk();if(chatBusy||erasing436.size)return;
  const direct=!!currentDirectThreadId,id=direct?currentDirectThreadId:currentCloudChatId,phone=normalizePhone(st.phone),input=document.getElementById('mi'),body=input.value.trim(),photo=currentChatMessageImage,attachment=window.chatAttachment432?.get()||null;
  if(!id||(!body&&!photo&&!attachment))return;if(body.length>5000)return alert('შეტყობინება მაქსიმუმ 5000 სიმბოლოა.');
  const request={direct,id,phone,body,photo,attachment,reply:replyTarget?{...replyTarget}:null,image:null,clientId:crypto.randomUUID(),sending:false};outbox.set(request.clientId,request);
  window.chatAttachment432?.clear();input.value='';replyTarget=null;paintReply();clearChatMessageImage();drafts.delete(conversationKey());await persistDisk();const task=transmit(request);chat.scrollTop=chat.scrollHeight;return task;
 };

 window.eraseConversation436=async(kind,id,mutate)=>{
  await restoreDisk();const phone=normalizePhone(st.phone),direct=kind==='direct',key=phone+':'+direct+':'+id;
  if([...outbox.values()].some(r=>r.id===id&&r.sending))throw Error('დაელოდე მიმდინარე გაგზავნის დასრულებას.');
  if(erasing436.has(key))return;erasing436.add(key);
  try{await loads.get(key);await mutate();if(phone!==normalizePhone(st.phone))return;
   for(const[k,r]of outbox)if(r.id===id&&r.direct===direct){uploadControllers.get(k)?.abort();outbox.delete(k)}
   drafts.delete(String(direct)+':'+id);history.delete(key);hasOlder.delete(key);readWatermarks.delete(key);browsingHistory.delete(key);
   if(active({phone,direct,id})){clearingComposer=true;clearComposer();box.replaceChildren();clearingComposer=false;currentDirectThreadId='';currentCloudChatId='';}
   await persistDisk();
  }finally{erasing436.delete(key)}
 };
 const oldPick=pickChatMessageImage;pickChatMessageImage=function(input){const f=input.files?.[0];if(f&&(!/^image\/(jpeg|png|webp|heic|heif)$/.test(f.type)||f.size>10*1024*1024)){input.value='';return alert('აირჩიე ფოტო, მაქსიმუმ 10 MB.')}oldPick(input)};
 const oldLogout=logoutUser;logoutUser=function(){for(const c of uploadControllers.values())c.abort();uploadControllers.clear();const owner=diskOwner;diskOwner='';if(owner)diskChain=diskChain.catch(()=>{}).then(()=>window.chatDisk.remove(owner)).catch(()=>{});drafts.clear();outbox.clear();history.clear();hasOlder.clear();readWatermarks.clear();currentDirectThreadId='';currentCloudChatId='';directChatsCache=[];clearComposer();document.getElementById('directChatList').innerHTML='';document.getElementById('chatList').innerHTML='';window.ReactNativeWebView?.postMessage(JSON.stringify({type:'unregisterPush'}));oldLogout()};
 const oldGo=go;go=function(id){oldGo(id);if(id==='blockedUsers')loadBlockedUsers();if(id==='reportAdmin')loadReportAdmin()};
 // Notification clicks distinguish chat activity from a post notification.
 const oldNotifications=renderCloudNotifications;
 renderCloudNotifications=async function(){
  const el=document.getElementById('notificationList');if(!el||!st.phone)return;
  try{const rows=await sbListNotifications();el.innerHTML='';if(!rows.length)el.textContent='ახალი შეტყობინება არ არის.';
   for(const n of rows){const item=document.createElement('div');item.className='notifitem '+(n.is_read?'':'unseen');item.innerHTML=`<b>${esc(n.title)}</b><div class="meta">${esc(n.body||'')} • ${esc(formatCloudDate(n.created_at))}</div>`;item.onclick=()=>window.openActivity(n.id);el.append(item)}refreshCloudNotificationBadge();
  }catch(e){el.textContent='შეტყობინებები ვერ ჩაიტვირთა. სცადე ხელახლა.'}
 };
 const baseSafety=refreshPublicProfileSafety;refreshPublicProfileSafety=async function(){await baseSafety();const el=document.getElementById('publicProfileBlockBtn');if(el)el.textContent=el.textContent==='↻'?'↻ განბლოკვა':'⊘ დაბლოკვა'};
 // Keep all profiles cross-district. Guard late responses while switching people.
 let profileOpening=false;const baseProfile=openPublicProfileByPhone;
 openPublicProfileByPhone=async function(phone){if(profileOpening)return;profileOpening=true;try{await baseProfile(phone)}finally{profileOpening=false}};
 const basePush=requestPushFoundation;
 requestPushFoundation=function(){if(appNotificationsEnabled&&st.phone)basePush()};
 const baseToggle=toggleAppNotifications;
 toggleAppNotifications=function(){baseToggle();if(appNotificationsEnabled)requestPushFoundation();else window.ReactNativeWebView?.postMessage(JSON.stringify({type:'unregisterPush'}))};
 const oldFinish=finishLogin;finishLogin=async function(){await oldFinish();requestPushFoundation()};
 window.handlePushRegistration=async function(token){if(!st.phone)return;const r=await sbRpc('register_push_device',{p_phone:normalizePhone(st.phone),p_token:token});if(!r.ok)console.warn('Push token registration unavailable');else window.ReactNativeWebView?.postMessage(JSON.stringify({type:'pushRegistered',phone:normalizePhone(st.phone)}))};
 window.handlePushOpen=function(){if(st.phone)go('notifications')};
 document.addEventListener('visibilitychange',()=>{if(!document.hidden&&st.phone){refreshMessagingBadge();refreshCloudNotificationBadge()}});
 appPoll.add('badges',30000,()=>!!st.phone,()=>Promise.allSettled([refreshMessagingBadge(),refreshCloudNotificationBadge()]));
})();
