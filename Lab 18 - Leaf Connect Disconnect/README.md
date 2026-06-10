# Lab #18 - Leaf connect/disconnect

Previous to NATS 2.14, leaf configuration updates required restarting the updated server(s).

Starting 2.14 leaf configuration can be updated and hot reloaded (-HUP signal or remote request through the system account).

Also included in this Lab: a pattern to link/unlink a leaf externaly (works with any NATS versions).

---

## Hot-reload leaf configuration

Start the hub and 3 leafs as usual

```sh
../workshop.sh start "Lab 18 - Leaf Connect Disconnect"
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

Check the topology, from the hub:

```sh
nats --context syshub server ls
```

Only leaf 1 is connected.

Leaf 2 and Leaf 3 are also operational, but not connected to the hub:

```sh
nats --context sysl2 server ls

nats --context sysl3 server ls
```

Edit the hub configuration file `hub.conf`, uncomment the 2 lines that establish the reverse-leaf to leaf 2:

```yaml
  remotes [
    { urls: ["nats-leaf://el:x@localhost:7442"], account: APP, hub: true }
    { urls: ["nats-leaf://sl:x@localhost:7442"], account: SYS, hub: true }
  ]
```

send a -HUP signal to the hub server to reload the config:

```sh
nats --context=syshub request '$SYS.REQ.SERVER.PING' "" --replies=0 --timeout=1s --raw | \
jq -r 'select(.server.name == "hub") | .server.id' | \
xargs -I {} nats --context=syshub req \$SYS.REQ.SERVER.{}.RELOAD ''

# being lazy this works too:
killall  -HUP nats-server
```

Now the leaf 2 should be connected to the hub:

```sh
nats --context syshub server ls
```

---

## Linking leaf 3 externally using a gate leaf

Connecting leaf 3 is done using an intermediate leaf node (gate node). It can be started/stopped on demand as needed. Nothing is required to be done on neither the hub nor the leaf 3.
The gate node connects as a regular leaf towards the hub, and behaves as a hub (reverse leaf connection) towards leaf 3.

Start the gate node for leaf 3:

```sh
nats-server -c l3gate.conf &
```

Now the leaf 3 should be connected to the hub, daisy chained across the gate node:

```sh
nats --context syshub server ls
```

This pattern avoids reconfigs in the hub. Being a leaf --> to --> hub connection has other advantages with connectivity on multi node clusters (one link leaf-node to hub-cluster vs. each hub-cluster-node to each leaf-node).

---
