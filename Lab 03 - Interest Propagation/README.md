# Lab #3 - Subject Interest Propagation (side lab)

Monitor interest propagation between servers (hub<-->leafs in this case)

Repeat the tests with the server config files of Lab #1 (leafs with same cluster name) and Lab #2 (leafs with unique names).

---

## Setup notes

Similar setup to previous labs, but we'll start the servers with tracing on, in separate terminals.
Make sure no clients are dangling around from previous tests, they may reconnect (be safe with `killall nats`)

```sh
$ ../workshop.sh start 1 --trace
$ ../workshop.sh logs
```

Or

```sh
$ ../workshop.sh start 2 --trace
$ ../workshop.sh logs
```

Or manually:

# terminal 1
nats-server -c hub.conf --trace   # blocks!
# terminal 2
nats-server -c l1.conf --trace   # blocks!
# terminal 3
nats-server -c l2.conf --trace   # blocks!
# terminal 4
nats-server -c l3.conf --trace   # blocks!
```

---

## Subscription test

Once servers are connected and logs stable, test these commands, and review the server consoles:

From hub, subscribe to a few subjects:

```sh
nats --context hub sub foo bar baz
```

Review the servers consoles. Notice the `LS+` messages that the servers exchange (note the directional arrows)
You can run a few more of the above to add extra subscribers to the same subjects.
Then stop the `nats sub` commands and review the logs again.  
Notice the `LS+` and `LS-` messages exchanged between hub and leaf(s).
When subscribers on a subject decrease to 0, notice the `DELSUB` message too.

Repeat the same tests from the leaf 1:

```sh
nats --context l1 sub foo bar baz
```

If East-West is active, the `LS+`/`LS-`/`DELSUB` messages should also be forwarded to the other leafs.

Leafs can operate on non permanent connections. Bruteforce that by stopping the hub, or a leaf with active subscriptions: a disconnect will also trigger DELSUB messages. When you restart the node (or the connnection re-establishes), the `LS+` exchanges will come back.

---
