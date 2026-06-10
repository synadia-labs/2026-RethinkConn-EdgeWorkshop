# Lab #5 - More on `isolate` and `request_isolation` for east-west traffic in leaf nodes (side lab)

Communications from one leaf to another leaf across the hub is called "east-west" traffic.
Communications going just from leaf to hub and viceversa is "north-south" traffic.

By default a hub will brokerage interest across leafs, to support east-west traffic. This can impose a high burden tracking too many subjects: interest tables at the hub and all the leafs can take a lot of memory.
Also on leaf disconnect/reconnect, all the interest table needs to be shared again with the leaf, extending the connection time (potentially stalling it for very large interest maps).

In typical cases, east-west is not needed (or can be reduced to a very small set of subjects), so blocking east-west is desirable as a first measure to reduce memory consumption at the leafs.

Previously (before NATS 2.12), the way to get this kind of east-west isolation was using a workaround: set same cluster name for all the leaf nodes. That way the hub assumes that all the leafnodes are part of the same cluster and interconnected directly (though they are not), and the hub will refrain from brokeraging subject interest across them. This effectively disables east-west interest propagation across the hub.

It is now possible to configure leafnode subject interest isolation in three ways (NATS 2.12 onwards). This lab covers the first two:

1. For all leafnode connections on the hub using the top-level `isolate_leafnode_interest` or `isolate` option in the leafnodes block
2. Asking the remote side to isolate us from east-west interest originating remotely using the `request_isolation` option in the remotes config (which, in turn, adds the isolate flag into the leaf CONNECT info)

The reverse-connection form, where the hub connects to leafs with `remotes[].hub:true`, is covered in Lab 06.

https://github.com/nats-io/nats-server/pull/7277

Note that the hub will still get interest from/to the leafs. There are other mechanisms to limit that (user permissions & remotes deny_import/export)

---

## Setup

```sh
../workshop.sh start 5
../workshop.sh logs
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

## Subscription tests

Run the scripted subscriber view to see which leafs receive each message:

```sh
./demo.sh
```

Or manually:

```sh
nats --context l1 sub foo
nats --context l2 sub foo
nats --context l3 sub foo

nats --context hub pub foo "hello from hub"
nats --context l1 pub foo "hello from leaf 1"
nats --context l2 pub foo "hello from leaf 2"
nats --context l3 pub foo "hello from leaf 3"
```

Outcomes will vary depending on the setup as shown below.

---

## 1. Isolate at the hub

Set hub `isolate:true` to block leaf->hub->leaf *interest* propagation, not the actual traffic or the interest leaf->hub.
(Enable trace:true in the hub and leafs to see how LS+ messages propagate around, or start the servers with `--trace` option)

This option will disable east-west traffic across all nodes.

---

## 2. Request isolation

`request_isolation` at a leaf will disable east-west interest prop from other leafs, only at that leaf.

Set hub `isolate:false` to enable east-west traffic for other leafs (l1, l2). But for l3 we have set `request_isolation:true` in its config.
(Enable tracing in the hub to see the isolation request in the CONNECT message of leaf l3)

Note that we blocked interest propagation *into* leaf 3, that means blocking traffic *out* of leaf 3 towards other leafs.

---

## Note

As of 2.14.2, subscriptions in the hub will neutralize the effect of isolate/request_isolation: a subscriber in the hub will generate north-south interest on a specific subject set, and as a side effect east-west will be re-enabled for *that* subscribed subject.
You can test this with `nats --context hub sub foo`, in any of the previous tests east-west will be re-enabled for 'foo'.
This may change in future releases.

---
