// Account-bound server preferences replace the unconditional device schedule.
(()=>{
 let loadedPhone='',pending=null,generation=0,toggling=false;
 const state=()=>document.getElementById('settingsPhotoReminderState');
 function paint(){const node=state();if(node)node.textContent=loadedPhone===st.phone?(dailyPhotoReminderEnabled?'08:00 / 20:00 • ჩართული ›':'გამორთული ›'):'მოწმდება…'}
 function cancelLegacy(){try{window.ReactNativeWebView?.postMessage(JSON.stringify({type:'setDailyPhotoReminder',enabled:false}))}catch{}}
 const render=renderSettings;renderSettings=function(){render();paint()};
 syncDailyPhotoReminder=function(){cancelLegacy();const phone=st.phone,run=generation;if(!phone)return Promise.resolve();if(loadedPhone===phone)return Promise.resolve();if(pending?.phone===phone)return pending.promise;
  const promise=(async()=>{try{let r=await sbRpc('daily_reminder_preference',{p_enabled:null});if(phone!==st.phone||run!==generation)return;if(!r.ok)throw Error();if(r.data===null){const saved=localStorage.getItem('chemiUbaniDailyPhotoReminder:'+phone)??localStorage.getItem('chemiUbaniDailyPhotoReminder');r=await sbRpc('daily_reminder_preference',{p_enabled:saved!=='off'});if(!r.ok)throw Error()}if(phone!==st.phone||run!==generation)return;if(typeof r.data?.enabled!=='boolean')throw Error();dailyPhotoReminderEnabled=r.data.enabled;loadedPhone=phone;paint()}catch{if(phone===st.phone&&run===generation&&state())state().textContent='ვერ შემოწმდა • ხელახლა ცდა ›'}finally{if(run===generation)pending=null}})();pending={phone,promise};return promise;
 };
 toggleDailyPhotoReminder=async function(){if(toggling||!st.phone)return;const phone=st.phone,run=generation,wasLoaded=loadedPhone===st.phone;toggling=true;try{await syncDailyPhotoReminder();if(!wasLoaded)return;if(loadedPhone!==phone||phone!==st.phone||run!==generation)return;const next=!dailyPhotoReminderEnabled;state().textContent='ინახება…';const r=await sbRpc('daily_reminder_preference',{p_enabled:next});if(phone!==st.phone||run!==generation)return;if(!r.ok||typeof r.data?.enabled!=='boolean')throw Error();dailyPhotoReminderEnabled=r.data.enabled;localStorage.setItem('chemiUbaniDailyPhotoReminder:'+phone,dailyPhotoReminderEnabled?'on':'off');paint()}catch{if(phone===st.phone&&run===generation){paint();alert('შეხსენების პარამეტრი ვერ შეინახა. სცადე ხელახლა.')}}finally{if(run===generation)toggling=false}};
 const row=state()?.closest('.menurow');if(row){const note=document.createElement('p');note.className='meta';note.textContent='საქართველოს დროით 08:00 და 20:00 — მხოლოდ მაშინ, თუ დღევანდელი ფოტო არ გაქვს. მოქმედებს Push-ისა და ჩუმი საათების პარამეტრები.';row.after(note)}
 const finish=finishLogin;finishLogin=async function(){await finish();syncDailyPhotoReminder()};const navigate=go;go=function(id){navigate(id);if(id==='settings')syncDailyPhotoReminder()};
 const logout=logoutUser;logoutUser=function(){generation++;loadedPhone='';pending=null;toggling=false;cancelLegacy();return logout()};
 openDailyPhotoReminder=function(){if(st.phone)openDailyMoment();else go('login')};cancelLegacy();if(st.phone)syncDailyPhotoReminder();
})();
