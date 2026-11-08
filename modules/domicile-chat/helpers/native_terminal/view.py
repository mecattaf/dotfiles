#!/usr/bin/env python3
"""Native view of an EXISTING DSH terminal, run on NAS inside Kitty's SSH PTY."""
import argparse,base64,codecs,json,os,select,signal,socket,sys,termios,tty

def safe_title(text):
    return ''.join(c for c in text if ord(c)>=32 and ord(c)!=127)[:180]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ('socket','server','epoch','session','terminal'):parser.add_argument('--'+field,required=True)
    args=parser.parse_args()
    if not sys.stdin.isatty() or not sys.stdout.isatty():parser.error('interactive terminal required')
    channel=socket.socket(socket.AF_UNIX);channel.connect(args.socket)
    request={'version':1,'server':args.server,'epoch':args.epoch,'operation':'attach','session':args.session,'terminal':args.terminal}
    channel.sendall((json.dumps(request)+'\n').encode())
    previous=termios.tcgetattr(0);decoder=codecs.getincrementaldecoder('utf-8')('replace')
    buffer=b'';sequence=0;output_sequence=None;writable=False;ready=False;resize=True;attention=None;terminal_title='Terminal';unacked={}
    def dimensions():
        size=os.get_terminal_size(0);return {'cols':size.columns,'rows':size.lines}
    def resized(*_):
        nonlocal resize
        resize=True
    def write(payload):
        nonlocal sequence
        sequence+=1;payload['sequence']=sequence
        encoded=(json.dumps(payload)+'\n').encode()
        if sum(unacked.values())+len(encoded)>131072:raise RuntimeError('input window exhausted; input was not replayed')
        channel.sendall(encoded);unacked[sequence]=len(encoded)
    def title():
        state=attention.get('status') if attention else 'status unavailable'
        chat=attention.get('title') if attention else args.session
        os.write(1,('\x1b]2;'+safe_title(f'[{state}] {chat} · {terminal_title}')+'\x1b\\').encode())
    signal.signal(signal.SIGWINCH,resized)
    try:
        tty.setraw(0)
        while True:
            if ready and writable and resize:
                write({'type':'resize',**dimensions()});resize=False
            reads,_,_=select.select([channel]+([0] if ready and (not writable or sum(unacked.values())<65536) else []),[],[],1)
            for source in reads:
                if source==0:
                    data=os.read(0,16384)
                    if not data or b'\x1d' in data:return 0  # Ctrl+] detaches; never closes the DSH process.
                    if not writable:continue
                    text=decoder.decode(data)
                    if text:write({'type':'write','data':text})
                    continue
                data=channel.recv(65536)
                if not data:raise RuntimeError('DSH viewer disconnected; process retained. Reopen this exact identity to recover.')
                buffer+=data
                if len(buffer)>8*1024*1024:raise RuntimeError('oversized DSH frame')
                while b'\n' in buffer:
                    raw,buffer=buffer.split(b'\n',1);value=json.loads(raw)
                    if value['type']=='error':raise RuntimeError(value.get('code','DSH terminal unavailable'))
                    if value['type']=='identity':
                        if (value['server'],value['epoch'],value['session'],value['terminal'])!=(args.server,args.epoch,args.session,args.terminal):raise RuntimeError('DSH identity mismatch')
                        for key,text in (('dsh_session',args.session),('dsh_terminal',args.terminal),('dsh_server',args.server),('dsh_epoch',args.epoch)):
                            os.write(1,f'\x1b]1337;SetUserVar={key}={base64.b64encode(text.encode()).decode()}\x1b\\'.encode())
                    if value['type']=='attention':attention=value.get('value') if value.get('available') else None;title()
                    if value['type']!='frame':continue
                    frame=value['frame'];kind=frame['type']
                    if kind=='snapshot':
                        if frame['info']['id']!=args.terminal:raise RuntimeError('terminal snapshot identity mismatch')
                        output_sequence=frame['sequence'];writable=frame['writable'];ready=True;terminal_title=frame['info']['title']
                        termios.tcflush(0,termios.TCIFLUSH)
                        os.write(1,b'\x1b[0m\x1b[2J\x1b[H'+frame['screen'].encode());title()
                    elif kind=='output':
                        if output_sequence is None or frame['sequence']!=output_sequence+1:raise RuntimeError('DSH output continuity lost; reopen to recover')
                        output_sequence=frame['sequence'];os.write(1,frame['data'].encode())
                    elif kind=='state':
                        writable=frame['writable'];terminal_title=frame['info']['title'];title()
                    elif kind=='ack':
                        unacked.pop(frame['sequence'],None)
                        if frame.get('refusal'):writable=False;os.write(1,b'\r\nDSH terminal input is read-only.\r\n')
    finally:
        channel.close();termios.tcsetattr(0,termios.TCSADRAIN,previous)

if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,RuntimeError) as error:print(f'\r\n{error}',file=sys.stderr);raise SystemExit(1)
