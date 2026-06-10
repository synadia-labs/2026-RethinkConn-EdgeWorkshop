# Lab #9 - A little mess with JetStreams (captured subjects leak)

- Hub + leafs, different cluster names, East-West enabled
- No restrictions on permission North-South
- Each leaf has its own TELEMETRY stream (same name, same capture pattern)

What will happen?

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
```

Check the content of the streams:

```sh
nats --context l1 stream view TELEMETRY
nats --context l2 stream view TELEMETRY
nats --context l3 stream view TELEMETRY
```

Streams in each leaf will also pull in telemetry events from other leafs, as neither interest nor permissions are setup to block traffic.

In fact each stream returns its own ACK as feedback of the event capture.

```sh
# Listen the inbox subjects to monitor stream ACK responses:
nats --context l1 sub "_INBOX.>"
# In another terminal send an event to the stream in leaf 1
nats --context l1 pub --jetstream telemetry.device4.temp "4" 
```

You'll see multiple ACKS (x3) for a single event being captured in the different TELEMETRY streams (l1, l2, l3)

---

Even with East-West blocked (isolate:true or same-cluster-name leafs) the same will happen if a stream in the hub captures the same subjects `telemetry.*.>`.

Clients publishing to streams will use _INBOX (or other prefix) to get confirmation ACKs. These will also propagate wasteful interest to the other leafs!

Good practice: *block everything leaf-hub and then unblock just what is needed*

---

## Side note - Flight recorder pattern

Inside a cluster (or supercluster) JetStreams does not allow capturing same subjects (or overlapping subsets) in multiple streams.

But as seen above, leaf nodes allow us to do that. Though in previous example this was an anti-pattern, this can be useful in other use cases:

Create a leaf node to a main cluster, with a stream that captures the subjects of interest (or even everthing!) independently of JS streams in the main cluster.

Make sure that the stream does not send ACKS (`nats stream add --no-ack ...`) and silently captures the subjects of interest. Just in case set `permissions.publish.deny:[">"]` for the leaf user.

This is a great way to log capture everthing for further study as part of a debug session, for example.
