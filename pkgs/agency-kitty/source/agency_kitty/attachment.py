"""Opt-in reconnection for one persistent stock-SSH attachment.

The child inherits the terminal descriptors. This supervisor never reads,
forwards, echoes, rewrites or retries an input byte. The remote holder owns
restore/queued-input ordering; canonical probes never allocate a session.
"""
from __future__ import annotations

from dataclasses import dataclass
import copy
import json
import os
import selectors
import signal
import subprocess
import termios
import time
import tty
from typing import Callable

from .server import HOLDER_NAMESPACES
from .sessions import Session, SessionError
from .transport import SSHTransport


@dataclass(frozen=True)
class RetryPolicy:
    max_retries: int = 5
    initial_delay: float = .25
    maximum_delay: float = 4
    budget_seconds: float = 45
    probe_timeout: float = 5
    termination_timeout: float = 3
    stable_seconds: float = 30

    def validate(self):
        if (type(self.max_retries) is not int or not 1<=self.max_retries<=8
                or not .05<=self.initial_delay<=5 or not self.initial_delay<=self.maximum_delay<=10
                or not .1<=self.budget_seconds<=120 or not .1<=self.probe_timeout<=15
                or not .1<=self.termination_timeout<=5):
            raise SessionError('reconnect settings exceed their explicit bounds')
        if not 1<=self.stable_seconds<=120:raise SessionError('stable reconnect interval exceeds its bound')


def _stop(child,timeout):
    if child is not None and child.poll() is None:
        child.terminate()
        try:child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            child.kill();child.wait(timeout=2)


class _Signals:
    def __init__(self):
        self.number=0;self.child=None;self.previous={};self.reader=None;self.writer=None
    def __enter__(self):
        self.reader,self.writer=os.pipe2(os.O_CLOEXEC|os.O_NONBLOCK)
        self.previous_wakeup=signal.set_wakeup_fd(self.writer)
        def handler(number,_):
            self.number=number
            if self.child is not None and self.child.poll() is None:
                try:self.child.send_signal(number)
                except ProcessLookupError:pass
        for number in (signal.SIGINT,signal.SIGTERM,signal.SIGHUP):
            self.previous[number]=signal.signal(number,handler)
        return self
    def __exit__(self,*_):
        for number,handler in self.previous.items():signal.signal(number,handler)
        signal.set_wakeup_fd(self.previous_wakeup)
        os.close(self.reader);os.close(self.writer)


def _wait_child(child,signals):
    # pidfd readiness and the private signal pipe block without a timer.
    # Neither descriptor is a terminal or carries application input/output.
    if signals.number:return None
    if child.poll() is not None:return child.returncode
    try:descriptor=os.pidfd_open(child.pid)
    except ProcessLookupError:return child.wait()
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor,selectors.EVENT_READ,'child')
            selector.register(signals.reader,selectors.EVENT_READ,'signal')
            while not signals.number:
                for key,_ in selector.select():
                    if key.data=='child':return child.wait()
                    os.read(signals.reader,4096)
            return None
    finally:os.close(descriptor)


