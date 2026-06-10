# Lab #6 - Remote leaf isolation (Reverse hub)

This lab uses the reverse connection form for leafnodes: the hub connects out to
the leaf servers, and each leaf listens for incoming leafnode connections.

The key option in this setup is `isolate` on a hub remote:

```hcl
{ urls: ["nats-leaf://l:x@localhost:7452"], account: APP, hub: true, isolate: true }
```

That isolates the selected remote from east-west interest originating locally at
the hub. In this setup, only `l3` has east-west interest propagation disabled.

---

## Setup

```sh
../workshop.sh start 6
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

Use trace mode when you want to inspect the leaf interest protocol:

```sh
../workshop.sh restart 6 --trace
../workshop.sh logs
```

Or add `--trace` to each direct `nats-server` command.

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

As in the request-isolation example from Lab 05, interest propagation into `l3`
is blocked, which means traffic out of `l3` toward other leafs is blocked.

---

## Note

As of 2.14.2, subscriptions in the hub will neutralize the effect of isolation
for that subscribed subject. A subscriber in the hub creates north-south
interest, and as a side effect east-west will be re-enabled for that subject.
