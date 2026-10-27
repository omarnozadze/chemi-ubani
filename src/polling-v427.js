// One request at a time per task; inactive screens never poll.
(()=>{
 const jobs=new Map();
 const available=()=>!document.hidden&&navigator.onLine!==false&&window.appNativeActive!==false;
 function schedule(job,delay){clearTimeout(job.timer);if(!job.stopped)job.timer=setTimeout(()=>run(job),delay)}
 async function run(job){
  if(job.stopped)return;
  if(job.busy){schedule(job,job.interval);return}
  if(!available()||!job.active()){schedule(job,job.interval);return}
  job.busy=true;
  try{await job.action()}catch{}finally{job.busy=false;schedule(job,job.interval*(1+Math.random()*.15))}
 }
 window.appPoll={
  add(name,interval,active,action){this.remove(name);const job={interval,active,action,busy:false,stopped:false,timer:null};jobs.set(name,job);schedule(job,interval*(1+Math.random()*.15));},
  remove(name){const job=jobs.get(name);if(job){job.stopped=true;clearTimeout(job.timer);jobs.delete(name)}},
  interval(name,ms){const job=jobs.get(name);if(job){job.interval=ms;if(!job.busy)schedule(job,ms*(1+Math.random()*.15))}},
  wake(names){for(const [name,job]of jobs)if((!names||names.includes(name))&&!job.busy)schedule(job,250+Math.random()*1000)}
 };
 document.addEventListener('visibilitychange',()=>{if(available())appPoll.wake()});
 window.addEventListener('online',()=>appPoll.wake());
})();
