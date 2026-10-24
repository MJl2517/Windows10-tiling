const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../src/bar'),lock=JSON.parse(fs.readFileSync(path.join(root,'package-lock.json'),'utf8'));
const notices=[];
for(const key of Object.keys(lock.packages).filter(k=>k.startsWith('node_modules/'))){
  const dir=path.join(root,key);if(!fs.existsSync(dir))continue;
  const pkg=JSON.parse(fs.readFileSync(path.join(dir,'package.json'),'utf8'));
  notices.push(`\n===== ${pkg.name} ${pkg.version} (${pkg.license||'see package'}) =====\n`);
  for(const file of fs.readdirSync(dir).filter(n=>/^(licen[sc]e|copying|notice)(\.|$)/i.test(n))){
    if(fs.statSync(path.join(dir,file)).isFile())notices.push(fs.readFileSync(path.join(dir,file),'utf8'));
  }
}
fs.writeFileSync(path.resolve(__dirname,'../licenses/npm-NOTICES.txt'),notices.join('\n'));
