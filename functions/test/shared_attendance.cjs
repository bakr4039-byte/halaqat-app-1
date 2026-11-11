const {test} = require('node:test');
const assert = require('node:assert/strict');
const rows = new Map();
let counter=0;
class Doc {
  constructor(path){this.path=path;this.id=path.split('/').at(-1);this.ref=this;}
  get exists(){return rows.has(this.path);}
  data(){return rows.get(this.path);}
  async get(){return this;}
  collection(name){return new Query(this.path+'/'+name);}
  async set(value,options){rows.set(this.path,options?.merge?{...this.data(),...value}:value);}
}
class Query {
  constructor(path,filters=[]){this.path=path;this.filters=filters;}
  doc(id){return new Doc(this.path+'/'+(id||'generated-'+(++counter)));}
  where(field,op,value){return new Query(this.path,[...this.filters,[field,op,value]]);}
  limit(){return this;}
  orderBy(){return this;}
  async get(){
    const docs=[...rows.keys()].filter(k=>k.startsWith(this.path+'/')&&!k.slice(this.path.length+1).includes('/')).map(k=>new Doc(k)).filter(d=>this.filters.every(([f,op,v])=>op==='=='?d.data()[f]===v:op==='>='?d.data()[f]>=v:d.data()[f]<=v));
    return {docs,size:docs.length,empty:!docs.length,forEach:fn=>docs.forEach(fn)};
  }
}
const db={collection:path=>new Query(path),batch:()=>{
  const changes=[];
  return {
    set:(d,v)=>changes.push(['set',d.path,v]),
    update:(d,v)=>changes.push(['update',d.path,v]),
    delete:d=>changes.push(['delete',d.path]),
    commit:async()=>{
      const staged=new Map(rows);
      for(const [op,path,value] of changes){
        if(op==='update'&&!staged.has(path))throw new Error('missing document');
        if(op==='delete')staged.delete(path);
        else staged.set(path,op==='update'?{...staged.get(path),...value}:value);
      }
      rows.clear();for(const [path,value] of staged)rows.set(path,value);
    },
  };
},runTransaction:async fn=>{
  const changes=[];
  const result=await fn({get:q=>q.get(),delete:d=>changes.push(()=>rows.delete(d.path)),set:(d,v,o)=>changes.push(()=>d.set(v,o))});
  for(const write of changes)await write();return result;
}};
const admin={firestore:Object.assign(()=>db,{Timestamp:{fromDate:d=>d},FieldValue:{serverTimestamp:()=>new Date()}})};
require.cache[require.resolve('../lib/admin')]= {exports:{db,admin}};
require.cache[require.resolve('../lib/whatsapp')]= {exports:{notifyGuardiansOfAbsence:async()=>{}}};
const {saveStudentAttendanceDay,getStudents}=require('../lib/students');
const helpers=require('../lib/helpers');
const req=(teacher,records)=>({auth:{uid:teacher,token:{role:'teacher',circleId:'school-a',teacherId:teacher}},data:{circleId:'school-a',dateKey:'2026-11-11',records}});
test('two teacher/device saves preserve other records and converge on one record per student',async()=>{
 rows.set('circles/school-a/teachers/t-a',{subCircle:'نافع'});
 rows.set('circles/school-a/teachers/t-b',{subCircle:'عاصم'});
 rows.set('circles/school-a/students/s-a',{teacherId:'t-a',name:'طالب أ'});
 rows.set('circles/school-a/students/s-b',{teacherId:'t-b',name:'طالب ب'});
 rows.set('circles/school-a/studentAttendance/legacy-a',{studentId:'s-a',teacherId:'t-a',dateKey:'2026-11-11',status:'absent'});
 rows.set('circles/school-a/studentAttendance/legacy-b',{studentId:'s-b',teacherId:'t-b',dateKey:'2026-11-11',status:'present'});
 await saveStudentAttendanceDay.run(req('t-a',[{studentId:'s-a',status:'present'}]));
 assert.equal(rows.get('circles/school-a/studentAttendance/legacy-b').status,'present');
 await saveStudentAttendanceDay.run(req('t-b',[{studentId:'s-b',status:'late'}]));
 await saveStudentAttendanceDay.run(req('t-a',[{studentId:'s-a',status:'excused'}]));
 const all=await new Query('circles/school-a/studentAttendance').get();
 assert.equal(all.size,2);
 assert.equal(all.docs.find(d=>d.data().studentId==='s-a').data().status,'excused');
 await assert.rejects(()=>saveStudentAttendanceDay.run(req('t-a',[{studentId:'s-b',status:'absent'}])),/طالب/);
 const response=await getStudents.run(req('t-a',[]));assert.equal(response.students.length,1);
 assert.throws(()=>helpers.requireManagerAccess(req('t-a',[]),'school-a'));
 assert.throws(()=>helpers.requireCircleAccess(req('t-a',[]),'school-b'));
 assert.throws(()=>helpers.validDateKey('2026-02-31'));
});
test('incentive grant, correction and removal publish a protected revision in the same atomic batch',async()=>{
 const {applyIncentivePointsBulk,updateIncentiveTransaction,deleteIncentiveTransaction}=require('../lib/incentives');
 const school='circles/incentive-school';
 rows.set(school,{name:'School'});
 rows.set(school+'/students/s1',{name:'Student',teacherId:'t1'});
 rows.set(school+'/incentiveItems/item1',{name:'Progress',type:'grant',points:3});
 const request=data=>({auth:{uid:'manager',token:{role:'owner',circleId:'incentive-school'}},data:{circleId:'incentive-school',...data}});
 await applyIncentivePointsBulk.run(request({itemId:'item1',studentIds:['s1']}));
 const ledger=await new Query(school+'/incentiveLedger').get();
 assert.equal(ledger.size,1);assert.equal(ledger.docs[0].data().points,3);
 const firstRevision=rows.get(school).lastDataChange;assert.ok(firstRevision instanceof Date);
 await updateIncentiveTransaction.run(request({transactionId:ledger.docs[0].id,updates:{points:5}}));
 assert.equal(rows.get(ledger.docs[0].path).points,5);
 assert.notEqual(rows.get(school).lastDataChange,firstRevision);
 const secondRevision=rows.get(school).lastDataChange;
 await deleteIncentiveTransaction.run(request({transactionId:ledger.docs[0].id}));
 assert.equal((await new Query(school+'/incentiveLedger').get()).size,0);
 assert.notEqual(rows.get(school).lastDataChange,secondRevision);
 rows.delete(school);
 await assert.rejects(()=>applyIncentivePointsBulk.run(request({itemId:'item1',studentIds:['s1']})),/missing document/);
 assert.equal((await new Query(school+'/incentiveLedger').get()).size,0,'failed parent update must not leave a ledger entry');
});
