# Lab #15 - Hub sources & merges streams from leafs

- Telemetry Store & Forward & Merge in hub stream
- Minimum set of $JS API subjects to support the sourcing
- Uses the default sourcing ephemeral consumers and default delivery subjects (`$JS.S.>`)
- These consumers are special, defined internally and not visible
- They are not good when sourcing interest/workqueue streams (check next lab for that)

---

## Setup

```sh
../workshop.sh start 15
```

Direct equivalent, from this lab directory:

```sh
# terminal 1
nats-server -c hub.conf
# terminal 2
nats-server -c l1.conf
# terminal 3
nats-server -c l2.conf
# terminal 4
nats-server -c l3.conf
```

---

Create the streams in the leafs

```sh
nats --context l1 stream add TELEMETRY --subjects="telemetry.*.>" --defaults
nats --context l2 stream add TELEMETRY --subjects="telemetry.*.>" --defaults
nats --context l3 stream add TELEMETRY --subjects="telemetry.*.>" --defaults
```

Some devices in each leaf publish some telemetry

```sh
nats --context l1 pub --jetstream telemetry.device1.temp "1"
nats --context l2 pub --jetstream telemetry.device2.temp "2"
nats --context l3 pub --jetstream telemetry.device3.temp "3"
nats --context l1 pub --jetstream telemetry.device4.temp "4"
nats --context l2 pub --jetstream telemetry.device5.temp "5"
nats --context l3 pub --jetstream telemetry.device6.temp "6"
nats --context l1 pub --jetstream telemetry.device1.temp "7"
nats --context l2 pub --jetstream telemetry.device2.temp "8"
nats --context l3 pub --jetstream telemetry.device3.temp "9"
```

Merged stream in hub:

```sh
nats --context hub stream add --config hub_mergetelemetry.json

nats --context hub stream report
```

---

Next lab does the same but using the new explicit consumer option for sourcing/mirroring.
Compare the hub config files, the difference in required permissions in both directions for the sourcing to work correctly.

---

## Merging limits

How many sources can be merged?

- Destination stream I/O bandwidth limits will normally determine this. Network could also saturate. Use case specific: a few bulky sourced streams vs a lot of low traffic ones.
- Assuming I/O bandwidth not a bottleneck, a few thousands are possible, but...
- ...on server restart the destination stream leader performs a linear backward scan to find out last message per source, while locking other stream operations (!)
- Optimization to avoid this coming soon!
