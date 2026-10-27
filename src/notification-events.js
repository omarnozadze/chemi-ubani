// Live hot-news feed and category-aware navigation. Server enforces publishing rights.
(()=>{
 let generation=0,news=[],filter='ყველა',publishing=false;
 const feed=document.getElementById('hotNewsFeed');
 const render=()=>{
  feed.replaceChildren();
  const rows=news.filter(n=>filter==='ყველა'||n.category===filter).sort((a,b)=>Number(!!b.pinned)-Number(!!a.pinned)||new Date(b.created_at)-new Date(a.created_at)||String(b.id).localeCompare(String(a.id))); 
  if(!rows.length){feed.textContent='ცხელი ამბავი ჯერ არ გამოქვეყნებულა.';return}
  for(const n of rows){const card=document.createElement('article');card.className='card hotItem';card.dataset.newsId=n.id;if(n.campaign_id){card.dataset.adId=n.campaign_id;card.classList.add('serverAd')}
   for(const [tag,value] of [['div',[n.category,n.city,n.district,n.neighborhood].filter(Boolean).join(' • ')],['h3',n.title],['p',n.body],['small',formatCloudDate(n.created_at)]]){const e=document.createElement(tag);e.textContent=value;card.append(e)}
   if(n.image_url){const img=document.createElement('img');img.src=n.image_url;img.className='uploadPreview';img.alt=n.title;card.append(img)}
   if(n.pinned){const badge=document.createElement('p');badge.className='pinnedNews444';badge.textContent='📌 აპინული';card.prepend(badge)}
   if(n.can_pin){const pin=document.createElement('button');pin.className='small';pin.textContent=n.pinned?'აპინის მოხსნა':'აპინვა';pin.setAttribute('aria-pressed',String(!!n.pinned));pin.onclick=async()=>{if(pin.disabled)return;pin.disabled=true;const owner=st.phone;try{const r=await sbRpc('pin_hot_news_v444',{p_id:n.id,p_pinned:!n.pinned,p_expected:!!n.pinned});if(owner!==st.phone)return;if(!r.ok||r.data?.ok===false)throw Error('აპინვა ვერ შესრულდა. განაახლე სია და სცადე ხელახლა.');n.pinned=!!r.data.pinned;render()}catch(e){if(owner===st.phone){const error=document.createElement('p');error.setAttribute('role','alert');error.textContent=e.message;card.append(error)}}finally{pin.disabled=false}};card.append(pin)}
   feed.append(card);
  }
 };
 window.loadHotNews=async()=>{
  const request=++generation,phone=st.phone;filter='ყველა';document.querySelectorAll('#hotFilters .filter').forEach((b,i)=>b.classList.toggle('on',i===0));news=[];feed.textContent='იტვირთება…';
  const r=await sbRpc('list_hot_news',{});
  if(request!==generation||phone!==st.phone)return;
  if(!r.ok){feed.textContent='ამბები ვერ ჩაიტვირთა. ხელახლა გახსენი გვერდი.';return}
  news=Array.isArray(r.data)?r.data:[];render();

 };
 window.setHotFilter=(btn,value)=>{filter=value;document.querySelectorAll('#hotFilters .filter').forEach(b=>b.classList.toggle('on',b===btn));render()};
 const previousGo=go;go=function(id){previousGo(id);if(id==='hotNews')window.loadHotNews().catch(()=>{feed.textContent='ამბები ვერ ჩაიტვირთა.'})};
 const previousOpen=openCloudNotificationV417;
 openCloudNotificationV417=async function(id,kind,postId,row){
  const target={direct_message:'groups',group_message:'groups',daily_photo:'dailyMoment',hot_news:'hotNews',service_order:'specialistCabinet',service_order_update:'myOrders'}[kind];
  if(!target)return previousOpen(id,kind,postId,row);
  try{await sbMarkNotificationRead(id)}catch{}
  row?.classList.remove('unseen');go(target);
 };
 // Local advertisement previews must not masquerade as published hot news.
 const previousAd=activateAdDemo;
 activateAdDemo=function(ad){const placement=ad.placement;try{ad.placement=placement.replace('ცხელი ამბები','');previousAd(ad)}finally{ad.placement=placement}if(placement.includes('ცხელი ამბები'))alert('ცხელ ამბებში გამოსაქვეყნებლად გამოიყენე ცხელი ამბების გამოქვეყნების ფორმა.')};
 document.title='ჩემი უბანი v4.23.3';document.querySelectorAll('.appVersionBadge').forEach(x=>x.textContent='v4.23.3');
 feed.textContent='ცხელი ამბები გვერდის გახსნისას ჩაიტვირთება.';
})();
