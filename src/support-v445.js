// A tap only opens a verified direct thread. The user writes and sends their own message.
(()=>{
 const {el,button,rpc}=ui432;let pending=null,epoch=0;
 const card=button('',()=>openSupportChat445());card.id='supportHome445';card.className='card';
 const title=document.createElement('strong'),description=document.createElement('span'),arrow=document.createElement('span');
 title.textContent='იდეა ან პრობლემა გაქვს?';description.textContent='მოგვწერე ადმინისტრატორს';arrow.textContent='↗';arrow.setAttribute('aria-hidden','true');
 const copy=document.createElement('span');copy.append(title,description);card.append(copy,arrow);
 (el('marketHome444')||el('home').querySelector('.neighborhoodHero')).after(card);
 const style=document.createElement('style');style.textContent='#supportHome445{display:flex;width:100%;align-items:center;justify-content:space-between;gap:16px;text-align:left;background:#f1f6f3;color:#174b39;border:1px solid #d4e5dc;padding:17px 18px;margin:0 0 18px;border-radius:18px}#supportHome445 strong,#supportHome445 span span{display:block}#supportHome445 strong{font-size:16px;margin-bottom:5px}#supportHome445 span span{font-size:13px;color:#536b61}#supportHome445>span:last-child{font-size:24px}#supportHome445:disabled{opacity:.6}';document.head.append(style);
 window.openSupportChat445=function(){
  if(pending)return pending;const phone=st.phone,run=epoch;if(!phone)return;if(normalizePhone(phone)==='500000000'){go('groups');setMessageTab('direct');return;}
  card.disabled=true;
  const request=(async()=>{try{const result=await rpc('start_support_chat_v445',{});if(phone!==st.phone||run!==epoch)return;
   await openDirectChat(result.id,result.other);if(phone!==st.phone||run!==epoch)return;el('mi').placeholder='მოგვწერე შენი იდეა ან პრობლემა…';el('mi').focus();
  }catch{if(phone===st.phone&&run===epoch)alert('ადმინისტრატორთან ჩათი ვერ გაიხსნა. სცადე ხელახლა.');}
  finally{if(run===epoch){pending=null;card.disabled=false;}}})();pending=request;return request;
 };
 const logout=logoutUser;logoutUser=function(){epoch++;pending=null;card.disabled=false;logout()};
})();
