# Lab #10 - Another little mess with JetStreams (Domain lottery)

- Hub + leafs, East-West blocked (isolate:true and also explicit block for `telemtry.>` subject)
- Each leaf has its own TELEMETRY stream (same name, same capture pattern)
- Same JS Domain name (L) in all leafs
- No JS Domain name in hub

---

## Stream setup at the leafs

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
```

Check the content of the streams:

```sh
echo "-- leaf 1 --"
nats --context l1 stream view TELEMETRY
echo "-- leaf 2 --"
nats --context l2 stream view TELEMETRY
echo "-- leaf 3 --"
nats --context l3 stream view TELEMETRY
```

All good in the streams :-)

---

## Lottery in the hub

Now view the stream from the hub: specify the JS Domain (ie. instead of using the local `$JS.API.>` it will use `$JS.L.API.>`. Use `--trace` to see details)

```sh
# Run multiple times
nats --context hub --js-domain L stream view TELEMETRY 
```

Everytime we run that we'll get different results. Sometimes more than 1 response will do the cut of the nats-cli logic.

Check the messy interaction with a simpler `nats stream info`.

```sh
# listen to the info responses
nats --context hub sub '_INBOX.>'

# run in a separete terminal:
nats --context hub --js-domain L stream info TELEMETRY
```

We get responses from the 3 leaf nodes, nats-cli will pick whichever gets back first.

As all leafs have the same domain, they listen in the same API `$JS.L.API.>`. The hub is sending the command to all of them.
If you question why the request is not send to only one of them, round-robin (as with regular dqueue service pools in NATS): this is related to how Domains work internally (using account subject mapping in leaf nodes). It is an internal implementation detail, and could change in the future.

Make sure leaf nodes have a _unique_ domain name!

---

## JetStream Leaf to hub access

Create a stream in the hub:

```sh
nats --context hub stream add FOO --subjects="foo.>" --defaults
nats --context hub stream info FOO
```

Lets access the stream from the leaf 1:

```sh
nats --context l1 stream info FOO --js-domain ......mmmmmm...what??
```

Right, we can't complete that command. We can't reach the $JS API in the hub from the leaf, as there is no JS domain name defined for the hub.

So if the leafs need to access streams in the hub (directoy or for sourcing/mirroring) the hub also needs a domain name.

---
