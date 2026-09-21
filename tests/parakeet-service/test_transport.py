import importlib.util,socket,threading,io,struct,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('transport',str(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[2]/'pkgs/parakeet-service/transport.py')); m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def check(data,expected):
 a,b=socket.socketpair();out=io.BytesIO()
 def send():
  for pos in range(0,len(data),37):a.sendall(data[pos:pos+37])
  a.close()
 t=threading.Thread(target=send);t.start()
 try:
  got=m.receive(b,out); assert got==expected,(got,expected)
 except (EOFError,ValueError) as e:
  assert expected==type(e),(e,expected)
 finally:b.close();t.join()
check(struct.pack('<I',9600)+bytes(9600)+bytes(4),9600)
check(struct.pack('<I',9600)+bytes(9600),EOFError)
check(struct.pack('<I',3)+b'abc',ValueError)
check(struct.pack('<I',70000),ValueError)
check(bytes(4),ValueError)
print('5 framing/cancel/limit probes passed')

# Socket activation: systemd owns the listener and the path, so an activated
# server must adopt fd 3 and must not claim ownership of the socket file.
import os,tempfile,types
def args_at(d):return types.SimpleNamespace(socket=Path(d)/'engine.sock')
def activated(count,pid):
 os.environ.update(LISTEN_FDS=str(count),LISTEN_PID=str(pid),LISTEN_FDNAMES='engine.sock')
with tempfile.TemporaryDirectory() as d:
 held=socket.socket(socket.AF_UNIX);held.bind(str(Path(d)/'systemd.sock'));held.listen(1)
 os.dup2(held.fileno(),3);held.detach()  # fd 3 is systemd's to hand over, not ours to close
 activated(1,os.getpid())
 sock,owns=m.listener(args_at(d))
 assert sock.fileno()==3,sock.fileno()
 assert owns is False,owns
 assert not{'LISTEN_FDS','LISTEN_PID','LISTEN_FDNAMES'}&set(os.environ),'activation vars leak to the engine'
 sock.close()
with tempfile.TemporaryDirectory() as d:
 a=args_at(d);sock,owns=m.listener(a)
 assert owns is True,owns
 assert a.socket.is_socket(),'self-bound server must create its own socket'
 sock.close()
with tempfile.TemporaryDirectory() as d:
 activated(2,os.getpid())
 try:m.listener(args_at(d));raise AssertionError('two activation sockets must be refused')
 except RuntimeError:pass
print('3 socket-activation probes passed')
