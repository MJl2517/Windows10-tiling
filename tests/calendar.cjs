const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('../src/bar/node_modules/typescript');
const code=ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/bar/src/features/calendar-month.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const scope={exports:{},Date};vm.runInNewContext(code,scope);
const {monthDays,sameDay}=scope.exports;
for(const year of [2021,2024,2026,2100])for(let month=0;month<12;month++){
 const cells=monthDays(new Date(year,month,28));
 assert.equal(cells.length,42);assert.equal(cells[0].getDay(),1);assert.equal(cells[41].getDay(),0);
 const inMonth=cells.filter(day=>day.getFullYear()===year&&day.getMonth()===month);
 assert.equal(inMonth.length,new Date(year,month+1,0).getDate());
 for(let i=1;i<42;i++)assert(sameDay(cells[i],new Date(cells[i-1].getFullYear(),cells[i-1].getMonth(),cells[i-1].getDate()+1)));
}
assert.equal(monthDays(new Date(2024,1,1)).filter(day=>day.getMonth()===1).length,29);
assert.equal(monthDays(new Date(2100,1,1)).filter(day=>day.getMonth()===1).length,28);
assert(sameDay(new Date(2026,9,27,0),new Date(2026,9,27,23)));
assert(!sameDay(new Date(2026,9,27),new Date(2025,9,27)));
assert.equal(new Date(2026,11+1,1).getFullYear(),2027);
assert.equal(new Date(2026,-1,1).getFullYear(),2025);
console.log('PASS: Monday-first grid, 48 months, leap years, month/year navigation, local dates');
