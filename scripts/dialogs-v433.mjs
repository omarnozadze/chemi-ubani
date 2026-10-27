import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{parse}=require('@babel/parser');
export function replaceDialogs(code){
 const ast=parse(code,{sourceType:'script',allowReturnOutsideFunction:true}),edits=[],asyncFns=new Set();
 function visit(n,fn=null){if(!n||typeof n!=='object')return;if(['FunctionDeclaration','FunctionExpression','ArrowFunctionExpression','ObjectMethod'].includes(n.type))fn=n;
  if(n.type==='CallExpression'&&n.callee.type==='Identifier'&&['prompt','confirm'].includes(n.callee.name)){
   if(!fn)throw Error('Dialog outside function');
   edits.push([n.start,n.start,'(await '],[n.end,n.end,')'],[n.callee.start,n.callee.end,n.callee.name==='prompt'?'appPrompt433':'appConfirm433']);
   if(!fn.async&&!asyncFns.has(fn)){asyncFns.add(fn);edits.push([fn.start,fn.start,'async '])}
  }
  for(const[k,v]of Object.entries(n)){if(['loc','start','end','extra'].includes(k))continue;if(Array.isArray(v))v.forEach(x=>visit(x,fn));else if(v&&typeof v==='object')visit(v,fn)}
 }
 visit(ast);for(const[a,b,s]of edits.sort((x,y)=>y[0]-x[0]||y[1]-x[1]))code=code.slice(0,a)+s+code.slice(b);parse(code,{sourceType:'script'});return code;
}
