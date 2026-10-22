import { spawn } from "node:child_process";
const child = spawn("/etc/profiles/per-user/tom/bin/mpv", ["--no-config","--no-video","--idle=yes","--ao=null","--input-ipc-client=fd://3","--msg-level=all=no"], { stdio: ["ignore","ignore","ignore","pipe"] });
console.log(child.pid);
setInterval(() => {}, 1000);
