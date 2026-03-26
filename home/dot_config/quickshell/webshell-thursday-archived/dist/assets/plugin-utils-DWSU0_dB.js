function u(t,r){return()=>{try{return t()??r}catch{return r}}}async function e(t){try{return await t()}catch{return}}export{e as i,u};
