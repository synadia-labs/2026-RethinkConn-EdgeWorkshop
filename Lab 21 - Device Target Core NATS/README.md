# Lab #21 - Target devices individually avoiding propagation to hub (core nats based)

Summary:

- Allows addressing large number of edge devices (distributed in edge/leaf microcells) without having a massive interest propagation graph out of each leaf
- Purely based on core NATS messaging
- Leverages how account subject mappings in the leaf propagate to the hub.
- It can handle PUB and R/R from hub to the devices
- It allows addressing devices in specific leaves (L1, L2...) or a broadcast to all leaves if location is unknown (ALL)
- It can also be leveraged to handle R/R from devices towards the hub without wide opening _INBOX propagation to the hub (requires some extra work)

How it works:

- The edge/leaf node has a subject mapping (`h2lx.L1.>` --> `edge.>`) defined in the edge account. Similar for all leaves (`h2lx.L2.>`, `h2lx.L3.>` etc.), note that the prefix is unique, to allow targeting each leaf individually.
- This creates a *single* interest propagated to the hub for that `h2lx.L1.>` subject prefix
- Locally, each leaf maps that to subjects `edge.>` that target individual devices/endpoints (and that are blocked from propagating interest to the hub).
- For example device 123 in leaf #1 could be listening locally in `edge.123.>`, and the hub can address it by sending a message to `h2lx.L1.123.whatever`.
- Devices could have other tokens/prefixes to define families of devices as needed (`edge.foo.123.>`); any subtoken under `edge.>` is transparent to the pattern but must be properly matched by the hub. So for device listening to `edge.foo.123.bar.>` the hub would contact `h2lx.L1.foo.123.bar.whatever`.
- There is also a `h2lx.ALL.>` subject that all leaves define and map to the local `edge.>` subjects. This provides a broadcast channel from the hub to all the leaves, useful in case the device location is unknown.

Note on efficiency: keep in mind that messages targeting non existing devices will still flow hub-to-edge. The edge will efficiently discard the message if there is no device subscriber, but the traffic will still flow down to the edge, incurring in some wasted bandwidth.

---

## Setup

Start the lab:

```sh
../workshop.sh start "Lab 21 - Device Target Core NATS"
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

## Hub reaching to devices

Test PUB to a device

```sh
# a device with id=123 in leaf 1 listens in its own subject...
nats --context l1 sub edge.foo.123    # blocks!

# ... can be addressed from the hub using the leaf-mapped subjects
nats --context hub pub h2lx.L1.foo.123 "Hello id-123 at leaf 1"

# ... even if we don't know the right leaf we can still address it, broadcasting to all the leaves
nats --context hub pub h2lx.ALL.foo.123 "Hello id-123 wherever you are"
```

Test R/R from hub to devices. In this case we have opened INBOX leaf->hub (which is generally ok from an interest prop perspective) so we don't need to specify an inbox prefix:

```sh
# start a couple terminals with responders
nats --context l1 reply edge.foo.123 "Hi, I'm 123, in leaf #1"   # blocks!
nats --context l2 reply edge.foo.456 "Hi, I'm 456, in leaf #2"   # blocks!

# query them
nats --context hub request h2lx.L1.foo.123 "Hello id-123, how is life at leaf 1?"
nats --context hub request h2lx.ALL.foo.123 "Hello id-123 how is life wherever you are?"
nats --context hub request h2lx.L2.foo.456 "Hello id-456, how is life at leaf 2?"
nats --context hub request h2lx.ALL.foo.456 "Hello id-456 how is life wherever you are?"

# Of course we could use any valid inbox prefix. In this example `l2h.>` is also open, so we could piggy back on that one:
nats --context hub request h2lx.L1.foo.123 "Hello id-123, how is life at leaf 1?" --inbox-prefix l2h.foo
```

### Subscription analisys in the hub

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

and can be addressed individually from the hub, whatever leaf they are:

```sh
nats --context hub pub h2l.foo.123 "hi device 123"
```

In parallel, check again the subscriptions in the hub - should be much larger now, bad!!

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

Check in the hub the detailed list of subjects interested by the leaves, we  get a long list!

```sh
curl -s "localhost:8222/leafz?subs=1" |
jq -r '
  .leafs[]
  | .subscriptions_list[]
' | sort
```

Once the sub jobs are done after a minute, try the same but using the edge.> subject, that is fenced inside the edge cluster:

```sh
for i in $(seq 1 200); do
  nats --context l1 sub edge.foo.$i --wait=1m &
