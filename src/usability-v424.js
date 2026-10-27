// Verified notification routing, order guidance and shared image handling.
(()=>{
 const style=document.createElement('style');style.textContent=`.activityFocus{outline:3px solid #087958;outline-offset:3px}.orderNext{width:100%;padding:12px;background:#eef7f3;border-radius:12px;line-height:1.6}.orderSteps{display:flex;gap:5px;margin-top:8px}.orderSteps span{height:5px;flex:1;background:#d5dfdb;border-radius:5px}.orderSteps .complete{background:#087958}.uploadStatus{position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:#163e32;color:white;padding:12px 18px;border-radius:14px;z-index:9999;max-width:90%;text-align:center}.imageRetry{display:block;margin:8px auto}.chatDelivery{padding:8px 4px;line-height:1.5}`;document.head.append(style);
 const next={consultation_requested:'სპეციალისტმა უნდა მიიღოს ან უარყოს მოთხოვნა.',accepted:'სპეციალისტი შეათანხმებს სამუშაოს და გამოგზავნის ფასს.',offer_sent:'დამკვეთმა უნდა განიხილოს და დაადასტუროს ფასი.',funds_held:'სპეციალისტი ასრულებს სამუშაოს.',work_done_pending:'დამკვეთმა უნდა დაადასტუროს შესრულება ან გახსნას დავა.',done:'სამუშაო დასრულებულია. დამკვეთს შეუძლია შეფასების დატოვება.',disputed:'დავა ადმინისტრატორის განხილვას ელოდება.',cancelled:'შეკვეთა გაუქმებულია.',refunded:'შეკვეთა თანხის დაბრუნების სტატუსით დაიხურა.'};
 const stages=['consultation_requested','accepted','offer_sent','funds_held','work_done_pending','done'];
 function guide(o){const step=stages.indexOf(o.status);return `<div class="orderNext" data-order-id="${esc(o.id)}"><b>შემდეგი ნაბიჯი</b><div>${esc(next[o.status]||'განაახლე შეკვეთა სტატუსის სანახავად.')}</div>${step<0?'':`<div class="orderSteps" aria-label="ეტაპი ${step+1} / 6">${stages.map((_,i)=>`<span class="${i<=step?'complete':''}"></span>`).join('')}</div>`}</div>`}
 const customer=customerOrderActions,provider=providerCloudActions;
 customerOrderActions=o=>guide(o)+customer(o);providerCloudActions=o=>guide(o)+provider(o);
 let pending=null,routeSerial=0;
 const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
 function focusTarget(screen,id){if(!uuid(id))return;const root=document.getElementById(screen);if(!root)return;
  const find=()=>{let el=root.querySelector(`[data-order-id="${id}"],[data-news-id="${id}"],[data-moment-id="${id}"]`)||document.getElementById('dailyComments-'+id);if(!el)return false;el=el.closest('.card,.dailyMomentCard')||el;el.classList.add('activityFocus');el.scrollIntoView({block:'center',behavior:'smooth'});setTimeout(()=>el.classList.remove('activityFocus'),6000);return true};
  if(find())return;const observer=new MutationObserver(()=>{if(find())observer.disconnect()});observer.observe(root,{childList:true,subtree:true});setTimeout(()=>observer.disconnect(),10000);
 }
 window.openActivity=async function(id){
  if(!uuid(id)){go('notifications');return false}
  if(!st.phone){pending=id;return false}
  const phone=st.phone,serial=++routeSerial;const r=await sbRpc('resolve_notification',{p_id:id});
  if(phone!==st.phone||serial!==routeSerial)return false;
  if(!r.ok||!r.data){go('notifications');alert('შეტყობინება ვერ გაიხსნა. სცადე ხელახლა.');return false}
  const t=r.data;
  if(t.screen==='chat'&&uuid(t.id)){if(t.kind==='direct')await openDirectChat(t.id,t.other);else await openCloudChat(t.id,t.name);if(phone!==st.phone||serial!==routeSerial)return false;if(uuid(t.messageId))await window.focusChatMessage?.(t.messageId)}
  else if(t.screen==='locationRequests435'&&window.openLocationRequests435){await openLocationRequests435(!!t.manage)}
  else if(t.screen==='civicIssues434'&&uuid(t.id)&&window.openCivicReport434){await openCivicReport434(t.id)}
  else if(t.screen==='dailyMoment'){if(uuid(t.id)&&window.openDailyTarget)await window.openDailyTarget(t.id);else{openDailyMoment();focusTarget(t.screen,t.id)}}
  else if(t.screen==='home'){if(uuid(t.postId)&&window.openPostTarget)await window.openPostTarget(t.postId);else go('home')}
  else if(['myOrders','specialistCabinet','orderReview441'].includes(t.screen)&&uuid(t.id)&&window.openOrderDetail441){await window.openOrderDetail441(t.id)}
  else if(['myOrders','specialistCabinet','hotNews','notifications','specialistAdsAdmin','businessAdmin','myListings'].includes(t.screen)){if(t.screen==='specialistCabinet')proOrderFilter='all';go(t.screen);focusTarget(t.screen,t.id)}
  else go('notifications');
  if(t.unavailable)alert('ეს ჩანაწერი წაიშალა ან მასზე წვდომა აღარ გაქვს.');
  refreshCloudNotificationBadge();return true;
 };
 window.handlePushOpen=function(data){const id=data?.notificationId;if(!st.phone){pending=uuid(id)?id:'list';return}if(uuid(id))openActivity(id);else go('notifications')};
 const finish=finishLogin;finishLogin=async function(){await finish();if(st.phone&&pending){const id=pending;pending=null;if(id==='list')go('notifications');else await openActivity(id)}};
 const logout=logoutUser;logoutUser=function(){pending=null;routeSerial++;logout()};
 // Native camera images and all existing upload pickers share compression and status.
 const upload=sbUploadDataImage;let activeUploads=0;
 const status=document.createElement('div');status.className='uploadStatus hide';status.setAttribute('role','status');status.setAttribute('aria-live','polite');document.body.append(status);
 async function smaller(data){
  if(!data.startsWith('data:image/'))return data;
  const img=new Image();await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(Error('ფოტო ვერ დამუშავდა. აირჩიე JPG ან PNG ფოტო.'));img.src=data});
  const scale=Math.min(1,1600/Math.max(img.naturalWidth,img.naturalHeight));const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.naturalWidth*scale));canvas.height=Math.max(1,Math.round(img.naturalHeight*scale));const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);const result=canvas.toDataURL('image/jpeg',.8);canvas.width=canvas.height=1;return result.length<data.length?result:data;
 }
 sbUploadDataImage=async function(data,bucket){if(!data||/^https?:/.test(data))return upload(data,bucket);activeUploads++;status.classList.remove('hide');status.textContent='ფოტო მუშავდება…';try{const compact=await smaller(data);status.textContent='ფოტო იტვირთება…';return await upload(compact,bucket)}finally{if(--activeUploads===0)status.classList.add('hide')}};
 sbUploadPostImage=data=>sbUploadDataImage(data,'post-images');
 function images(root){for(const img of [...(root.matches?.('img:not([data-loading-ready])')?[root]:[]),...root.querySelectorAll('img:not([data-loading-ready])')]){img.dataset.loadingReady='1';img.decoding='async';if(!img.src.startsWith('data:'))img.loading='lazy';img.addEventListener('error',()=>{if(img.nextElementSibling?.classList.contains('imageRetry'))return;const b=document.createElement('button');b.className='small imageRetry';b.textContent='ფოტოს ჩატვირთვა თავიდან';b.onclick=e=>{e.stopPropagation();b.remove();const src=img.src;img.removeAttribute('src');img.src=src};img.after(b)});img.addEventListener('load',()=>{if(img.nextElementSibling?.classList.contains('imageRetry'))img.nextElementSibling.remove()})}}
 let scheduled=false;const added=new Set();new MutationObserver(records=>{for(const r of records)for(const n of r.addedNodes)if(n.nodeType===1)added.add(n);if(scheduled||!added.size)return;scheduled=true;requestAnimationFrame(()=>{scheduled=false;for(const root of added)if(root.isConnected)images(root);added.clear()})}).observe(document.body,{childList:true,subtree:true});images(document);
 document.title='ჩემი უბანი v4.24.0';document.querySelectorAll('.appVersionBadge').forEach(x=>x.textContent='v4.24.0');
})();
