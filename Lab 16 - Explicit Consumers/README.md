# Lab #16 - Hub sources & merges streams from leafs

- Telemetry Store & Forward & Merge in hub stream
- Minimum set of $JS API subjects to support the sourcing
- Uses the new explicit consumer option for sourcing/mirroring
- Consumers for the sourcing/mirroring are created explicitly by the user. They are fully observable.
- These consumers can handle sourcing/mirroring from interest/workqueue streams, yay!

The manually created consumers must meet some requirements

- Push consumers, using the new `flow_control` ack mode.
- The target delivery subject is arbitrary. In this example we reuse the standard $JS.S.>
- `max_ack_pending` is respected.
- Both Flow control and ACK subjects are needed.
- Both stream+consumer names and delivery subjects should be unique (we use leaf # to add uniqueness)

---

## Setup

```sh
../workshop.sh start 16
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
```

Create the consumers in each sourced stream (note that the `$JS.S.>` subject prefix in the delivery subject is arbitrary. Anything open leaf->hub would work. Using this one here for consistency with previous implementation of sourcing/mirroring)

```sh
nats --context l1 consumer create --ack=flow_control --deliver=all --max-pending=999 TELEMETRY l1-hub-src0 --target '$JS.S.TELEMETRY.l1-hub-src0' --defaults
nats --context l2 consumer create --ack=flow_control --deliver=all --max-pending=999 TELEMETRY l2-hub-src0 --target '$JS.S.TELEMETRY.l2-hub-src0' --defaults
nats --context l3 consumer create --ack=flow_control --deliver=all --max-pending=999 TELEMETRY l3-hub-src0 --target '$JS.S.TELEMETRY.l3-hub-src0' --defaults
```

Merged stream in hub:

```sh
nats --context hub stream add --config hub_mergetelemetry.json

# check status - should have data replicated from the 3 leafs
nats --context hub stream report
```

---

Compare the hub config files with the previous lab, the difference in required permissions in both directions for the sourcing to work correctly.
