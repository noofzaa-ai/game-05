# Local netfox patches

Upstream baseline: netfox1.35.3, commit c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4. Original distribution remains unchanged in tools/netcode/vendor/netfox-1.35.3. Active copy under addons/netfox differs as documented below.

## Pause scheduler phase (2026-10-28)

`network-time.gd::_loop()` previously reset `_tick` to reference time after a stall while retaining the stretched stepping clock and next-tick phase. When those clocks had an offset, later time stretching removed the clock offset but left a permanent tick-ID offset. A deterministic2s stall at0.8/1.25 prior stretch reproduced +26/-28 ticks after3s recovery. This crosses our server's +24 future input bound; increasing that bound would hide the defect.

The pause branch now rebases stepping clock, next-tick deadline and tick label to one reference timestamp and resets stretch to1.0. It keeps the upstream pause policy of discarding elapsed pause simulation; no input validation is loosened. The same deterministic test gives2ticks in both cases (within normal loop/floor phase). Reproduction: tests/netfox_pause_clock_contract.gd, before/after logs in build/netfox-migration/pause-clock-{before,after}.log.

Boss actual Web candidate3 showed client network4050/reference4009, rejected1273 future_window inputs. This is consistent with the reproduced bug; actual Safari candidate4 subsequently showed network/reference10300/10301, accepted1188, future_window0 (past_history6 remains). Boss then reported much smoother real play. This supports the phase fix; extended combat/co-op acceptance and other CPU/replay/teardown issues remain separate. See online_lag_netfox_summary_20261028_TH.md.
