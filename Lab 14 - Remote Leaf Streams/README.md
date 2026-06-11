# Lab #13 - Hub remote accesing a stream in leaf

- Hub with restricted access to streams in leafs
- leaf 1 - hub can access the full JetStream API in the leaf (incl. push consumer subjects)
- leaf 2 - hub can only admin consumers of a TELEMETRY stream in the hub (CRUD ops. and push consumer subjects for mirror/source)
- leaf 3 - very restricted accesss: just to an existing (pre-created) _pull_ consumer in the leaf

Important: $JS.ACK.> (consumer acks) and $JS.FC.> (consumer flow control) are not JS Domain aware. Make sure STREAMNAME+CONSUMERNAME are unique from the hub perspective.
Placing the leaf JS Domain name as part of the consumer names will meet that requirement. For cross-account stream sharing, adding the account may help too.  Mirror/Sourcing will create random consumer names and meet the requirement too.
NATS 2.14 is adding domain/account safe APIs for these two; they will be fully enabled in 2.15 ([https://docs.nats.io/release-notes/whats_new/whats_new_214#domain-aware-acknowledgement-and-flow-control-subjects])

---

## Setup

```sh
../workshop.sh start 13
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

For leaf 1, the hub can perform all kind of operations

```sh
nats --context hub --js-domain=L1 stream ls
nats --context hub --js-domain=L1 stream add FOO --subjects="foo.>" --defaults   # (it can't send data to the foo.> subjects though, as that is not open hub->leaf)
nats --context l1  pub --jetstream foo.bar "hi"   # so we send data locally at the leaf
nats --context hub --js-domain=L1 stream view FOO
# and so on...
nats --context hub --js-domain=L1 stream rm FOO --force
nats --context hub --js-domain=L1 stream view TELEMETRY
```

For leaf 2, the hub can perform only consumer operations in stream TELEMETRY

```sh
nats --context hub --js-domain=L2 stream ls  # this will not work, not allowed to list streams
nats --context hub --js-domain=L2 stream view TELEMETRY
nats --context hub --js-domain=L2 stream get TELEMETRY 1    # this one will fail unless MSG.GET unblocked
nats --context hub --js-domain=L2 consumer create TELEMETRY l2-hub-consumer --pull --defaults
nats --context hub --js-domain=L2 consumer next TELEMETRY l2-hub-consumer --ack
# the new consumer pause and reset ops (NATS 2.14.x) also works
nats --context hub --js-domain=L2 consumer reset TELEMETRY l2-hub-consumer --sequence=0 --force
nats --context hub --js-domain=L2 consumer pause TELEMETRY l2-hub-consumer 1h --force
nats --context hub --js-domain=L2 consumer info TELEMETRY l2-hub-consumer
```

For leaf 3, restrictions are harder, we can just use an existing consumer created locally at the leaf

```sh
# first create the consumer locally in the leaf
nats --context l3 consumer create TELEMETRY l3-c0 --pull --ack=explicit --defaults

# now the hub can use it
nats --context hub --js-domain=L3 consumer next TELEMETRY l3-c0 --ack
nats --context hub --js-domain=L3 consumer info TELEMETRY l3-c0

# Reset and pause are not enabled and will not work
nats --context hub --js-domain=L3 consumer reset TELEMETRY l3-c0 --sequence=0 --force
nats --context hub --js-domain=L3 consumer pause TELEMETRY l3-c0 1h -force
# What JetStream API subjects should be allowed to enable the consumer reset & pause operation for l3?
```

---
