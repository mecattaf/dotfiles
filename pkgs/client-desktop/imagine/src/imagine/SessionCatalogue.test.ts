import { expect, test } from "bun:test";
import { receiveCatalogue as receive, EMPTY_CATALOGUE, markSessionSeen, projectCatalogue } from "./SessionCatalogue";
import { consumeCatalogue, watchCatalogue } from "./useSessionCatalogue";
import { initialAgencyState, agencyReducer as reduce } from "./policy";
import { WindowAction as A } from "@domicile-desktop/manganese-window-management/window-state";
const row = (status = "working", revision = 1, attentionRevision = revision) => ({sessionId:"session-test",title:"A real title",status,revision,attentionRevision,pendingApprovals:0,pendingQuestions:0,updatedAt:revision});
const baseline = () => receive(EMPTY_CATALOGUE,{type:"snapshot",version:1,epoch:"epoch",seq:1,sessions:{"session-test":row("finished")}},"agency-web");
const update = (state: ReturnType<typeof baseline>, value: ReturnType<typeof row>) => receive(state,{type:"upsert",version:1,epoch:"epoch",seq:value.revision,session:value},"agency-web");
test("attachment is a quiet baseline; fresh completion is unseen and a title change preserves seen revision",()=>{
  let state=baseline();expect(projectCatalogue(state,initialAgencyState())[0]!.unseen).toBeFalse();
  state=update(state,row("working",2));state=update(state,row("finished",3));
  expect(projectCatalogue(state,initialAgencyState())[0]!.unseen).toBeTrue();
  state=markSessionSeen(state,"session-test");state=update(state,{...row("finished",4,3),title:"Renamed"});
  expect(projectCatalogue(state,initialAgencyState())[0]!.unseen).toBeFalse();
  expect(state.rows["session-test"]!.title).toBe("Renamed");
});
test("outage marks cached rows unavailable; sequence gaps require a new baseline",()=>{
  let state=baseline();state=receive(state,{type:"unavailable"},"agency-web");
  expect(state.available).toBeFalse();expect(Object.keys(state.rows)).toHaveLength(1);
  expect(()=>update(state,row("idle",2))).toThrow();
  state=receive(state,{type:"snapshot",version:1,epoch:"new",seq:0,sessions:{}},"agency-web");
  expect(state.available).toBeTrue();expect(Object.keys(state.rows)).toHaveLength(0);
  expect(()=>update(baseline(),row("idle",3))).toThrow();
});
test("viewer identity resolves the SDK window and its actual workspace, never a saved app-N",()=>{
  const tag="agencychat"+"a".repeat(32);
  let cat=receive(baseline(),{type:"viewers",viewers:[{sessionId:"session-test",tag}]},"agency-web");
  let state=reduce(initialAgencyState(),A.AppAppeared("app-999","Window"));
  state=reduce(state,A.AppDesktopIdChanged("app-999","chrome-file__"+tag+"_start"));
  expect(projectCatalogue(cat,state)[0]!.viewers[0]!.id).toBe("app:app-999");
  expect(projectCatalogue(cat,initialAgencyState())[0]!.viewers).toHaveLength(0);
});
test("UTF-8 NDJSON survives arbitrary chunk boundaries; partial EOF is rejected",async()=>{
  const bytes=new TextEncoder().encode(JSON.stringify({title:"café"})+"\n");const frames:unknown[]=[];
  await consumeCatalogue(new ReadableStream({start(c){for(const byte of bytes)c.enqueue(new Uint8Array([byte]));c.close();}}),x=>frames.push(x));
  expect(frames).toEqual([{title:"café"}]);
  await expect(consumeCatalogue(new ReadableStream({start(c){c.enqueue(new TextEncoder().encode('{"partial":'));c.close();}}),()=>{})).rejects.toThrow();
});
test("relay exit cancels open readers and promptly marks cached metadata unavailable", async () => {
  let cancelled = 0;
  const stream = () => new ReadableStream<Uint8Array>({ cancel() { cancelled++; } });
  const child = { stdout: stream(), stderr: stream(), closeStdin() {}, kill() {}, exited: Promise.resolve({}) };
  const domicile = { processes: { spawn: async () => ({ match: ({ Ok }: any) => Ok(child) }) } } as any;
  const frames: any[] = [];
  const stop = watchCatalogue(domicile, { relay: "fixture", server: "agency-web" }, frame => frames.push(frame));
  await new Promise(resolve => setTimeout(resolve, 15));
  stop();
  expect(frames.some(f => f.type === "unavailable")).toBeTrue();
  expect(cancelled).toBe(2);
});