done
```

and can still be addressed from the hub thru the `h2lx.>` subjects that are mapped to local `edge.>` subjects by each leaf:

```sh
nats --context hub pub h2lx.L1.foo.123 "hi device 123 at leaf 1"
nats --context hub pub h2lx.ALL.foo.123 "hi device 123 at some leaf"
```

This time, no extra interest is propagated into the hub:

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

Check in the hub the detailed list of subjects interested by the leaves, quite short now:

```sh
curl -s "localhost:8222/leafz?subs=1" |
jq -r '
  .leafs[]
  | .subscriptions_list[]
' | sort
```

Note the few `h2lx` subjects, `h2lx.L1.>` and alike. These are the ones doing the magic.
The leaves create them due to the subject mapping they locally do in the account definition, and effectively hide actual interest from devices (listening in the mapped-to subjects, `edge.>`).
So this pattern allows individual addressing of devices (one way or R/R), without creating a large interest graph up to the hub.

As noted previosly, the interest is in place even if there is no device listening in a leaf. So the messages addressing devices in a specific leaf will be forwarded to that leaf even if devices are not there, and then dropped/ignored by the leaf. This is a little un-efficiency to keep in mind, network bandwidth is being wasted in that case.

---

## Devices reaching to hub (Request/Reply)

Devices issuing request/reply (R/R) operations toward the hub require a reply subject for responses, typically an `_INBOX.>` subject.

With large numbers of edge devices, it is generally not advisable to open `_INBOX.>` hub->leaf. Doing so can significantly impact hub scalability due to:

- A *very large* in-memory interest graph.
- Extensive interest propagation activity as device requests are created and completed.

While the latter can be partially mitigated (see Lab #20: Muxed Request/Reply), interest storms may still occur when leaf nodes disconnect and reconnect, or when devices frequently join and leave the system.

### Subscription analisys in hub

Start a service in the hub. We use a prefix (`l2h.>`) that is reachable from the leaves. We include a sleep period to slow things down and have time to analyze things.

```sh
nats --context hub reply --sleep=10s l2h.foo.service "Response from the HUB to: {{Request}}"
```

Get total number of subscriptions for the hub:

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

Start a few (200) edge requests to the hub. In this example _INBOX.> is blocked hub-to-leaf, but we can use the `h2l.>` prefix that is open, the outcome will be the same:

```sh
# they will be active for 1 minute
for i in $(seq 1 200); do
  nats --context l1 request --timeout=60s --inbox-prefix=h2l l2h.foo.service "Request from device $i at leaf #1" &
done
```

Get total number of subscriptions for the hub again:

```sh
curl -s "http://localhost:8222/varz" | jq .subscriptions
```

It should be much larger, imagine with hundreds of thousands of devices!!

Check the detailed list of subjects, tons of `h2l.xxx.yyy` subjects, the inboxes waiting for the response:

```sh
curl -s "localhost:8222/leafz?subs=1" |
jq -r '
  .leafs[]
  | .subscriptions_list[]
' | sort
```

Upcoming versions of NATS are going to improve inbox handling in leaf nodes, and this will not be a problem anymore.
In the meantime, keep on reading on how to approach this efficiently, where we apply to edge reply-to inboxes the same pattern described above for hub-to-edge device addressing.

### Device inbox prefix

Devices should use a custom inbox prefix that leverages the leaf subject mapping described previously in this lab. This approach avoids creating additional interest propagation toward the hub while still allowing responses to be routed back to the originating device.

To construct the appropriate inbox prefix, the device must either:

- Know which leaf node it is connected to and use the right leaf prefix (something like prefix `h2lx.L1` in this lab example), or
- Use a broadcast prefix as a fallback (a simpler but less efficient approach) - the `h2lx.ALL` prefix in this lab example

Current NATS client libraries allow a custom inbox prefix to be specified only as a connection option. As a result, that inbox prefix can only be defined *before* the client connects and cannot be modified afterward. Also, due to the subject mapping in the leaf, the reply-to subject specified by the device is different from the subject on which it actually listens for responses (`h2lx.L1.>` vs `edge.>` in the lab example). As a result of these two facts, we cannot really use the conventional request API provided by the NATS client library. Instead, the request must be explicitly implemented using a  subscription for the response subject and a separate publish operation for the request:

```sh
# service in the hub (we use the l2h prefix as that subject prefix is open leaf->hub in this lab)
nats --context hub reply l2h.bar-service "Response from the HUB to: {{Request}}"   # blocks!

