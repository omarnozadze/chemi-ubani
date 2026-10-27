(()=>{
 let chain=Promise.resolve(),generation=0,cancelActive=null;
 window.cancelAppDialogs433=()=>{generation++;cancelActive?.();};
 const clean=v=>String(v??'').replace(/\b(?:TypeError|ReferenceError|SyntaxError|JavaScript)\b:?/gi,'').replace(/https?:\/\/\S+/g,'').slice(0,4000);
 function dialog(kind,message,value=''){
  const ticket=generation;const run=()=>new Promise(resolve=>{
   if(ticket!==generation){resolve(kind==='prompt'?null:false);return}
   const previous=document.activeElement,layer=document.createElement('div'),box=document.createElement('form'),title=document.createElement('h3'),label=document.createElement('label'),input=document.createElement('textarea'),actions=document.createElement('div');
   layer.className='appDialog433';box.className='appDialogBox433';box.setAttribute('role','dialog');box.setAttribute('aria-modal','true');title.id='dialogTitle433';title.textContent=kind==='prompt'?'რედაქტირება':kind==='confirm'?'დადასტურება':'ჩემი უბანი';box.setAttribute('aria-labelledby',title.id);label.textContent=clean(message)||'მოქმედება ვერ დასრულდა. სცადე ხელახლა.';input.value=String(value??'');input.className='inp';input.rows=5;input.maxLength=5000;input.setAttribute('aria-label',label.textContent);actions.className='dialogActions433';
   const done=v=>{cancelActive=null;layer.remove();previous?.focus?.();resolve(v)};cancelActive=()=>done(kind==='prompt'?null:false);
   function button(text,fn){const b=document.createElement('button');b.type='button';b.className='small';b.textContent=text;b.onclick=fn;actions.append(b);return b}
   if(kind!=='alert')button('გაუქმება',()=>done(kind==='prompt'?null:false));const ok=button(kind==='prompt'?'შენახვა':kind==='confirm'?'დადასტურება':'გასაგებია',()=>done(kind==='prompt'?input.value:true));
   box.onsubmit=e=>{e.preventDefault();ok.click()};box.append(title,label);if(kind==='prompt')box.append(input);box.append(actions);layer.append(box);document.body.append(layer);(kind==='prompt'?input:ok).focus();
   box.onkeydown=e=>{if(e.key==='Escape'){e.preventDefault();done(kind==='prompt'?null:false)}if(e.key==='Tab'){const f=[...box.querySelectorAll('button,textarea')];if(e.shiftKey&&document.activeElement===f[0]){e.preventDefault();f.at(-1).focus()}else if(!e.shiftKey&&document.activeElement===f.at(-1)){e.preventDefault();f[0].focus()}}};
  });const p=chain.then(run);chain=p.catch(()=>{});return p;
 }
 window.appPrompt433=(m,v)=>dialog('prompt',m,v);window.appConfirm433=m=>dialog('confirm',m);window.alert=m=>{void dialog('alert',m)};
 const style=document.createElement('style');style.textContent='.appDialog433{position:fixed;inset:0;z-index:100000;background:#10291f88;display:grid;place-items:center;padding:20px}.appDialogBox433{width:min(100%,460px);max-height:85dvh;overflow:auto;background:white;color:#153d30;border-radius:24px;padding:24px;box-shadow:0 16px 60px #0003}.appDialogBox433 label{display:block;white-space:pre-wrap;margin:12px 0;overflow-wrap:anywhere}.appDialogBox433 textarea{width:100%;box-sizing:border-box}.dialogActions433{display:flex;justify-content:flex-end;gap:10px;margin-top:18px}.dialogActions433 button{min-height:44px}';document.head.append(style);
})();
