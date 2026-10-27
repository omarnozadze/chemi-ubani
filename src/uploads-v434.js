// Authenticated, bounded Storage uploads with real byte progress and cancellation.
(()=>{
 const active=new Set(),abortError=()=>new DOMException('ატვირთვა შეჩერებულია','AbortError');
 window.storageUpload434=async(bucket,path,blob,{signal,onProgress}={})=>{
  if(bucket==='order-evidence'?!/^[0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp)$/.test(path):(!['chat-files','chat-images','civic-photos'].includes(bucket)||!/^[a-zA-Z0-9-]+\/[a-zA-Z0-9.-]+$/.test(path)))throw Error('არასწორი ატვირთვის მისამართი');
  const phone=st.phone,session=await getActivitySession();if(!session||phone!==st.phone)throw Error('შესვლა საჭიროა');if(signal?.aborted)throw abortError();
  return new Promise((resolve,reject)=>{const xhr=new XMLHttpRequest();let done=false;const abort=()=>xhr.abort();const finish=(err)=>{if(done)return;done=true;active.delete(xhr);signal?.removeEventListener('abort',abort);err?reject(err):resolve(path)};
   xhr.open('POST',SUPABASE_URL+'/storage/v1/object/'+bucket+'/'+path);xhr.timeout=120000;
   xhr.setRequestHeader('apikey',SUPABASE_ANON_KEY);xhr.setRequestHeader('Authorization','Bearer '+session.token);xhr.setRequestHeader('Content-Type',blob.type);xhr.setRequestHeader('x-upsert','false');
   xhr.upload.onprogress=e=>{if(phone!==st.phone){xhr.abort();return}if(e.lengthComputable)onProgress?.(Math.min(100,Math.floor(100*e.loaded/e.total)))};
   xhr.onload=()=>{let data={};try{data=JSON.parse(xhr.responseText)}catch{}if(phone!==st.phone)return finish(abortError());if(xhr.status>=200&&xhr.status<300||xhr.status===409||String(data.statusCode)==='409'||xhr.status===400&&/^(Duplicate|Asset Already Exists|The resource already exists)$/i.test(data.error||data.message||'')){onProgress?.(100);finish()}else finish(Error(xhr.status===401?'სესია განაახლე და ხელახლა სცადე.':'ატვირთვა ვერ დასრულდა. დანართი შენახულია ხელახლა გასაგზავნად.'))};
   xhr.onerror=()=>finish(Error('კავშირი შეწყდა. დანართი შენახულია.'));xhr.ontimeout=()=>finish(Error('ატვირთვის დრო ამოიწურა. სცადე ხელახლა.'));xhr.onabort=()=>finish(abortError());active.add(xhr);signal?.addEventListener('abort',abort,{once:true});if(signal?.aborted)return finish(abortError());xhr.send(blob);
  });
 };
 window.uploadChatPhoto434=async(request,options)=>{
  const match=/^data:(image\/(?:jpeg|png|webp));base64,([\s\S]+)$/.exec(request.photo||'');if(!match)throw Error('აირჩიე JPG, PNG ან WebP ფოტო');
  const bytes=atob(match[2]),data=new Uint8Array(bytes.length);for(let i=0;i<bytes.length;i++)data[i]=bytes.charCodeAt(i);
  if(data.length>10485760)throw Error('ფოტო მაქსიმუმ 10 MB უნდა იყოს');const ext=match[1]==='image/jpeg'?'jpg':match[1].split('/')[1],path=request.phone+'/'+request.clientId+'.'+ext;
  await storageUpload434('chat-images',path,new Blob([data],{type:match[1]}),options);
  return SUPABASE_URL+'/storage/v1/object/public/chat-images/'+path;
 };
 const logout=logoutUser;logoutUser=function(){for(const xhr of active)xhr.abort();logout()};
})();
