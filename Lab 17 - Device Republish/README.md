# Lab #17 - Target devices individually with stream republish

Summary:

- Allows addressing large number of edge devices (distributed in edge/leaf microcells) without having a massive interest propagation graph out of each leaf
- Mimics core NATS SLA, no ACKS, best effort. Can easily be adapter for higher SLA.
- Each edge/leaf microcell has a small stream that muxes interest from all the devices into a single subject subscription
- Stream republish is used to demux the messages and target the devices

Limitations:

- No direct support for reply subjects. Reply subjects must be specified in the payload or implicitly defined somewhere else, and replies published separately.

---

## Setup

Start the lab:

```sh
../workshop.sh start "Lab 17 - Device Republish"
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

Leafs lock `edge.>` locally (block interest leaving the edge or coming in): in this setup the hub is already locking down most subjects using permissions, but just in case the leaf also locks `edge.>` using `deny_exports/imports`

Each leaf uses an LMUX stream that captures 2 subjects:

- Messages addressed just to one specific leaf: `lmux.Lx.>`
- Messages addressed to all the leafs: `lmux.ALL.>`

Only these 2 subjects propagate up to the hub.

To create the streams in each leaf:

```sh
for i in {1..3}; do
  nats --context l$i stream add LMUX \
    --subjects="lmux.L$i.>","lmux.ALL.>" \
    --no-ack \
    --retention=limits \
    --discard=old \
    --max-age=10s \
    --max-bytes=10M \
    --transform-source="lmux.*.>" \
    --transform-destination=">" \
    --republish-source=">" \
    --republish-destination="edge.>" \
    --defaults
done

for i in {1..3}; do
  nats --context l$i stream report
done  
```

Notes:

- No acks are sent, ie. best effort: the LMUX stream is just an artifact to reduce interest graphs for core nats messaging --> at most once semantics
- Discard msgs based on `--max-age` --> improved performance, and core NATS SLA ==> very short lifespan is enough (here we do 10 seconds)
- Removes the `lmux.Lx` / `lmux.ALL` prefixes for captured messages
- Republish ==> this is the demux service inside the leaf node!! It republishes into the local `edge.>` subject space that the devices can be listening into.
- About `lmux.ALL`: if no local subscriber in the leaf for an event, it will be efficiently dropped right away (min. resources consumed)

Test the pattern:

```sh
# a device with id=123 in leaf 1 listens in its own subject...
nats --context l1 sub edge.foo.123

# ... can be addressed from the hub using the LMUX stream capture subjects
nats --context hub pub lmux.L1.foo.123 "Hello id-123, how is life at leaf 1"

# ... even if we don't know the right leaf we can still address it, broadcasting to all the leafs
nats --context hub pub lmux.ALL.foo.123 "Hello id-123 wherever you are"
```

---

## Subscription analisys in the hub

Get total number of subscriptions for the hub:

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

Start a few edge subscribers with unique subjects in an unblocked subject:

```sh
# they will be active for 1 minute
for i in $(seq 1 200); do
  nats --context l1 sub h2l.foo.$i --wait=1m &
done
```

and can be addressed from the hub

```sh
nats --context hub pub h2l.foo.123 "hi device 123"
```

In parallel, check again the subscriptions in the hub - should be much larger now

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

Once done after a minute, try the same but using the edge.> subject, that is fenced inside the edge cluster:

```sh
for i in $(seq 1 200); do
  nats --context l1 sub edge.foo.$i --wait=1m &
done
```

and can still be addressed from the hub thru the LMUX stream republish

```sh
nats --context hub pub lmux.L1.foo.123 "hi device 123 at leaf 1"
nats --context hub pub lmux.ALL.foo.123 "hi device 123 at some leaf"
```

This time, no extra interest is propagated into the hub:

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

This way the many devices are still individually addresable, without creating a large interest graph up to the hub.

---