# in a separate terminal we simulate the device foo.123, that creates an inbox subscription with the right local prefix
# it should receive here the responses from the hub for the device requests that we'll send in subsequent commands
nats --context l1 sub edge.foo.123.ABC.XYZ   # blocks!

# and in a separate terminal, we simulate the same device foo.123 sending the actual request to the hub service, swapping in the reply-to inbox subject the prefix that the hub should use to reach it
nats --context l1 pub l2h.bar-service --reply=h2lx.L1.foo.123.ABC.XYZ "Request from device foo.123 at leaf #1"
# or using the ALL broadcast if the device does not know the leaf connected at
nats --context l1 pub l2h.bar-service --reply=h2lx.ALL.foo.123.ABC.XYZ "Request from device foo.123, at an unknown leaf"
```

The device could actually find out easily the server and cluster it is connected to, and use that info to define the right `h2lx.Lx` prefix:

```sh
nats --context l1 req -r '$SYS.REQ.USER.INFO' "" | jq -r '"h2lx." + .server.cluster'
```

This pattern works, but makes the device logic a bit more complicated: having to find where it is connected and then not being able to use the standard NATS client request API.
Lets consider an alternative that shifts that complexity to the hub side.

### Tweaking reply-to on the hub side

We can keep the edge devices doing a regular R/R to a hub service, using the local inbox prefix that does not propagate up to the hub (the local `edge.>` prefix that we defined in this lab).
Instead, the hub service will have to tweak the received reply-to subject and use the correct prefix to route the response back to the right leaf node.

The device could provide its leaf location as part of the request payload, or the hub services may have alternative mechanisms for determining device location, such as Auth Callout metadata (kept in a device-to-leaf KV store).

A particularly elegant approach is to enforce origin tracking directly in the request subject. This can be implemented transparently through per-leaf subject mappings, where the leaf injects a token with its identity. Check the `lx2h.>` mapping shown in each leaf server configuration file in this lab. With this approach, devices and client applications remain completely unaware of the origin-tracking mechanism, the hub does not need to keep a database (KV) with device-to-leaf assignments, and is completely dynamic, where devices that reconnect to a new leaf will instantly use the right origin token.

Once the hub service knows which leaf node hosts the device, it can apply custom logic to modify the reply subject allowing responses to be routed directly to the correct leaf.

Here is a clunky way to showcase this in the lab example (nats-cli does not let us tweak reply-to subjects, so we have to implement the hub service as a separate subscriber and publisher):

```sh
# Here we have "bar-service" that processes requests for ever. Note the prefix lx2h.*, it is open leaf->hub so the edge devices will reach the service  
while true; do
  # SUBSCRIBER - Note the * wildcard in the subscription -- we'll receive the origin leaf of the caller injected there!
  received=$(nats --context hub sub 'lx2h.*.bar-service' --count=1)

  received_subject=$(printf '%s\n' "$received" | awk -F'"' '/Received on/ {print $2}')
  reply_subject=$(printf '%s\n' "$received" | awk -F'"' '/Received on/ {print $4}')
  payload=$(printf '%s\n' "$received" | tail -n +2)

  # The leaf origin that we'll use to route back the response is the 2nd token in the subject: lx2h.L1, Lx2h.L2, etc. 
  # BTW, review also the NATS hub config file, the leaf permissions are defined in such a way that leaves can not impersonate other leaves
  leafid=$(printf '%s\n' "$received_subject" | cut -d. -f2)

  # Here we tweak the reply-to subject: we'll replace "edge" with the right prefix on the hub side (h2lx.L1 or whaever is the right leaf id)
  target_subject=$(printf '%s\n' "$reply_subject" | sed "s/^edge\./h2lx.${leafid}./")

  # send back the response to the device
  nats --context hub pub "$target_subject" "This is the hub responding to a device in leaf $leafid to the request with payload: $payload"
done
```

And now the devices can just invoke the service directly!:

```sh
nats --context l1 request lx2h.bar-service "hi from device 123 at leaf #1" --inbox-prefix edge.foo.123
sleep 1
nats --context l2 request lx2h.bar-service "hi from device 456 at leaf #2" --inbox-prefix edge.foo.456
sleep 1
nats --context l3 request lx2h.bar-service "hi from device 789 at leaf #3" --inbox-prefix edge.bar.789
```

No interest prop will happen toward the hub, that will be happy to handle a huge number of edges/devices without getting stressed with tons of inbox interests around.

All the needed machinery is invisible for the devices, at the cost of some complexity on the hub side (tweaking the reply-to subjects).

---
