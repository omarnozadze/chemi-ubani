(()=>{
 const el=id=>document.getElementById(id);
 const style=document.createElement('style');style.id='fixes442';style.textContent=`
 #chat{padding-top:0!important;padding-bottom:18px!important;scroll-padding-top:84px}
 #chat>.top{display:grid!important;grid-template-columns:44px minmax(0,1fr) 44px;align-items:center!important;position:sticky!important;top:0!important;z-index:25;gap:10px!important;margin:0 -8px 12px!important;padding:12px 8px!important;background:#fff!important;border-radius:0 0 18px 18px;box-shadow:0 3px 12px #103c2510}
 #chat>.top>div{min-width:0;text-align:left}
 #chat>.top h1{font-size:17px!important;line-height:1.35!important;margin:0!important;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 #chatMemberCount{font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 #chat>.top>button{display:grid;place-items:center;min-width:44px;width:44px;height:44px;padding:0!important;border-radius:50%;line-height:1}
 #chatComposeRow435{position:sticky;bottom:0;z-index:20;align-items:center!important;box-shadow:0 2px 16px #123b2210}
 #chatComposer432{min-width:0;align-items:center!important}
 #chatSend432{display:grid!important;place-items:center!important;position:relative;flex:0 0 44px!important;width:44px!important;height:44px!important;min-width:44px!important;max-width:44px!important;min-height:44px!important;max-height:44px!important;padding:0!important;margin:0!important;align-self:center!important;line-height:0!important;font-size:0!important;border-radius:50%!important}
 #chatSend432::after{content:''!important;display:block!important;position:absolute;inset:0;width:22px;height:22px;margin:auto!important;transform:none!important;background:center/22px 22px no-repeat url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m21 3-6.5 18-4-7.5L3 9.5 21 3ZM21 3 10.5 13.5'/%3E%3C/svg%3E")}
 #chatSend432:disabled{opacity:.55}
 #msgs .replyAction442{display:grid;place-items:center;width:36px;height:32px;min-width:36px;min-height:32px;margin:6px 0 0 auto;padding:0!important;border:1px solid #c9d8d0;border-radius:16px;background:transparent;color:#466657;box-shadow:none}
 #pushStatusCard442{margin-top:12px;padding:14px;border:1px solid #d9e6df;border-radius:16px;background:#f5faf7}
 #pushStatusCard442 p{margin:6px 0;font-size:14px;line-height:1.5}
 `;document.head.append(style);
 const back=el('chat')?.querySelector('.top>button');if(back){back.textContent='←';back.setAttribute('aria-label','უკან');back.title='უკან';}
 const info=el('chat')?.querySelector('.top>button:last-child');if(info)info.setAttribute('aria-label','ჩათის ინფორმაცია');
 const labels={idle:'შეტყობინებების კავშირი მოწმდება.',connecting:'შეტყობინებების კავშირი მოწმდება…',retrying:'შეტყობინებების სერვისი დროებით მიუწვდომელია. კავშირს ფონურად ხელახლა ვცდით.',unavailable:'შეტყობინებების კავშირი ვერ დამყარდა. შეამოწმე ინტერნეტი და Google Play services, შემდეგ სცადე ხელახლა.',denied:'შეტყობინებების ნებართვა გამორთულია. ჩართე ტელეფონის პარამეტრებში.',ready:'მოწყობილობა რეგისტრირებულია შეტყობინებების მისაღებად.'};
 let state='idle',stateOwner='';const card=document.createElement('div');card.id='pushStatusCard442';const title=document.createElement('b');title.textContent='შეტყობინებების კავშირი';const status=document.createElement('p');status.setAttribute('role','status');const retry=document.createElement('button');retry.className='small';retry.textContent='კავშირის ხელახლა შემოწმება';card.append(title,status,retry);el('settings').append(card);
 const current=()=>normalizePhone(st.phone||'');
 function render(){const native=!!window.ReactNativeWebView;card.hidden=!native;status.textContent=!appNotificationsEnabled?'აპის შეტყობინებები გამორთულია.':labels[stateOwner===current()?state:'idle'];retry.disabled=!appNotificationsEnabled||stateOwner===current()&&state==='connecting';}
 window.setPushStatus442=(next,phone)=>{if(phone!==current()||!appNotificationsEnabled)return;if(!labels[next])return;if(next==='unavailable'&&(state!==next||stateOwner!==phone))window.reportAppIssue?.('push_failed','push_registration');state=next;stateOwner=phone;render();};
 requestPushFoundation=function(manual=false){if(!st.phone||!appNotificationsEnabled)return;window.ReactNativeWebView?.postMessage(JSON.stringify({type:'registerPush',phone:current(),manual:manual===true}));};
 retry.onclick=()=>requestPushFoundation(true);
 window.handlePushRegistration=async function(token,phone,requestId){let ok=false;try{if(!phone||phone!==current()||!appNotificationsEnabled)return;const r=await sbRpc('register_push_device',{p_phone:phone,p_token:token});ok=phone===current()&&appNotificationsEnabled&&r.ok&&r.data?.ok!==false;}catch{}finally{window.ReactNativeWebView?.postMessage(JSON.stringify({type:'pushRegistered',phone,requestId,ok:!!ok}));}};
 const settings=renderSettings;renderSettings=function(){settings();render();};
 const logout=logoutUser;logoutUser=function(){state='idle';stateOwner='';logout();render();};render();
})();
