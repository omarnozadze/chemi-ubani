// Bounded feed pages, account-scoped offline snapshot, and an accessible post composer entry.
(()=>{
 let rows=[],owner='',busy=false,epoch=0,hasMore=false,page=0,cursors=[null];
 const root=document.getElementById('feed'),controls=document.createElement('div'),create=document.createElement('button'),status=document.createElement('p');
 create.id='feedCreatePost';create.className='btn';create.type='button';create.textContent='＋ პოსტის დამატება';create.setAttribute('aria-label','პოსტის დამატება');create.onclick=()=>openPostCreator();root.before(create,status);status.setAttribute('role','status');
 const button=(text,fn)=>{const b=document.createElement('button');b.className='small';b.textContent=text;b.onclick=fn;return b};
 const previous=button('← წინა პოსტები',()=>load(page-1)),more=button('შემდეგი პოსტები →',()=>load(page+1)),refresh=button('განახლება',()=>reset());controls.append(previous,more,refresh);root.after(controls);
 const render=renderDistrictFeed;sbListPostsSocial=async()=>rows;
 const key=phone=>'feed-v428:'+phone;
 function removeCache(phone){try{localStorage.removeItem(key(phone))}catch{}}
 function saveCache(phone,data){try{localStorage.setItem(key(phone),JSON.stringify({time:Date.now(),city:st.city,district:st.district,neighborhood:st.neigh,rows:data.map(p=>({...p,content:String(p.content||'').slice(0,5000)}))}))}catch{}}
 function cached(phone){try{const data=JSON.parse(localStorage.getItem(key(phone)));return data&&data.city===st.city&&data.district===st.district&&data.neighborhood===st.neigh&&Date.now()-data.time<86400000&&Array.isArray(data.rows)?data.rows.slice(0,25):[]}catch{return[]}}
 function buttons(){previous.hidden=page===0;more.hidden=!hasMore;previous.disabled=more.disabled=refresh.disabled=busy}
 async function load(index=0){if(busy||!st.phone||index<0||index>cursors.length)return;const phone=st.phone,version=epoch;busy=true;buttons();status.textContent='იტვირთება…';const cursor=cursors[index];
 try{const r=await sbRpc('feed_page',{p_before:cursor?.created_at||null,p_before_id:cursor?.id||null});if(phone!==st.phone||version!==epoch)return;if(!r.ok)throw Error();
 rows=(Array.isArray(r.data)?r.data:[]).slice(0,25);page=index;hasMore=rows.length===25;cursors[index+1]=rows.at(-1)||null;cursors.length=index+2;owner=phone;
 if(index===0)saveCache(phone,rows);await render();status.textContent=rows.length?`გვერდი ${page+1}`:'ჯერ პოსტები არ არის — დაამატე პირველი პოსტი.';root.querySelectorAll('img').forEach(img=>{img.loading='lazy';img.decoding='async'});
 }catch{if(phone===st.phone&&version===epoch){status.textContent=rows.length?'კავშირი ვერ დამყარდა — ნაჩვენებია ბოლოს ჩატვირთული პოსტები.':'პოსტები ვერ ჩაიტვირთა. დააჭირე განახლებას.'}}
 finally{if(version===epoch){busy=false;buttons()}}}
 async function reset(){epoch++;busy=false;page=0;cursors=[null];hasMore=false;rows=[];owner=st.phone;root.replaceChildren();if(owner){rows=cached(owner);if(rows.length){await render();status.textContent='ბოლოს შენახული პოსტები';}}return load(0)}
 renderDistrictFeed=()=>reset();
 window.clearFeedSnapshot=()=>{removeCache(st.phone);rows=[];epoch++;busy=false;root.replaceChildren()};
 const logout=logoutUser;logoutUser=function(){removeCache(owner);epoch++;busy=false;rows=[];owner='';status.textContent='';page=0;hasMore=false;buttons();root.replaceChildren();logout()};buttons();
})();
