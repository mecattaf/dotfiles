import {test,expect} from 'bun:test';
import {NotificationStore,parseNotificationCommand,type NotificationInput} from './notifications';
const input=(patch:Partial<NotificationInput>={}):NotificationInput=>({app:'Test',summary:'Hello',body:'body',replacesId:0,actions:[],urgency:1,timeout:0,resident:false,transient:false,...patch});
function setup(){const closed:number[][]=[],invoked:unknown[][]=[];const store=new NotificationStore(()=>{},(id,r)=>closed.push([id,r]),(id,k)=>invoked.push([id,k]),()=>123);return {store,closed,invoked}}
test('replacement keeps ID, replaces content and updates history',()=>{
 const {store}=setup();const id=store.notify(input());expect(store.notify(input({replacesId:id,summary:'Updated'}))).toBe(id);expect(store.snapshot().items).toHaveLength(1);expect(store.snapshot().history[0]?.summary).toBe('Updated');store.stop();
});
test('close signals preserve protocol reasons and cannot fire twice',()=>{
 const {store,closed}=setup();const id=store.notify(input());store.close(id,3);store.close(id,2);expect(closed).toEqual([[id,3]]);expect(store.snapshot().items).toHaveLength(0);expect(store.snapshot().history).toHaveLength(1);
});
test('actions are allowlisted and resident actions remain open',()=>{
 const {store,invoked}=setup();const id=store.notify(input({actions:['open','Open'],resident:true}));expect(()=>store.command({type:'action',id,key:'injected'})).toThrow();store.command({type:'action',id,key:'open'});expect(invoked).toEqual([[id,'open']]);expect(store.snapshot().items).toHaveLength(1);store.stop();
});
test('nonresident action emits invocation then dismissal',()=>{
 const {store,closed,invoked}=setup();const id=store.notify(input({actions:['default','Open']}));store.command({type:'action',id,key:'default'});expect(invoked).toEqual([[id,'default']]);expect(closed).toEqual([[id,2]]);
});
test('transient notifications never enter history; clear dismisses all',()=>{
 const {store,closed}=setup();store.notify(input({transient:true}));store.notify(input());expect(store.snapshot().history).toHaveLength(1);store.command({type:'clear'});expect(closed.map(c=>c[1])).toEqual([2,2]);expect(store.snapshot().history).toHaveLength(0);
});
test('DND changes delivery state without dropping notification history',()=>{
 const {store}=setup();store.command({type:'dnd',enabled:true});store.notify(input());expect(store.snapshot().dnd).toBe(true);expect(store.snapshot().history).toHaveLength(1);store.stop();
});
test('expired notifications close with reason 1; critical remains',async()=>{
 const {store,closed}=setup();const id=store.notify(input({timeout:10}));store.notify(input({timeout:10,urgency:2}));await Bun.sleep(35);expect(closed).toEqual([[id,1]]);expect(store.snapshot().items).toHaveLength(1);store.stop();
});
test('memory bounded under a notification flood',()=>{
 const {store}=setup();for(let i=0;i<150;i++)store.notify(input());expect(store.snapshot().items).toHaveLength(100);expect(store.snapshot().history).toHaveLength(100);store.stop();
});
test('IPC rejects invalid IDs and arbitrary commands',()=>{
 for(const command of [{type:'exec',command:'sh'},{type:'dismiss',id:-1},{type:'dismiss',id:1.5},{type:'dnd',enabled:'yes'}])expect(()=>parseNotificationCommand(command)).toThrow();
});

test('replacement moves to newest position for snapshot and dismiss-latest',()=>{
 const {store,closed}=setup();const first=store.notify(input());const second=store.notify(input());
 store.notify(input({replacesId:first,summary:'Newest update'}));
 expect(store.snapshot().items.map(item=>item.id)).toEqual([first,second]);
 store.command({type:'dismiss-latest'});expect(closed).toEqual([[first,2]]);store.stop();
});
test('opaque action keys are preserved and oversized keys cannot alias a valid action',()=>{
 const {store,invoked}=setup();const key='x'.repeat(256);
 const id=store.notify(input({resident:true,actions:[key+'different','Invalid',key,'Valid',key,'Duplicate']}));
 expect(store.snapshot().items[0]?.actions).toEqual([{key,label:'Valid'}]);
 expect(()=>store.command({type:'action',id,key:key+'different'})).toThrow();
 store.command({type:'action',id,key});expect(invoked).toEqual([[id,key]]);store.stop();
});