def _probe(transport,session,action,timeout,env,signals,policy):
    child=subprocess.Popen(transport.command_argv(action,session.id),stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
    signals.child=child
    selector=selectors.DefaultSelector();streams={'stdout':bytearray(),'stderr':bytearray()}
    for name,stream in (('stdout',child.stdout),('stderr',child.stderr)):
        os.set_blocking(stream.fileno(),False);selector.register(stream,selectors.EVENT_READ,name)
    end=time.monotonic()+timeout
    try:
        while selector.get_map():
            if signals.number:raise InterruptedError('attachment cancelled')
            delay=end-time.monotonic()
            if delay<=0:raise TimeoutError('canonical attachment probe timed out')
            for key,_ in selector.select(min(delay,.1)):
                data=os.read(key.fileobj.fileno(),65536)
                if not data:selector.unregister(key.fileobj);continue
                streams[key.data].extend(data)
                if sum(map(len,streams.values()))>131072:raise SessionError('canonical attachment probe exceeded its bound')
        try:code=child.wait(timeout=max(.001,end-time.monotonic()))
        except subprocess.TimeoutExpired as error:raise TimeoutError('canonical attachment probe timed out') from error
        if signals.number:raise InterruptedError('attachment cancelled')
        if code==255:return None
        if code:raise SessionError('canonical NAS attachment is unavailable; no replacement was allocated')
        value=json.loads(streams['stdout'])
        if action=='rebind':
            if not isinstance(value,dict) or type(value.get('version')) is not int or value.get('version')!=1:raise SessionError('invalid canonical rebind response')
            value=value.get('session')
        _validate(value,session,retry=action=='rebind')
        return value
    finally:
        selector.close();_stop(child,policy.termination_timeout)
        child.stdout.close();child.stderr.close();signals.child=None


def _validate(value,session,*,retry):
    if (not isinstance(value,dict) or value.get('id')!=session.id or value.get('host')!='nas'
            or value.get('transport')!='zmx' or value.get('mode')!='persistent' or value.get('resumable') is not True
            or value.get('holder_version')!=session.holder_version or value.get('cwd')!=session.cwd
            or not isinstance(value.get('status'),str) or value.get('status') not in ('created','active','detached')
            or type(value.get('live')) is not bool
            or type(value.get('schema_version')) is not int or value.get('schema_version')!=1 or session.holder_version not in HOLDER_NAMESPACES
            or value.get('live') is not True and (retry or value.get('status')!='created' or session.status!='created')):
        raise SessionError('exact persistent NAS owner is unavailable; no replacement was allocated')


def supervise(session: Session, argv: list[str], transport: SSHTransport, *,
              policy: RetryPolicy = RetryPolicy(), env: dict | None = None,
              event: Callable[[dict],None] | None = None) -> int:
    """Wait on stock SSH; retry only255 with exact live-owner verification.

    Opt-in caller must already select the persistent stock-SSH transport before
    allocation. Direct sessions and alternate terminal proxies are unsupported.
    """
    policy.validate()
    if session.host!='nas' or session.status=='closed' or session.holder_version not in HOLDER_NAMESPACES:
        raise SessionError('reconnect requires one known persistent NAS identity')
    if (transport.interactive_transport!='plain' or argv!=transport.attach_argv(session)
            or not argv or argv[0]!=transport.ssh):
        raise SessionError('automatic reconnect requires the exact persistent stock SSH attach command without allocation flags')
    if not hasattr(os,'pidfd_open'):
        raise SessionError('automatic reconnect requires Linux pidfd support')
    if not os.isatty(0) or not os.isatty(1):raise SessionError('persistent attachment requires an inherited interactive terminal')
    initial=termios.tcgetattr(0);waiting=copy.deepcopy(initial);tty.cfmakeraw(waiting);waiting[3]|=termios.ISIG
    def notify(phase,**values):
        if event:event({'phase':phase,'session':session.id,**values})
    def wait_for(seconds,signals):
        with selectors.DefaultSelector() as selector:
            selector.register(signals.reader,selectors.EVENT_READ)
            if not signals.number:selector.select(seconds)
    child=None
    try:
        with _Signals() as signals:
            try:
                # TCSANOW never discards queued typeahead. Active SSH then owns
                # its terminal modes; we establish no-echo waiting modes only
                # while no interactive SSH child is running.
                termios.tcsetattr(0,termios.TCSANOW,waiting)
                initial_value=_probe(transport,session,'describe',policy.probe_timeout,env,signals,policy)
                if initial_value is None:return 255
                retries=0;loss_started=None
                while not signals.number:
                    child=subprocess.Popen(list(argv),env=env)
                    attached_at=time.monotonic()
                    signals.child=child;notify('attached-child',pid=child.pid,retry=retries)
                    _wait_child(child,signals)
                    if signals.number:return 128+signals.number
                    code=child.returncode;signals.child=None;notify('child-exit',code=code,retry=retries)
                    if code!=255:return code if code>=0 else 128-code
                    termios.tcsetattr(0,termios.TCSANOW,waiting)
                    if time.monotonic()-attached_at>=policy.stable_seconds:retries=0;loss_started=None
                    if loss_started is None:loss_started=time.monotonic()
                    verified=False
                    while retries<policy.max_retries and time.monotonic()-loss_started<policy.budget_seconds and not signals.number:
                        delay=min(policy.maximum_delay,policy.initial_delay*2**retries,
                                  max(0,policy.budget_seconds-(time.monotonic()-loss_started)))
                        retries+=1;notify('retry-wait',retry=retries,delay=delay)
                        wait_for(delay,signals)
                        if signals.number:break
                        budget=policy.budget_seconds-(time.monotonic()-loss_started)
                        if budget<=0:break
                        try:value=_probe(transport,session,'rebind',min(policy.probe_timeout,budget),env,signals,policy)
                        except TimeoutError:value=None
                        if value is not None:
                            verified=True;notify('retry-verified',retry=retries);break
                    if not verified:return 128+signals.number if signals.number else 255
                return 128+signals.number
            except InterruptedError:
                return 128+signals.number if signals.number else 130
            finally:
                _stop(signals.child,policy.termination_timeout);signals.child=None
                _stop(child,policy.termination_timeout)
    finally:
        # TCSANOW restores caller modes without flushing queued bytes.
        try:termios.tcsetattr(0,termios.TCSANOW,initial)
        except termios.error:
            if os.isatty(0):raise
