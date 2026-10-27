// Device-local durable drafts and outbox. No tokens or messages are sent to analytics.
(()=>{
 let database;
 const db=()=>database||(database=new Promise((resolve,reject)=>{if(!window.indexedDB)return reject(Error('Storage unavailable'));const r=indexedDB.open('chemiUbaniChat',1);r.onupgradeneeded=()=>r.result.createObjectStore('state');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)}));
 async function operation(key,value,remove=false){const d=await db();return new Promise((resolve,reject)=>{const tx=d.transaction('state',value===undefined&&!remove?'readonly':'readwrite'),s=tx.objectStore('state');const r=remove?s.delete(key):value===undefined?s.get(key):s.put(value,key);tx.oncomplete=()=>resolve(r.result);tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error)})}
 window.chatDisk={get:phone=>operation('owner:'+phone),put:(phone,value)=>operation('owner:'+phone,value),remove:phone=>operation('owner:'+phone,null,true)};
})();
