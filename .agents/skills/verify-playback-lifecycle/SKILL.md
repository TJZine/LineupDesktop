---
name: verify-playback-lifecycle
description: Verify native load identity, replacement reclamation and stop completion when changing NativePlaybackState or its libmpv event ordering.
---

# Verify playback lifecycle

A skipped replacement must release its tracking slot. A started predecessor must retain its load ID until its own END_FILE. A stop retry may complete only once, for the latest stop ID, after the event queue drains and the playlist is empty and idle. Breaking these obligations can exhaust the 1024 slots during channel changes, assign a stale event to a new load, or report a stop too early.

From the repository root on a POSIX host with a C++17 compiler, run the bounded explicit-state checker directly against the production header.

```sh
scratch=$(mktemp -d)
c++ -std=c++17 -O2 -Inative native/player_core/playback_lifecycle_model.cpp -o "$scratch/check" && "$scratch/check"
```

The checker explores every prefix allowed by its finite transition system in breadth-first order. There are up to three ordered replace commands with known, distinct playlist IDs, one accepted stop and one optional second accepted stop. A start may skip earlier replacements, and any started predecessor may end late. Replacements wait for a pending stop. After each start or empty-idle barrier the checker fills a copy with fresh loads to the expected available capacity. It also checks incomplete idle observations, duplicate completion and load ownership. The first failing trace is a shortest counterexample within this model.

Compare a counterexample with the load and stop ordering in the [native protocol](../../../docs/native-player-protocol.md#correlation-and-lifetime-rules). Confirm whether the adapter and mpv permit that sequence before changing the model or production code. The model starts at the worker's serialized state transitions. The threaded `player_core_contract` CTest uses fake mpv operations to reject a stop, accept its retry, and check the public retry ID after queued events drain. The `native_playback_state` CTest exercises ordinary FIFO matching, redirect siblings and the capacity limit. A fallback load skipped by a keyed replacement and a redirect child replaced before it starts both remain outside those proofs. The model excludes fallback IDs, redirects, missing required events, duplicate or lost lifecycle events, queue overflow and loads accepted during a pending stop. Device behavior, real mpv timing, fairness and unbounded liveness require other evidence.

## Replay the historical failure

With commit `3d7c6f87fde271ea142b4b98d103b58bdfed7dde` available locally, run the same checker against the exact header from before PR 66 in the disposable directory. Keep the working tree intact.

```sh
mkdir -p "$scratch/player_core"
git show 3d7c6f87fde271ea142b4b98d103b58bdfed7dde:native/player_core/native_playback_state.h > "$scratch/player_core/native_playback_state.h" &&
  c++ -std=c++17 -O2 -I"$scratch" native/player_core/playback_lifecycle_model.cpp -o "$scratch/historical" &&
  "$scratch/historical"
```

Expect exit 1 after accepting loads 0 and 1 and starting load 1. The old mapping for load 0 consumes a slot needed for a future load. Run `"$scratch/check"` again for the current implementation. macOS and Windows CI both select the `playback_lifecycle_model` CTest.

## Coverage record

Last synchronized production revision `309b917c`. Compare [NativePlaybackState](../../../native/player_core/native_playback_state.h) (`AcceptLoad`, `StartFile`, `EndFile`, `RetireLoad`, `AcceptStop`, `ObserveIdle`) and [PlayerCore](../../../native/player_core/player_core.cpp) (`RunCommand`, `EventLoop`, `HandleMpvEvent`) with the [model](../../../native/player_core/playback_lifecycle_model.cpp). If the accepted event orders change, update the transitions and recheck their assumptions. Advance the sync revision after rerunning the model, the historical replay and affected core contracts.
