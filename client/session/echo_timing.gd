extends RefCounted
## Splits one app ping (Lag Report 2026-11-27) into the network part and the local wait before the game read it.
## Root cause of the old net_rtt_ms=0: the pong is handled inside SceneMultiplayer.poll(), which runs BEFORE the
## session's poll() of that frame, so the "previous frame start" it used was two frames old, earlier than the ping
## send itself: net clamped to 0 and the whole ping was reported as frame stall.
## Now: on web the browser stamps each pong's WebSocket message event (performance.now(), FIFO queue, see HOOK_JS);
## elsewhere the arrival is bounded by the previous multiplayer poll (process_frame signal), never before the send.
const HOOK_JS := "(()=>{if(window.zorxWsHooked)return;window.zorxWsHooked=true;window.zorxPongs=[];const W=window.WebSocket;function scan(d){if(!(d instanceof ArrayBuffer))return;const b=new Uint8Array(d),n=Math.min(b.length-3,64);for(let i=0;i<n;i++){if(b[i]===0x5a&&b[i+1]===0x58&&b[i+2]===%d&&b[i+3]===6){window.zorxPongs.push(performance.now());if(window.zorxPongs.length>16)window.zorxPongs.shift();return}}}class Z extends W{constructor(...a){super(...a);try{this.addEventListener('message',e=>scan(e.data))}catch(e){}}}window.WebSocket=Z})()"
## Age (ms) of the oldest unread pong arrival, -1 when none was stamped.
const READ_JS := "(()=>{const q=window.zorxPongs;if(!q||!q.length)return -1;return performance.now()-q.shift()})()"

## Pure. sent/processed/poll_floor in one clock (ms). arrival_age_ms >= 0: measured age of the pong at processing
## (browser clock, no mixing); else the arrival lies after max(sent, poll_floor). worker_wait_ms: the server's hold.
static func split(sent_ms: int, processed_ms: int, poll_floor_ms: int, arrival_age_ms: float = -1.0, worker_wait_ms = null) -> Dictionary:
	var rtt := maxi(0, processed_ms - sent_ms)
	var stall: int
	var source := "browser_event"
	if arrival_age_ms >= 0.0:
		stall = clampi(roundi(arrival_age_ms), 0, rtt)
	else:
		source = "poll_bound"
		stall = clampi(processed_ms - maxi(sent_ms, poll_floor_ms), 0, rtt)
	var net := rtt - stall
	var hold := maxi(0, int(worker_wait_ms)) if worker_wait_ms != null else 0
	return {"rtt_ms": rtt, "frame_stall_ms": stall, "net_rtt_ms": maxi(0, net - hold), "server_hold_ms": mini(hold, net), "source": source}
