// v444: direct specialist conversations, no checkout, prominent marketplace.
(()=>{
 const {el,button,rpc}=ui432;
 const css=document.createElement('style');css.textContent=`
 #marketHome444{display:flex;align-items:center;justify-content:space-between;width:100%;text-align:left;padding:20px;margin:14px 0 20px;border:1px solid #bdd9c6;background:linear-gradient(120deg,#e4f5dc,#f6fbef);border-radius:22px;color:#124630;box-shadow:0 5px 16px #123c2310}
 #marketHome444 strong{display:block;font-size:22px;margin-bottom:5px}#marketHome444 span{font-size:14px}#marketHome444 .marketArrow444{font-size:30px;margin-left:12px}
 .pinnedNews444{color:#087958;font-weight:700;font-size:13px}#serviceChatContext432{display:none!important}
 `;document.head.append(css);
 const market=el('home').querySelector('[onclick="openMarketplace()"]');if(market){const b=button('',()=>openMarketplace());b.id='marketHome444';const copy=document.createElement('div'),title=document.createElement('strong'),sub=document.createElement('span'),arrow=document.createElement('span');title.textContent='მარკეტი';sub.textContent='იყიდე და გაყიდე შენს ახლოს';arrow.textContent='›';arrow.className='marketArrow444';copy.append(title,sub);b.append(copy,arrow);market.remove();el('home').querySelector('.neighborhoodHero').after(b)}
 document.querySelectorAll('[onclick*="pickPostType"],[onclick*="setFeedFilter"]').forEach(b=>{if(b.getAttribute('onclick').includes('იყიდება'))b.remove()});
 const pick=pickPostType;pickPostType=function(b,type){if(type==='იყიდება'){openMarketplace();return}return pick(b,type)};
 // Remove obsolete payment/checkout destinations after all legacy initializers ran.
 const blocked=new Set(['paymentCenter','financeAdmin','serviceOrder']);
 document.querySelectorAll('[onclick]').forEach(e=>{const a=e.getAttribute('onclick');if(/openPaymentCenter|managePaymentMethod|openFinanceAdmin|renderFinanceAdmin|go\(['"](?:paymentCenter|financeAdmin)['"]\)/.test(a))e.remove()});
 for(const id of blocked)el(id)?.remove();
 const navigate=go;go=function(id){if(blocked.has(id)){navigate('specialists');renderSpecialists();return}navigate(id)};
 openPaymentCenter=managePaymentMethod=openFinanceAdmin=()=>{};
 for(const name of ['approveProtectedPayment','confirmCloudPayment','renderPaymentCenter','renderFinanceAdmin','savePaymentMethod','releasePayout','refundOrder'])if(typeof window[name]==='function')window[name]=()=>{};
 // Keep historical order records available, but remove payment claims from their UI.
 document.querySelectorAll('.paymentShield').forEach(e=>e.remove());
 let pending=null;
 window.openRequest432=async function(id){
  if(pending)return pending;
  const owner=st.phone;if(!owner)return;
  const buttons=[...document.querySelectorAll('[data-ad-id] button')].filter(x=>x.closest('[data-ad-id]').dataset.adId===String(id)&&x.textContent==='მიწერა');buttons.forEach(x=>x.disabled=true);
  pending=(async()=>{try{const result=await rpc('start_specialist_chat_v444',{p_ad_id:id});if(st.phone!==owner)return;await openDirectChat(result.id,result.other);if(st.phone!==owner)return;el('mi').placeholder='მიწერე სპეციალისტს, რა გჭირდება…';el('mi').focus();}catch(e){if(st.phone===owner)alert(e.message||'მიმოწერა ვერ გაიხსნა. სცადე ხელახლა.')}finally{buttons.forEach(x=>x.disabled=false);pending=null}})();return pending;
 };
 openCloudServiceOrder=id=>id?openRequest432(id):go('specialists');openServiceOrder=openCloudServiceOrder;
 el('refreshBusinessBtn')?.remove();
 osmAddress=function(tags={}){const parts=[tags['addr:street'],tags['addr:housenumber']].filter(Boolean);return parts.join(' ')||tags['addr:full']||tags['addr:place']||'მისამართი წყაროში მითითებული არ არის'};
 const logout=logoutUser;logoutUser=function(){pending=null;logout()};
})();
