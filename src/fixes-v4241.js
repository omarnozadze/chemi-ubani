// Field-test fixes: Georgia day boundary, scrollable chat, truthful location details.
(()=>{
 const style=document.createElement('style');style.textContent=`#chat>.top{position:sticky;top:0;z-index:30;background:#f7fafc;margin-top:0;padding:10px 0;border-bottom:1px solid #e3eaf0}#chat{scroll-padding-top:90px}.pendingMessage .small{display:block;margin-top:8px}.cathead{width:100%;text-align:left}.distance{white-space:nowrap;color:#087958;font-weight:600}.businessTitle{overflow-wrap:anywhere}.businessCard{cursor:pointer}.businessCard:focus-visible{outline:3px solid #398cd9}`;document.head.append(style);
 const offset=4*3600000,dayMs=86400000;
 function visible(created,now=Date.now()){const t=new Date(created).getTime();return Number.isFinite(t)&&t<=now&&Math.floor((t+offset)/dayMs)===Math.floor((now+offset)/dayMs)&&(now+offset)%dayMs<dayMs-60000}
 window.dailyVisibleAt=visible;
 let boundaryTimer;
 function purge(){dailyMoments=dailyMoments.filter(m=>visible(m.created_at))}
 const own=renderDailyOwnComposer,feed=renderDailyFeed;
 renderDailyOwnComposer=function(){purge();own()};renderDailyFeed=function(){purge();feed()};
 todayIso=()=>dailyMemoryKey(new Date());
 dailyStreakCount=function(){const days=new Set(dailyMemories.map(m=>dailyMemoryKey(m.created_at)));let cursor=Date.parse(todayIso()+'T00:00:00Z'),streak=0;if(!days.has(todayIso()))cursor-=dayMs;while(days.has(new Date(cursor).toISOString().slice(0,10))){streak++;cursor-=dayMs}return streak};
 function scheduleBoundary(){clearTimeout(boundaryTimer);const now=Date.now(),start=Math.floor((now+offset)/dayMs)*dayMs-offset,cutoff=start+dayMs-60000,target=now<cutoff?cutoff:start+dayMs;
  boundaryTimer=setTimeout(()=>{purge();renderDailyOwnComposer();renderDailyFeed();if(st.phone)refreshDailyHomeStatus();scheduleBoundary()},Math.max(1,target-now));
 }
 document.addEventListener('visibilitychange',()=>{if(!document.hidden){purge();renderDailyOwnComposer();renderDailyFeed();scheduleBoundary();if(st.phone&&!document.getElementById('dailyMoment').classList.contains('hide'))loadDailyMoments()}});scheduleBoundary();
 const oldStatus=refreshDailyHomeStatus;
 refreshDailyHomeStatus=async function(){await oldStatus();const el=document.getElementById('dailyHomeStatus');if(el)el.textContent=el.textContent.replaceAll('ბოლო 12 საათში','დღეს')};
 const note=document.createElement('div');note.className='meta';note.textContent='დღის ფოტოები ქრება საქართველოს დროით 23:59-ზე. შენი ფოტოები რჩება „კალენდარში“.';document.getElementById('dailyFeedPane').prepend(note);
 window.formatBusinessDistance=function(km){if(!Number.isFinite(km))return 'მანძილი უცნობია';return km<1?Math.round(km*1000)+' მ':km.toFixed(1)+' კმ'};
 const coords=b=>b.lat!=null&&b.lng!=null&&String(b.lat).trim()!==''&&String(b.lng).trim()!==''&&Number.isFinite(Number(b.lat))&&Number.isFinite(Number(b.lng))&&Math.abs(Number(b.lat))<=90&&Math.abs(Number(b.lng))<=180;
 const distance=b=>coords(b)?kmBetween(userCoords.lat,userCoords.lng,Number(b.lat),Number(b.lng)):Infinity;
 const button=(label,fn)=>{const b=document.createElement('button');b.type='button';b.className='small';b.textContent=label;b.onclick=e=>{e.stopPropagation();fn()};return b};
 function showOsm(b){
  const root=document.getElementById('bizDetailBody');root.replaceChildren();const card=document.createElement('div');card.className='card';
  for(const[tag,value]of [['h2',b.name||'ობიექტი'],['p',b.cat],['p',b.address],['p',b.opening_hours?'სამუშაო საათები: '+b.opening_hours:''],['p',b.approximate?'რუკაზე მონიშნულია ობიექტის ტერიტორიის მიახლოებითი ცენტრი.':'კოორდინატები რუკის წყაროდან.']]){if(!value)continue;const e=document.createElement(tag);e.textContent=value;card.append(e)}
  if(coords(b))card.append(button('🧭 მარშრუტი',()=>window.openBusinessRoute?openBusinessRoute(b.lat,b.lng):openMap(b.lat,b.lng,b.name)));
  if(b.phone&&/^[+\d\s()-]+$/.test(b.phone))card.append(button('☎ დარეკვა',()=>window.open('tel:'+b.phone.replace(/[^+\d]/g,''),'_blank')));
  if(/^https?:\/\//i.test(b.website||''))card.append(button('🌐 საიტი',()=>window.open(b.website,'_blank')));
  root.append(card);go('businessDetail');window.showNearbyDetailRoute453?.(b,card);
 }
 openBusiness=function(name){const matches=businessData.filter(x=>x.name===name);const b=businessData.find(x=>x.osmId===name)||(matches.length===1?matches[0]:null);if(b)showOsm(b);else alert('აირჩიე კონკრეტული ობიექტი სიიდან.')};
 // Each collapsed category creates only a header; expand to create its cards.
 const previousRender=renderGroupedBusinesses;
 renderGroupedBusinesses=function(){
  if(!window.businessLocationReady()){previousRender();return}
  const root=document.getElementById('businessList');
  const q=(document.getElementById('bizSearch').value||'').trim().toLowerCase();
  const rows=[...cloudBusinesses.map(b=>({...b,source:'cloud'})),...businessData.map(b=>({...b,source:'osm'}))].map(b=>({...b,groupCat:normalizeBusinessCategory(b.category||b.cat),dist:window.nearbyRouteDistance449?nearbyRouteDistance449(b,distance(b)):distance(b)})).filter(b=>b.dist<=(maxRadiusKm===0?.05:maxRadiusKm)&&(bizQuickCat==='ყველა'||bizQuickCat===b.groupCat)&&(!q||[b.name,b.groupCat,b.address].some(v=>String(v||'').toLowerCase().includes(q)))).sort((a,b)=>a.dist-b.dist);
  root.replaceChildren();const groups=new Map();for(const b of rows){if(!groups.has(b.groupCat))groups.set(b.groupCat,[]);groups.get(b.groupCat).push(b)}
  for(const[cat,items]of groups){const group=document.createElement('div');group.className='catgroup';const expanded=openCats.has(cat)||!!q;const header=button(`${businessCategoryIcon(cat)} ${cat} • ${items.length} ${expanded?'▴':'▾'}`,()=>toggleCat(cat));header.className='cathead';header.setAttribute('aria-expanded',String(expanded));group.append(header);
   if(expanded){const list=document.createElement('div');list.className='catitems';for(const b of items){const card=document.createElement('article');card.className='card businessCard';card.dataset.routeLat=b.lat;card.dataset.routeLng=b.lng;card.tabIndex=0;card.setAttribute('role','button');const open=()=>b.source==='cloud'?openCloudBusinessDetail(b.id):showOsm(b);card.onclick=open;card.onkeydown=e=>{if(e.target===card&&['Enter',' '].includes(e.key)){e.preventDefault();open()}};
    const title=document.createElement('b');title.className='businessTitle';title.textContent=b.name||'სახელი მითითებული არ არის';const addr=document.createElement('div');addr.className='meta';addr.textContent=b.address||'';const dist=document.createElement('div');dist.className='distance';dist.textContent='⌖ '+formatBusinessDistance(b.dist)+(b.approximate?' • მიახლოებითი':'');dist.title='პირდაპირი მანძილი შენი მდებარეობიდან';if(window.nearbyRouteLabel449){dist.textContent=nearbyRouteLabel449(b,distance(b));dist.title=dist.textContent;}const badge=document.createElement('span');badge.className='businessBadge447';badge.textContent=b.icon||businessCategoryIcon(b.groupCat);if(/^https:\/\//i.test(b.image_url||'')){const img=document.createElement('img');img.src=b.image_url;img.alt=b.name||'ობიექტი';img.loading='lazy';img.referrerPolicy='no-referrer';img.onerror=()=>img.remove();badge.append(img);}card.append(badge,title,addr,dist);
    const rating=document.createElement('div');rating.className='meta';rating.textContent=b.source==='cloud'&&Number(b.rating_count)>0?`⭐ ${Number(b.avg_rating).toFixed(1)} • ${b.rating_count} შეფასება`:b.source==='cloud'?'შეფასება ჯერ არ არის':'შეფასება წყაროში ხელმისაწვდომი არ არის';if(b.source==='cloud'&&Number(b.rating_count)>0)card.append(rating);
    card.append(button('🧭 მარშრუტი',()=>window.openBusinessRoute?openBusinessRoute(b.lat,b.lng):openMap(b.lat,b.lng,b.name)));list.append(card)
   }group.append(list)}root.append(group)
  }
  if(!rows.length){const empty=document.createElement('p');empty.textContent='ამ რადიუსში ობიექტი ვერ მოიძებნა.';root.append(empty)}
  const attribution=document.createElement('p');attribution.className='meta';attribution.textContent='OpenStreetMap + „ჩემი უბანი“ • გზის მანძილი მხოლოდ დათვლილი მარშრუტისთვის';root.append(attribution);
 };
 // Ratings are real user submissions for approved businesses, never OSM demo stars.
 const publicBusinesses=fetchPublicBusinesses;let ratingRefresh=null;
 fetchPublicBusinesses=async function(){const phone=st.phone;await publicBusinesses();if(!ratingRefresh)ratingRefresh=sbRpc('list_business_rating_summaries',{}).finally(()=>{ratingRefresh=null});const r=await ratingRefresh;if(phone!==st.phone)return;if(r.ok&&Array.isArray(r.data)){const byId=new Map(r.data.map(x=>[String(x.id),x]));cloudBusinesses=cloudBusinesses.map(b=>({...b,...byId.get(String(b.id))}));renderGroupedBusinesses()}};
 const cloudDetail=openCloudBusinessDetail;openCloudBusinessDetail=function(id){cloudDetail(id);const b=cloudBusinesses.find(x=>String(x.id)===String(id));if(!b)return;const label=document.createElement('p');label.className='distance';label.textContent='';document.getElementById('bizDetailBody').prepend(label);window.showNearbyDetailRoute453?.(b,label)};
 // Refresh cached role on profile entry, using only the verified server profile.
 let profileRefresh=null;
 const navigate=go;go=function(id){navigate(id);if(id==='profile'&&st.phone&&!profileRefresh){const phone=st.phone;profileRefresh=sbRpc('get_verified_profile',{}).then(r=>{const p=Array.isArray(r.data)?r.data[0]:r.data;if(r.ok&&p&&phone===st.phone){st.role=(p.is_super_admin||p.admin_level==='super')?'super':p.admin_level==='district_admin'?'district':p.admin_level==='moderator'?'moderator':'user';renderRole()}}).catch(()=>{}).finally(()=>{profileRefresh=null})}};
 const endSession=logoutUser;logoutUser=function(){dailyMoments=[];dailyMemories=[];dailyCameraBack='';dailyCameraFront='';endSession()};
 document.title='ჩემი უბანი v4.24.1';document.querySelectorAll('.appVersionBadge').forEach(e=>e.textContent='v4.24.1');
})();
